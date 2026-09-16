/**
 * GP-Next 的 Tauri 兼容层（注入到网页 document-start 的脚本）。
 *
 * 背景：GP-Next 面板前端原本跑在 Tauri 桌面容器里，文件读写 / 另存为 / 打开外链全部通过
 * `window.__TAURI_INTERNALS__.invoke(cmd, args, headers)` 调后端。payload 的 index.html 里自带一个
 * 用 localStorage 伪造文件系统的 polyfill，但实现残缺（写入必抛异常且被静默吞掉、zip 读不出二进制、
 * read_dir 把带点的文件名判成目录、默认 settings.json 的键前后不一致），因此这里在 document-start
 * 阶段抢先定义同名对象——polyfill 只在 `if (!window.__TAURI_INTERNALS__)` 成立时才安装，于是自动让位。
 * 之后所有命令经 `window.__gpNextNative.invoke` 交给 ArkTS 侧真正落盘。
 *
 * 两个必须遵守的协议细节（来自 payload 的 @tauri-apps/plugin-fs 绑定）：
 *  - `read_text_file` / `read_file` 的返回值会被 `Uint8Array.from(...)` + `TextDecoder` 处理，
 *    所以原生必须回传**字节**；本脚本负责 base64 → Uint8Array 的还原。
 *  - `write_text_file` 把路径放在**第三个参数** `headers.path`（URI 编码），体是 Uint8Array。
 *
 * 注意：API 12 的 javaScriptOnDocumentStart 按字典序执行脚本，故整体只用一条 ScriptItem；
 * 且本字符串是 ArkTS 模板字面量，脚本内不得出现反引号与 "\\${" 序列。
 */
export const GPNEXT_SHIM: string = `(function () {
  'use strict';
  if (window.__gpNextNativeReady) { return; }

  var callbacks = {};
  var nextCallbackId = 1;

  function bytesToBase64(bytes) {
    var text = '';
    var CHUNK = 0x8000;
    for (var i = 0; i < bytes.length; i += CHUNK) {
      text += String.fromCharCode.apply(null, bytes.subarray(i, i + CHUNK));
    }
    return btoa(text);
  }

  function base64ToBytes(text) {
    var binary = atob(text);
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) { bytes[i] = binary.charCodeAt(i); }
    return bytes;
  }

  function serialize(value) {
    if (value === null || value === undefined) { return value; }
    if (value instanceof Uint8Array) { return { __gpNextBytes: bytesToBase64(value) }; }
    if (value instanceof ArrayBuffer) { return { __gpNextBytes: bytesToBase64(new Uint8Array(value)) }; }
    if (Array.isArray(value)) {
      var list = [];
      for (var i = 0; i < value.length; i++) { list.push(serialize(value[i])); }
      return list;
    }
    if (typeof value === 'object') {
      var mapped = {};
      for (var key in value) {
        if (Object.prototype.hasOwnProperty.call(value, key)) { mapped[key] = serialize(value[key]); }
      }
      return mapped;
    }
    return value;
  }

  function invoke(command, args, headers) {
    if (!window.__gpNextNative || typeof window.__gpNextNative.invoke !== 'function') {
      return Promise.reject(new Error('[gp-next-shim] 原生桥尚未就绪: ' + command));
    }
    var request = JSON.stringify({
      command: String(command || ''),
      args: serialize(args === undefined ? {} : args),
      options: serialize(headers === undefined ? null : headers)
    });
    // ArkWeb 的 JavaScriptProxy 返回的是原生 JSPromise，它的 .then() 不是标准 Promise 链：
    // 回调的返回值会被直接丢弃（实测恒定解析成 null），于是 read_dir 变成 null，GP-Next 的
    // discoverPacks 立刻抛 "n is not iterable"。必须先经 Promise.resolve() 归一成标准 Promise。
    return Promise.resolve(window.__gpNextNative.invoke(request)).then(function (raw) {
      var response = JSON.parse(raw);
      if (!response.ok) {
        var error = new Error(response.error || '原生桥执行失败');
        error.code = response.code || 'gp_next_error';
        throw error;
      }
      var value = response.value;
      if (value && typeof value === 'object' && typeof value.__gpNextBytes === 'string') {
        return base64ToBytes(value.__gpNextBytes);
      }
      return value;
    });
  }

  function transformCallback(callback, once) {
    var id = nextCallbackId++;
    callbacks[id] = { callback: callback, once: once === true };
    return id;
  }

  function runCallback(id, payload) {
    var entry = callbacks[id];
    if (!entry) { return; }
    try { entry.callback(payload); } finally { if (entry.once) { delete callbacks[id]; } }
  }

  window.__TAURI_INTERNALS__ = {
    metadata: { currentWindow: { label: 'main' }, currentWebview: { label: 'main' } },
    callbacks: callbacks,
    transformCallback: transformCallback,
    runCallback: runCallback,
    invoke: invoke
  };
  // payload 的 event 绑定在 unlisten 时会无条件访问这个全局，缺了会直接 TypeError
  window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {
    unregisterListener: function (event, eventId) { delete callbacks[eventId]; }
  };
  // 一并占位，避免 polyfill 再装一份 localStorage 版的 fs 桩
  window.__TAURI__ = {
    window: { getCurrent: function () { return { label: 'main' }; } },
    fs: {
      readTextFile: function (path) {
        return invoke('plugin:fs|read_text_file', { path: path }).then(function (bytes) {
          return new TextDecoder().decode(bytes);
        });
      },
      writeTextFile: function (path, contents) {
        return invoke('plugin:fs|write_text_file', new TextEncoder().encode(String(contents)),
          { headers: { path: encodeURIComponent(path), options: JSON.stringify({}) } });
      }
    }
  };
  window.__TAURI_IPC_KEY__ = '__TAURI_IPC_KEY__';

  // GP-Next 上游把 JS Modding 锁成"只能在开发者控制台打开"（面板里的开关会强制置回 false）。
  // 单机 HAP 场景下由壳层直接打开：必须写在 GP-Next 初始化之前，settings-store 启动时才会读到。
  try {
    var stored = localStorage.getItem('gp-next-settings');
    var settings = stored ? JSON.parse(stored) : {};
    if (!settings.experimental) { settings.experimental = {}; }
    if (settings.experimental.jsModding !== true) {
      settings.experimental.jsModding = true;
      localStorage.setItem('gp-next-settings', JSON.stringify(settings));
      console.info('[gp-next-shim] 已启用 JS Modding');
    }
  } catch (err) {
    console.warn('[gp-next-shim] 写入 jsModding 开关失败', err);
  }

  window.__gpNextNativeReady = true;
  console.info('[gp-next-shim] 原生桥已接管 __TAURI_INTERNALS__');
})();`;
