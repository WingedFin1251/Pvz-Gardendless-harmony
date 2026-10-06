import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * A6：手动导出 / 导入 localStorage（"手动求全"）。
 *
 * 与 A1 的分工（见 docs/PERSISTENCE_PLAN.md §11）：
 *   · A1（自动）= 固定 3 键 ∪ gpn_ 前缀，窄而轻，负责"日常不丢"；
 *   · A6（手动，本模块）= **全量**，负责"能搬走、能回滚、能挺过卸载"。
 *
 * 为什么必须经页面：只有页面能读 localStorage（官方 WebStorage 只能查用量/删除，见预案 §9.6）。
 * 页面侧函数在 resources/rawfile/touchPatch.js 末尾（__pvzStorageExport / ApplyBegin / Chunk / End）。
 *
 * 导入语义（预案 §9.8/§9.3）：**只覆盖、从不删除**；导入前自动备份当前状态；只接受
 * format/version 匹配的文件，否则明确报错且**不改动任何数据**。
 */
export interface StorageBackupDeps {
  /** 在页面上下文执行 JS（通常是 webController.runJavaScript） */
  runJs: (script: string) => Promise<string>;
  /** 让用户选保存位置；取消返回 null */
  pickSavePath: (fileName: string) => Promise<string | null>;
  /** 让用户选一个备份文件；取消返回 null */
  pickStorageFile: () => Promise<string | null>;
  /** 顶部状态提示 */
  notify: (message: string, duration: number) => void;
  /** 应用自己的文件目录（导入前的自动备份落在这里，不打扰用户） */
  filesDir: string;
  /** 应用版本（写进导出文件，便于日后排查） */
  appVersion: string;
}

export interface StorageBackupResult {
  /** true=完成；false=用户取消或失败（message 里是原因） */
  ok: boolean;
  message: string;
}

export class StorageBackup {
  /** 导出文件的格式标识与版本（导入侧严格校验） */
  static readonly FORMAT: string = 'pvzge-localstorage';
  static readonly VERSION: number = 1;
  /** 导入文件体积上限（防护：防止选到奇怪的大文件） */
  private static readonly MAX_IMPORT_BYTES: number = 8 * 1024 * 1024;
  /** 分片大小（字符数）：把 JSON 分块送进页面，避免拼进脚本文本 */
  private static readonly CHUNK_SIZE: number = 60000;
  private static readonly JS_EXPORT: string = 'window.__pvzStorageExport()';
  private static readonly JS_APPLY_BEGIN: string = 'window.__pvzStorageApplyBegin()';
  private static readonly JS_APPLY_END: string = 'window.__pvzStorageApplyEnd()';
  private static readonly ERR_PREFIX: string = '__PVZ_ERR__';

  /** 生成默认文件名：pvzge-localstorage-YYYYMMDD-HHmm.json */
  static buildFileName(now: Date): string {
    const pad = (value: number): string => (value < 10 ? '0' + value : '' + value);
    return 'pvzge-localstorage-' + now.getFullYear() + pad(now.getMonth() + 1) + pad(now.getDate())
      + '-' + pad(now.getHours()) + pad(now.getMinutes()) + '.json';
  }

