import { ResourceManager } from './ResourceManager';

/**
 * 本地负载服务：把 `https://cocos.local/...` 的请求映射到 rawfile。
 *
 * 处理顺序（与原页面内实现完全一致，勿改）：
 *   1. 按规则补负载前缀（壳层自带文件不补）
 *   2. 先查 ResourceManager 的 LRU 缓存（同步、无异步开销）
 *   3. 未命中再从 rawfile 原始读取
 *   4. 都失败返回 null，交给系统处理
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
  static serve(url: string, readRawfile: (path: string) => Resource): WebResourceResponse | null {
    if (!url.startsWith('https://cocos.local/')) {
      return null;
    }
    let rawFilePath = decodeURIComponent(url.replace('https://cocos.local/', ''));
    rawFilePath = rawFilePath.split('?')[0];

    // 负载自带的 index.html 用根绝对路径引用自己的模块（/assets/<hash>.js），故这里补前缀；
    // 已经是 game/ 开头的请求（来自页面的相对路径）不重复补。
    if (!rawFilePath.startsWith(PAYLOAD_DIR) && SHELL_ROOT_FILES.indexOf(rawFilePath) < 0) {
      rawFilePath = PAYLOAD_DIR + rawFilePath;
    }

    // 1. 同步检查 ResourceManager LRU 缓存（快速路径，无异步开销）
    const cachedData = ResourceManager.getInstance().getCachedSync(rawFilePath);
    if (cachedData) {
      const response = new WebResourceResponse();
      response.setResponseData(cachedData);
      response.setResponseEncoding('utf-8');
      response.setResponseMimeType(mimeOf(rawFilePath));
      response.setResponseCode(200);
      response.setReasonMessage('OK');
      response.setResponseIsReady(true);
      return response;
    }

    // 2. 缓存未命中，从 rawfile 加载并返回
    try {
      const response = new WebResourceResponse();
      response.setResponseData(readRawfile(rawFilePath));
      response.setResponseEncoding('utf-8');
      response.setResponseMimeType(mimeOf(rawFilePath));
      response.setResponseCode(200);
      response.setReasonMessage('OK');
      response.setResponseIsReady(true);
      return response;
    } catch (error) {
      console.error(`拦截器读取文件失败: ${rawFilePath}`, error);
      return null;
    }
  }
}
