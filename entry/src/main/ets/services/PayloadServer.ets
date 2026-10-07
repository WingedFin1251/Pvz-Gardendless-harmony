import { ResourceManager } from './ResourceManager';

/**
 * 本地负载服务：把 `https://cocos.local/...` 的请求映射到 rawfile。
 *
 * 处理顺序（与原页面内实现完全一致，勿改）：
 *   1. 按规则补负载前缀（壳层自带文件不补）
 *   2. 先查 ResourceManager 的 LRU 缓存（同步、无异步开销）
 *   3. 未命中则用**同步字节读**拿到内容（同时回填缓存，让第 2 步下次能命中）
 *   4. 同步字节读不可用时退回 $rawfile；都失败返回 null，交给系统处理
 *
 * 为什么必须同步：onInterceptRequest 要求当场返回响应，异步读取来不及；
 * 所以填缓存只能用 getRawFileContentSync 这类同步接口。
 *
 * 说明：读取 rawfile 的函数由页面传入（`$rawfile` 是 UI 全局），
 * 这样数据来源与改动前完全一致，不引入行为变化。
 */

/** 游戏负载（Cocos 构建产物，含它**自带的** index.html）统一放在 rawfile/<PAYLOAD_DIR> 下 */
export const PAYLOAD_DIR: string = 'game/';

/** 留在 rawfile 根、由壳层自己提供的文件：不补负载前缀 */
const SHELL_ROOT_FILES: string[] = ['touchPatch.js'];

/**
 * 文件后缀 → MIME。
 * 其余一律按二进制：0.15.0 的 lite 用 .avif 纹理，先前 default=text/plain
 * 会让图片解码失败、引擎资源加载卡死（表现为面板一直「Waiting for engine…」）。
 */
export function mimeOf(fileName: string): string {
  const ext = fileName.split('.').pop()?.toLowerCase();
  switch (ext) {
    case 'html': return 'text/html';
    case 'js': return 'application/javascript';
    case 'wasm': return 'application/wasm';
    case 'json': return 'application/json';
    case 'css': return 'text/css';
    case 'png': return 'image/png';
    case 'jpg':
    case 'jpeg': return 'image/jpeg';
    case 'webp': return 'image/webp';
    case 'avif': return 'image/avif';
    case 'gif': return 'image/gif';
    // 音频/视频：Cocos 多数场景按 ArrayBuffer 解码，MIME 主要影响直接播放
    case 'mp3': return 'audio/mpeg';
    case 'm4a': return 'audio/mp4';
    case 'aac': return 'audio/aac';
    case 'ogg': return 'audio/ogg';
    case 'wav': return 'audio/wav';
    case 'mp4': return 'video/mp4';
    case 'webm': return 'video/webm';
    case 'ttf': return 'font/ttf';
    case 'otf': return 'font/otf';
    case 'woff': return 'font/woff';
    case 'woff2': return 'font/woff2';
    case 'txt': return 'text/plain';
    case 'xml': return 'application/xml';
    case 'csv': return 'text/csv';
    case 'svg': return 'image/svg+xml';
    case 'data': return 'application/octet-stream';
    default: return 'application/octet-stream';
  }
}

export class PayloadServer {
  /**
   * 处理一次请求。
   * @param url 请求 URL（非 cocos.local 的一律返回 null）
   * @param readRawfile 读取 rawfile 的函数（页面传 `$rawfile`，保持数据来源不变）
   */
  static serve(url: string,
    readRawfile: (path: string) => Resource,
    readRawfileBytes?: (path: string) => Uint8Array): WebResourceResponse | null {
    if (!url.startsWith('https://cocos.local/')) {
      return null;
    }
    // ⚠️ 顺序：**先切 query 再 decode**。反过来的话，文件名里含 `%3F` 的请求会被截断。
    const rawPath = url.replace('https://cocos.local/', '').split('?')[0];
    let rawFilePath: string;
    try {
      rawFilePath = decodeURIComponent(rawPath);
    } catch (error) {
      // 畸形转义（如 `%zz`）会让 decodeURIComponent 抛异常；不接住就会抛穿 ArkWeb 的回调
      console.warn(`URL 解码失败，按未找到处理: ${rawPath}`);
      return null;
    }

    // 路径穿越防护：解码后再查（`%2e%2e` 解码后就是 `..`），命中即本地拒绝，不外发
    if (rawFilePath.indexOf('..') >= 0 || rawFilePath.indexOf('\\') >= 0 ||
      rawFilePath.indexOf('\u0000') >= 0) {
      console.warn(`拒绝可疑路径: ${rawFilePath}`);
      const denied = new WebResourceResponse();
      denied.setResponseCode(403);
      denied.setReasonMessage('Forbidden');
      denied.setResponseIsReady(true);
      return denied;
    }

    // 负载自带的 index.html 用根绝对路径引用自己的模块（/assets/<hash>.js），故这里补前缀；
    // 已经是 game/ 开头的请求（来自页面的相对路径）不重复补。
    if (!rawFilePath.startsWith(PAYLOAD_DIR) && SHELL_ROOT_FILES.indexOf(rawFilePath) < 0) {
      rawFilePath = PAYLOAD_DIR + rawFilePath;
    }

    // 1. 同步检查 ResourceManager LRU 缓存（快速路径，无异步开销）
    const cachedData = ResourceManager.getInstance().getCachedSync(rawFilePath);
    if (cachedData) {
      return PayloadServer.buildResponse(PayloadServer.toExactArrayBuffer(cachedData), mimeOf(rawFilePath), rawFilePath);
    }

    // 2. 缓存未命中：优先用同步字节读（拿到字节才能回填缓存）
    if (readRawfileBytes) {
      try {
        const bytes = readRawfileBytes(rawFilePath);
        if (bytes && bytes.byteLength > 0) {
          const itemSize = bytes.byteLength;
          ResourceManager.getInstance().cacheResource(rawFilePath, bytes);
          const response = PayloadServer.buildResponse(PayloadServer.toExactArrayBuffer(bytes), mimeOf(rawFilePath), rawFilePath);
          // 哨兵：若 setResponseData 是"转移（detach）"语义，上面那一步会把这个 buffer 抽干。
          // 官方文档没写是拷贝还是转移，所以用一行 warn 把它钉死：出现即说明缓存必须改存副本。
          if (bytes.byteLength !== itemSize) {
            console.warn(`[lru-detach] setResponseData 转移了 buffer: ${rawFilePath} ${itemSize} -> ${bytes.byteLength}`);
          }
          return response;
        }
      } catch (error) {
        console.warn(`同步读取失败，退回 $rawfile: ${rawFilePath}`, error);
      }
    }

    // 3. 退回 $rawfile（数据来源与改动前一致）
    try {
      return PayloadServer.buildResponse(readRawfile(rawFilePath), mimeOf(rawFilePath), rawFilePath);
    } catch (error) {
      console.error(`拦截器读取文件失败: ${rawFilePath}`, error);
      return null;
    }
  }