  /** 把页面回传的导出串清洗成"纯 JSON"：ArkWeb 可能把字符串结果再包一层引号 */
  private static unwrap(raw: string): string {
    let text = (raw === undefined || raw === null) ? '' : raw;
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      try {
        const parsed: string = JSON.parse(text) as string;
        if (typeof parsed === 'string') { text = parsed; }
      } catch (err) {
        // 不是被包了一层的字符串，按原样使用
      }
    }
    return text;
  }

  /** 导出：收集页面全部 localStorage → 拼自描述 JSON → 让用户选位置 → 写文件 */
  static async exportAll(deps: StorageBackupDeps): Promise<StorageBackupResult> {
    const rawExport: string = await deps.runJs(StorageBackup.JS_EXPORT);
    const entries: string = StorageBackup.unwrap(rawExport);
    if (entries.length === 0 || entries === 'null') {
      return { ok: false, message: '导出失败：页面没有返回数据（可能负载尚未就绪）' };
    }
    if (entries.startsWith(StorageBackup.ERR_PREFIX)) {
      return { ok: false, message: '导出失败：' + entries.substring(StorageBackup.ERR_PREFIX.length) };
    }
    if (!entries.startsWith('{')) {
      return { ok: false, message: '导出失败：页面返回的数据不是 JSON 对象' };
    }

    const now = new Date();
    const payload: string = '{"format":"' + StorageBackup.FORMAT + '","version":' + StorageBackup.VERSION
      + ',"exportedAt":"' + now.toISOString() + '"'
      + ',"origin":"https://cocos.local"'
      + ',"app":{"bundle":"com.gardendless.gpnext","version":"' + deps.appVersion + '"}'
      + ',"entries":' + entries + '}';

    const fileName: string = StorageBackup.buildFileName(now);
    const uri: string | null = await deps.pickSavePath(fileName);
    if (uri === null || uri.length === 0) {
      return { ok: false, message: '已取消导出' };
    }

    // ⚠️ 与导入同理：选择器回传的 uri 可能是**百分号编码**的。
    // 写入时必须**优先用解码后的真实路径** —— 选择器已经在真实路径创建了空文件；
    // 若用编码形式写入，会在同一目录下**另建一个名字怪异的文件**（或直接失败）。
    const writeCandidates: string[] = [];
    try {
      const decodedTarget: string = decodeURIComponent(uri);
      if (decodedTarget !== uri) { writeCandidates.push(decodedTarget); }
    } catch (decodeErr) {
      console.warn(`uri 解码失败（按原样使用）: ${(decodeErr as BusinessError).message}`);
    }
    writeCandidates.push(uri);
    console.info(`[A6] 导出目标 uri: ${uri}`);

    let written: number = -1;
    let lastError: string = '';
    for (let i = 0; i < writeCandidates.length; i++) {
      const candidate: string = writeCandidates[i];
      let handle: fs.File | undefined = undefined;
      try {
        handle = fs.openSync(candidate, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC | fs.OpenMode.CREATE);
        written = fs.writeSync(handle.fd, payload);
        console.info(`[A6] 写入成功（第 ${i + 1} 种路径形式），${written} 字节`);
        lastError = '';
        break;
      } catch (err) {
        const error = err as BusinessError;
        lastError = `code=${error.code}, message=${error.message}`;
        console.warn(`[A6] 第 ${i + 1} 种路径形式写入失败: ${lastError}`);
      } finally {
        if (handle !== undefined) {
          try { fs.closeSync(handle); } catch (closeErr) {
            console.warn(`关闭备份文件失败: ${(closeErr as BusinessError).message}`);
          }
        }
      }
    }
    if (written < 0) {
      console.error(`写入备份文件失败（两种形式都不行）: ${lastError}`);
      return { ok: false, message: '写入失败：' + lastError };
    }

    const kb: string = (payload.length / 1024).toFixed(1);
    return { ok: true, message: `已导出全部数据（约 ${kb} KB）：${fileName}` };
  }

  /** 导入：选文件 → 校验 → 自动备份当前状态 → 分片送进页面 → 只覆盖不删除 */
  static async importFromFile(deps: StorageBackupDeps): Promise<StorageBackupResult> {
    const uri: string | null = await deps.pickStorageFile();
    if (uri === null || uri.length === 0) {
      return { ok: false, message: '已取消导入' };
    }

    // ⚠️ 系统选择器回传的 uri 可能是**百分号编码**的（目录/文件名含中文时必然如此，
    // 例如 pvzge%E5%AD%98%E6%A1%A3 = pvzge存档）。fs 需要解码后的路径；
    // 但某些版本直接接受原始 uri ⇒ **两种都试**，并把实际可用的那种记进日志。
    const candidates: string[] = [uri];
    try {
      const decoded: string = decodeURIComponent(uri);
      if (decoded !== uri) { candidates.push(decoded); }
    } catch (decodeErr) {
      console.warn(`uri 解码失败（按原样使用）: ${(decodeErr as BusinessError).message}`);
    }
    console.info(`[A6] 导入源 uri: ${uri}`);

    let text: string = '';
    let lastError: string = '';
    for (let i = 0; i < candidates.length; i++) {
      const candidate: string = candidates[i];
      try {
        const stat = fs.statSync(candidate);
        if (stat.size > StorageBackup.MAX_IMPORT_BYTES) {
          return { ok: false, message: `文件过大（${(stat.size / 1024 / 1024).toFixed(1)} MB），已中止，未改动任何数据` };
        }
        text = fs.readTextSync(candidate);
        console.info(`[A6] 读取成功（第 ${i + 1} 种路径形式），${stat.size} 字节`);
        lastError = '';
        break;
      } catch (err) {
        const error = err as BusinessError;
        lastError = `code=${error.code}, message=${error.message}`;
        console.warn(`[A6] 第 ${i + 1} 种路径形式读取失败: ${lastError}`);
      }
    }
    if (text.length === 0) {
      console.error(`读取备份文件失败（两种形式都不行）: ${lastError}`);
      return { ok: false, message: '读取失败：' + lastError };
    }

    // 校验：必须是我们自己的格式，且版本已知 —— 否则明确报错且不改动任何数据
    if (!text.includes('"' + StorageBackup.FORMAT + '"')) {
      return { ok: false, message: '这不是本应用的备份文件，已中止，未改动任何数据' };
    }
    if (!text.includes('"version":' + StorageBackup.VERSION)) {
      return { ok: false, message: '备份文件版本不受支持，已中止，未改动任何数据' };
    }
    const marker: string = '"entries":';
    const markerAt: number = text.indexOf(marker);
    const lastBrace: number = text.lastIndexOf('}');
    if (markerAt < 0 || lastBrace <= markerAt) {
      return { ok: false, message: '备份文件结构不完整，已中止，未改动任何数据' };
    }
    const entriesJson: string = text.substring(markerAt + marker.length, lastBrace).trim();
    if (!entriesJson.startsWith('{')) {
      return { ok: false, message: '备份文件里没有数据段，已中止，未改动任何数据' };
    }

    // 导入前自动备份当前状态（落在应用自己的目录里，不打扰用户）
    try {
      const current: string = StorageBackup.unwrap(await deps.runJs(StorageBackup.JS_EXPORT));
      if (current.startsWith('{')) {
        const autoPath: string = deps.filesDir + '/pvzge-storage-backup-before-import.json';
        const autoFile = fs.openSync(autoPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC | fs.OpenMode.CREATE);
        try {
          fs.writeSync(autoFile.fd, current);
        } finally {
          fs.closeSync(autoFile);
        }
        console.info(`导入前已自动备份当前状态: ${autoPath}`);
      }
    } catch (err) {
      const error = err as BusinessError;
      console.warn(`导入前自动备份失败（继续导入）: ${error.message}`);
    }

    // 分片传输 + 应用
    await deps.runJs(StorageBackup.JS_APPLY_BEGIN);
    for (let offset = 0; offset < entriesJson.length; offset += StorageBackup.CHUNK_SIZE) {
      const chunk: string = entriesJson.substring(offset, offset + StorageBackup.CHUNK_SIZE);
      await deps.runJs('window.__pvzStorageApplyChunk(' + JSON.stringify(chunk) + ')');
    }
    const applied: string = await deps.runJs(StorageBackup.JS_APPLY_END);
    const resultText: string = (applied === undefined || applied === null) ? '' : applied;
    if (resultText.startsWith(StorageBackup.ERR_PREFIX)) {
      return { ok: false, message: '导入失败：' + resultText.substring(StorageBackup.ERR_PREFIX.length) };
    }
    const count: number = Number(resultText);
    if (!Number.isFinite(count) || count <= 0) {
      return { ok: false, message: '导入未生效：页面回传 ' + resultText };
    }
    return { ok: true, message: `已导入 ${count} 个键。重启应用后生效（导入前的状态已自动备份）` };
  }
}