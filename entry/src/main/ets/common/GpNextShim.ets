/**
 * GP-Next 的 Tauri 兼容层（注入到网页 document-start 的脚本）。
 *
 * 背景：GP-Next 面板前端原本跑在 Tauri 桌面容器里，文件读写 / 另存为 / 打开外链全部通过
 * `window.__TAURI_INTERNALS__.invoke(cmd, args, headers)` 调后端。payload 的 index.html 里自带一个
 * 用 localStorage 伪造文件系统的 polyfill，但实现残缺（写入必抛异常且被静默吞掉、zip 读不出二进制、
 * read_dir 把带点的文件名判成目录、默认 settings.json 的键前后不一致），因此这里在 document-start
 * 阶段抢先定义同名对象——polyfill 只在 `if (!window.__TAURI_INTERNALS__)` 成立时才安装，于是自动让位。
 * 注意：**上述 polyfill 只存在于 0.14.0 负载**；0.15.0 负载已无它，本层的作用变成**提供** payload
 * 需要的 `__TAURI_INTERNALS__`（负载里有 5 处读取、0 处赋值）。
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

  // A7：0.16.15 起负载主启动流程会调 ElectronAPI.window() → window.electronAPI.window()。
  // 但该负载在非 Electron 环境只补了 7 个 electronAPI 方法（音乐包 / 说明窗口），没有 window()，
  // 于是启动时抛 "TypeError: n.window is not a function" ⇒ 后面的 loadScene("splashScene")
  // 永远不执行 ⇒ 画面全黑（看门狗报 scene=preSplashScene、assets=48）。
  // 这里在 document-start 装一层代理：
  //   · 已存在的方法原样生效（音乐包 / getVersionInfo 仍是负载的真实实现）；
  //   · 未知方法一律返回空函数（window/center/fullScreen/setSize 等桌面窗口控制，移动端无意义）；
  //   · 负载用 host.electronAPI ||= {} 写入 ⇒ 只会往代理目标上加方法，不会覆盖本访问器。
  (function () {
    try {
      var target = {};
      var SKIP = { toString: 1, valueOf: 1, toJSON: 1, constructor: 1, then: 1, inspect: 1 };
      var handler = {
        get: function (t, key) {
          if (typeof key === 'symbol') { return undefined; }
          if (key in t) { return t[key]; }
          if (SKIP[key]) { return undefined; }
          // A10：未知方法仍返回空函数（保持旧行为，避免未加保护的调用直接 TypeError），
          // 但**首次**访问时在 bridge.log 留一行 [shim] unimpl:xxx。
          // 目的：把“静默失效”变成“可见”——2026-11-16 的 GitHub 关卡就是被这种静默坑了三轮。
          if (!unimplWarned[key]) {
            unimplWarned[key] = true;
            try {
              invoke('gp_next_shell_log', { message: 'unimpl:' + String(key) });
            } catch (logErr) {
              // 记不上也不影响业务
            }
          }
          return function () { return undefined; };
        },
        set: function (t, key, value) { t[key] = value; return true; },
        has: function (t, key) { return key in t; }
      };
      // A10：记录已经告警过的未知方法名（每个只记一次，避免刷屏）
    var unimplWarned = {};
    var proxy = new Proxy(target, handler);
      Object.defineProperty(window, 'electronAPI', {
        configurable: true,
        enumerable: true,
        get: function () { return proxy; },
        set: function (value) {
          if (value && typeof value === 'object') {
            for (var key in value) {
              if (Object.prototype.hasOwnProperty.call(value, key)) { target[key] = value[key]; }
            }
          }
        }
      });
    } catch (e) {
      console.warn('[A7] electronAPI 兼容垫片安装失败: ' + (e && e.message));
    }
  })();

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

  // 有一小撮 plugin:window|* 的真值只有页面自己知道——"窗口"就是它自己。
  // 交给原生只能靠猜（此前 inner_size 返回 {0,0}、scale_factor 返回 1，而实测视口是
  // 1120x736、DPR 2.5），所以在这一层直接答，顺便省掉一次跨语言往返。
  function localWindowValue(command) {
    if (command === 'plugin:window|inner_size' || command === 'plugin:window|outer_size') {
      return { width: Math.round(window.innerWidth), height: Math.round(window.innerHeight) };
    }
    if (command === 'plugin:window|scale_factor') { return window.devicePixelRatio || 1; }
    if (command === 'plugin:window|is_focused') { return document.hasFocus(); }
    if (command === 'plugin:window|is_visible') { return !document.hidden; }
    if (command === 'plugin:window|is_maximized' || command === 'plugin:window|is_fullscreen'
      || command === 'plugin:window|is_minimized') { return false; }
    return undefined;
  }

  function invoke(command, args, headers) {
    if (!window.__gpNextNative || typeof window.__gpNextNative.invoke !== 'function') {
      return Promise.reject(new Error('[gp-next-shim] 原生桥尚未就绪: ' + command));
    }
    var local = localWindowValue(String(command || ''));
    if (local !== undefined) { return Promise.resolve(local); }
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

  // ==================== 隐藏面板热键徽标（左上角那个 F9） ====================
  // payload 的叠加层会在左上角**无条件**画一个热键提示徽标（overlay-*.js 里的
  // 「Hotkey Hint Badge」→ 「.gp-f1-hint」，position:fixed; top/left:8px，内容=当前热键）。
  // 它只是提示：点它等价于切换面板，功能上并非必须；设置页里也没有关闭项（只有"改热键"）。
  // 所以由壳层注入一条 CSS 隐藏它。
  //   - 用 CSS 而不是删 DOM：负载更新后依然有效（徽标在 0.14.0 / 0.15.0 都存在），
  //     也不会与它自己的「.gp-hidden」类逻辑打架；
  //   - 想恢复提示：把 GPNEXT_HIDE_HOTKEY_HINT 改成 false（或删掉这一段）。
  var GPNEXT_HIDE_HOTKEY_HINT = true;
  if (GPNEXT_HIDE_HOTKEY_HINT) {
    var installHintCss = function () {
      if (document.getElementById('gp-next-shell-css')) { return; }
      var style = document.createElement('style');
      style.id = 'gp-next-shell-css';
      style.textContent = '.gp-f1-hint{display:none !important;}';
      var host = document.head || document.documentElement;
      if (host) { host.appendChild(style); }
    };
    if (document.head || document.documentElement) { installHintCss(); }
    else { document.addEventListener('DOMContentLoaded', installHintCss); }
  }

  // A9 的关卡本地库在下面另一个 IIFE 里，需要复用这里的 invoke / base64 辅助函数。
  window.__gpNextInvoke = invoke;
  window.__gpNextBytesToBase64 = bytesToBase64;
  window.__gpNextBase64ToBytes = base64ToBytes;

  window.__gpNextNativeReady = true;
  console.info('[gp-next-shim] 原生桥已接管 __TAURI_INTERNALS__');
})();

// A9：GitHub 关卡本地库（对齐桌面 preload 的 saveLevel/loadLevel/removeLevel/listLevels）。
// 桌面端由 preload 暴露这四个方法，页面通过 electronAPI.loadLevel(path) 读关卡；
// 缺失时 index.js 的 ea() 拿到空值就直接弹 i18n "LevelNonExist"（中文：关卡文件不存在），
// 而且**不会产生任何原生调用** —— 这正是真机上"下载了却玩不了"的原因。
// 存储格式与桌面一致：gp-next/github-levels/<sha256(相对路径)>.json = {"path":…,"content":…}
(function () {
  try {
    if (!window.electronAPI) { return; }
    // invoke / base64 是上面主 IIFE 里的局部函数，这里通过 window 上的出口复用
    // （之前直接调 invoke 报 "invoke is not defined"，页面因此弹错误）。
    var bridgeInvoke = window.__gpNextInvoke;
    var toBase64 = window.__gpNextBytesToBase64;
    var fromBase64 = window.__gpNextBase64ToBytes;
    if (typeof bridgeInvoke !== 'function') {
      console.warn('[A9] 原生桥入口不可用，跳过关卡本地库安装');
      return;
    }
    var LEVEL_DIR = 'gp-next/github-levels';

    function levelValidPath(p) {
      if (typeof p !== 'string' || p.length === 0 || p.length > 512) { return false; }
      // ⚠️ 本段是 TS 模板字面量的一部分：不要写反斜杠转义或 NUL 字面量
      //    （反斜杠对会塌成未闭合字符串，NUL 会变成真字符），一律用 fromCharCode。
      if (p.indexOf('..') >= 0 || p.indexOf(String.fromCharCode(0)) >= 0) { return false; }
      if (p.indexOf(String.fromCharCode(92)) >= 0 || p.indexOf(':') >= 0) { return false; }
      return p.split('/').every(function (part) {
        return part.length > 0 && part !== '.' && part !== '..';
      });
    }

    function sha256HexOf(text) {
      var subtle = window.crypto && window.crypto.subtle ? window.crypto.subtle : null;
      if (!subtle || typeof subtle.digest !== 'function') {
        return Promise.reject(new Error('crypto.subtle 不可用'));
      }
      var bytes = new TextEncoder().encode(String(text));
      return subtle.digest('SHA-256', bytes).then(function (buf) {
        var view = new Uint8Array(buf);
        var out = '';
        for (var i = 0; i < view.length; i++) {
          var hex = view[i].toString(16);
          out += hex.length === 1 ? '0' + hex : hex;
        }
        return out;
      });
    }

    function levelFileOf(relativePath) {
      return sha256HexOf(relativePath).then(function (hex) {
        return LEVEL_DIR + '/' + hex + '.json';
      });
    }

    // ⚠️ 主 IIFE 的 invoke() 已经把 __gpNextBytes **自动解码成 Uint8Array** 再返回
    //    （见它末尾的 base64ToBytes 分支），所以这里必须先按 Uint8Array 处理，
    //    否则会拿不到内容 → 游戏判定关卡不存在。
    function textFromValue(value) {
      if (!value) { return null; }
      try {
        if (value instanceof Uint8Array) {
          return new TextDecoder().decode(value);
        }
        if (typeof value === 'string') {
          return value;
        }
        if (typeof value.__gpNextBytes === 'string') {
          return new TextDecoder().decode(fromBase64(value.__gpNextBytes));
        }
      } catch (decodeErr) {
        return null;
      }
      return null;
    }

    function readTextFileText(path) {
      return bridgeInvoke('plugin:fs|read_text_file', { path: path }).then(function (value) {
        return textFromValue(value);
      }, function () {
        return null;
      });
    }

    function writeTextFileText(path, text) {
      var payload = { __gpNextBytes: toBase64(new TextEncoder().encode(text)) };
      return bridgeInvoke('plugin:fs|write_text_file', payload, { headers: { path: encodeURIComponent(path) } });
    }

    function levelSave(relativePath, content) {
      if (!levelValidPath(relativePath) || typeof content !== 'string') {
        return Promise.reject(new Error('Invalid level payload'));
      }
      return levelFileOf(relativePath).then(function (file) {
        return writeTextFileText(file, JSON.stringify({ path: relativePath, content: content }));
      });
    }

    function levelLoad(relativePath) {
      if (!levelValidPath(relativePath)) { return Promise.resolve(null); }
      return levelFileOf(relativePath).then(function (file) {
        return readTextFileText(file).then(function (raw) {
          if (!raw) { return null; }
          try {
            var data = JSON.parse(raw);
            if (data && data.path === relativePath && typeof data.content === 'string') {
              return data.content;
            }
            return null;
          } catch (parseErr) {
            return null;
          }
        }, function () {
          return null;
        });
      }, function () {
        return null;
      });
    }

    function levelRemove(relativePath) {
      if (!levelValidPath(relativePath)) { return Promise.resolve(null); }
      return levelFileOf(relativePath).then(function (file) {
        return bridgeInvoke('plugin:fs|remove', { path: file }).then(function () {
          return null;
        }, function () {
          return null;
        });
      }, function () {
        return null;
      });
    }

    function levelList() {
      return bridgeInvoke('plugin:fs|read_dir', { path: LEVEL_DIR }).then(function (entries) {
        if (!Array.isArray(entries)) { return []; }
        var jobs = [];
        entries.forEach(function (entry) {
          if (!entry || !entry.isFile || !/^[a-f0-9]{64}\.json$/.test(String(entry.name))) { return; }
          var fileName = String(entry.name);
          jobs.push(readTextFileText(LEVEL_DIR + '/' + fileName).then(function (raw) {
            if (!raw) { return null; }
            try {
              var data = JSON.parse(raw);
              if (!data || typeof data.path !== 'string' || typeof data.content !== 'string') { return null; }
              return sha256HexOf(data.path).then(function (hex) {
                return hex + '.json' === fileName ? data.path : null;
              });
            } catch (parseErr) {
              return null;
            }
          }, function () {
            return null;
          }));
        });
        return Promise.all(jobs).then(function (values) {
          var result = [];
          for (var k = 0; k < values.length; k++) {
            if (typeof values[k] === 'string') { result.push(values[k]); }
          }
          return result;
        });
      }, function () {
        return [];
      });
    }

    var levelApi = {
      saveLevel: levelSave,
      loadLevel: levelLoad,
      removeLevel: levelRemove,
      listLevels: levelList
    };
    Object.keys(levelApi).forEach(function (name) {
      window.electronAPI[name] = levelApi[name];
    });
    console.info('[A9] GitHub 关卡本地库已接管 electronAPI.loadLevel/saveLevel');
  } catch (e) {
    console.warn('[A9] 关卡本地库安装失败: ' + (e && e.message));
  }
})();

// A11：补齐 electronAPI 上“窗口/全屏/分辨率/焦点”这几个桌面 preload 会挂的方法。
// 它们以前全是 Proxy 空桩（返回 undefined），A10 的 [shim] unimpl 日志把真实调用暴露出来后才补的。
(function () {
  try {
    if (!window.electronAPI) { return; }
    var api = window.electronAPI;
    var win = window;

    function isFullScreenNow() {
      return !!(document.fullscreenElement || document.webkitFullscreenElement);
    }

    // ⚠️ 这里必须**无条件覆盖**：读 api.xxx 会先命中 Proxy 空桩（总是返回函数），
    //    用 typeof 判断会把自己跳过，导致 A11 形同虚设（2026-11-16 实测踩过）。
    api.isFullScreen = function () { return isFullScreenNow(); };
    api.getCurrentResolutionSync = function () {
      return Math.round(win.innerWidth) + 'x' + Math.round(win.innerHeight);
    };
    api.onWindowFocused = function (callback) {
      if (typeof callback !== 'function') { return function () {}; }
      var handler = function () {
        try { callback(); } catch (err) { }
      };
      win.addEventListener('focus', handler);
      return function () { win.removeEventListener('focus', handler); };
    };
    api.onWindowUnfocused = function (callback) {
      if (typeof callback !== 'function') { return function () {}; }
      var handler = function () {
        try { callback(); } catch (err) { }
      };
      win.addEventListener('blur', handler);
      document.addEventListener('visibilitychange', handler);
      return function () {
        win.removeEventListener('blur', handler);
        document.removeEventListener('visibilitychange', handler);
      };
    };

    // electronAPI.window：桌面端是 Tauri 的窗口对象（可当函数调用，也可取属性）。
    // 这里给一个"函数 + 属性"的兼容体：调用返回对象，属性上是同样的一批空实现。
    var windowMethods = ['hide', 'show', 'minimize', 'maximize', 'unmaximize', 'close', 'destroy',
      'center', 'setTitle', 'setSize', 'setPosition', 'setFullscreen', 'setAlwaysOnTop', 'setDecorations'];
    var windowApi = {};
    windowMethods.forEach(function (name) {
      windowApi[name] = function () { return undefined; };
    });
    windowApi.isFullscreen = function () { return isFullScreenNow(); };
    windowApi.isFullScreen = windowApi.isFullscreen;
    var windowCallable = function () { return windowApi; };
    windowMethods.forEach(function (name) {
      windowCallable[name] = windowApi[name];
    });
    api.window = windowCallable;

    console.info('[A11] electronAPI 窗口/全屏/焦点方法已补齐');
  } catch (e) {
    console.warn('[A11] 窗口方法补齐失败: ' + (e && e.message));
  }
})();

// A12：音乐包的“选文件 + 读成 Blob”也由桌面 preload 提供（pickMusicPackFiles / readMusicPackFiles），
// 缺了它页面会退回 <input type=file>（ArkWeb 里不可用）。这里用桥的 fs 命令实现同样语义：
//   目录 → 递归列出 [{path(相对), blob}]
//   .zip → [{path: 文件名, blob(zip)}]（zip 解压由负载自己做）
//   .json → pack.json + 同目录音频（移动端只拿得到被选中的那一个文件，音频读不到会明确报错）
(function () {
  try {
    if (!window.electronAPI) { return; }
    var api = window.electronAPI;
    var bridgeInvoke = window.__gpNextInvoke;
    if (typeof bridgeInvoke !== 'function') { return; }

    function nameOf(path) {
      var parts = String(path || '').split('/');
      return parts[parts.length - 1] || '';
    }

    function dirOf(path) {
      var text = String(path || '');
      var index = text.lastIndexOf('/');
      return index > 0 ? text.substring(0, index) : '';
    }

    function mimeOf(path) {
      var name = nameOf(path).toLowerCase();
      if (/[.](zip)$/.test(name)) { return 'application/zip'; }
      if (/[.](json)$/.test(name)) { return 'application/json'; }
      if (/[.](mp3)$/.test(name)) { return 'audio/mpeg'; }
      if (/[.](ogg)$/.test(name)) { return 'audio/ogg'; }
      if (/[.](wav)$/.test(name)) { return 'audio/wav'; }
      if (/[.](m4a|aac)$/.test(name)) { return 'audio/mp4'; }
      return 'application/octet-stream';
    }

    function toBlob(bytes, path) {
      return new Blob([bytes], { type: mimeOf(path) });
    }

    function readFileBlob(path) {
      return bridgeInvoke('plugin:fs|read_file', { path: path }).then(function (value) {
        if (value instanceof Uint8Array) { return toBlob(value, path); }
        if (value && typeof value.__gpNextBytes === 'string') {
          return toBlob(window.__gpNextBase64ToBytes(value.__gpNextBytes), path);
        }
        throw new Error('读取失败: ' + path);
      });
    }

    function walk(dir, prefix, out) {
      return bridgeInvoke('plugin:fs|read_dir', { path: dir }).then(function (entries) {
        if (!Array.isArray(entries)) { return out; }
        return entries.reduce(function (chain, entry) {
          return chain.then(function () {
            if (!entry || !entry.name) { return; }
            var relative = prefix ? prefix + '/' + entry.name : entry.name;
            var full = dir + '/' + entry.name;
            if (entry.isDirectory) { return walk(full, relative, out); }
            if (!entry.isFile) { return; }
            return readFileBlob(full).then(function (blob) {
              out.push({ path: relative, blob: blob });
            });
          });
        }, Promise.resolve()).then(function () { return out; });
      }, function () { return out; });
    }

    api.readMusicPackFiles = function (path) {
      if (typeof path !== 'string' || path.length === 0) {
        return Promise.resolve([]);
      }
      return bridgeInvoke('plugin:fs|stat', { path: path }).then(function (info) {
        if (info && info.isDirectory) {
          return walk(path, '', []);
        }
        var name = nameOf(path);
        return readFileBlob(path).then(function (blob) {
          if (/[.]zip$/i.test(name)) {
            return [{ path: name, blob: new Blob([blob], { type: 'application/zip' }) }];
          }
          if (!/[.]json$/i.test(name)) {
            throw new Error('请选择 ZIP 或 pack.json 形式的音乐包');
          }
          return blob.text().then(function (text) {
            var manifest = JSON.parse(text);
            var result = [{ path: 'pack.json', blob: new Blob([text], { type: 'application/json' }) }];
            var audio = manifest && manifest.audio ? manifest.audio : {};
            var keys = Object.keys(audio);
            var base = dirOf(path);
            return keys.reduce(function (chain, key) {
              return chain.then(function () {
                // ⚠️ 不能用正则里的反斜杠（模板字面量会塌成一个 \，生成非法正则）
                var relative = String(audio[key] || '').split(String.fromCharCode(92)).join('/');
                if (!relative) { return; }
                if (result.some(function (item) { return item.path === relative; })) { return; }
                return readFileBlob(base + '/' + relative).then(function (audioBlob) {
                  result.push({ path: relative, blob: audioBlob });
                }, function () {
                  // 移动端只拿得到被选中的那一个文件：音频读不到时明确告知，别让用户以为导入成功
                  throw new Error('音频文件读不到：' + relative + '（请改用 ZIP 形式的音乐包）');
                });
              });
            }, Promise.resolve()).then(function () { return result; });
          });
        });
      });
    };

    api.pickMusicPackFiles = function (options) {
      var directory = !!(options && options.directory);
      var request = directory
        ? { options: { multiple: false, directory: true } }
        : { options: { multiple: false, filters: [{ name: 'Music pack', extensions: ['zip', 'json'] }] } };
      return bridgeInvoke('plugin:dialog|open', request).then(function (picked) {
        if (!picked) { return null; }
        return api.readMusicPackFiles(String(picked));
      });
    };

    console.info('[A12] 音乐包选文件/读取已接管 electronAPI.pickMusicPackFiles/readMusicPackFiles');
  } catch (e) {
    console.warn('[A12] 音乐包适配安装失败: ' + (e && e.message));
  }
})();`;