  /**
   * 生成 CodeCache 用的 ResponseDataID。
   *
   * 官方《自定义页面请求响应》：在响应头里加 ResponseDataID，内核会为该 JS 生成 CodeCache；
   * **不加则默认不生成**；且要求 ① 格式为不超过 13 位纯数字 ② 响应长度 ≥ 1024 ③ 内容变更时必须换值。
   *
   * 这里用「路径 + 字节长度」的简易哈希：负载资源名本身带内容哈希，长度再兜一层，
   * 足以在负载更新时改变取值。⚠️ 待实测项：该头在 onInterceptRequest 路径上的实际收益。
   */
  private static codeCacheId(seed: string): string {
    let hash = 2166136261;                       // FNV-1a 32bit
    for (let i = 0; i < seed.length; i++) {
      hash ^= seed.charCodeAt(i);
      hash = (hash * 16777619) >>> 0;
    }
    const text = `${hash}`.padStart(10, '0').slice(0, 13);
    return text;
  }

  /** 统一构造 200 响应 */
  private static buildResponse(data: ArrayBuffer | Resource, mime: string, path?: string): WebResourceResponse {
    const response = new WebResourceResponse();
    response.setResponseData(data);
    // ⚠️ 只有文本类才设 utf-8。
    // 首次实测教训：给二进制（wasm/avif/png…）设了 utf-8 后，内核按文本解码字节，
    // 资源全部被解坏 —— 表现是整包卡在 Cocos 引擎启动页（引擎 JS 是文本所以能过）。
    if (PayloadServer.isTextMime(mime)) {
      response.setResponseEncoding('utf-8');
    }
    response.setResponseMimeType(mime);
    response.setResponseCode(200);
    response.setReasonMessage('OK');
    // CodeCache：只给长度 ≥1024 的 JS 加（官方条件），值随"路径 + 长度"变化
    if (mime === 'application/javascript' && path !== undefined) {
      const byteLength = PayloadServer.dataByteLength(data);
      if (byteLength >= 1024) {
        response.setResponseHeader([{ headerKey: 'ResponseDataID', headerValue: PayloadServer.codeCacheId(`${path}:${byteLength}`) }]);
      }
    }
    response.setResponseIsReady(true);
    return response;
  }

  /** 取响应数据的字节长度；Resource 类型拿不到长度则返回 0（此时不加 CodeCache 头） */
  private static dataByteLength(data: ArrayBuffer | Resource): number {
    if (data instanceof ArrayBuffer) {
      return data.byteLength;
    }
    return 0;
  }

  /** 文本类 MIME：这类才需要显式 utf-8；二进制一律不设编码，交由内核按 MIME 处理 */
  private static isTextMime(mime: string): boolean {
    return mime.startsWith('text/') ||
      mime === 'application/javascript' ||
      mime === 'application/json' ||
      mime === 'application/xml';
  }

  /**
   * Uint8Array → 精确区间的 ArrayBuffer。
   * 不能直接写 `bytes.buffer`：视图可能只覆盖底层缓冲的一部分（与 DownloadSaver 里同一个坑）。
   * setResponseData 的官方参数类型是 string | number | ArrayBuffer | Resource。
   */
  private static toExactArrayBuffer(bytes: Uint8Array): ArrayBuffer {
    if (bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength) {
      return bytes.buffer as ArrayBuffer;
    }
    return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  }
}
