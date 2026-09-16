import fs from '@ohos.file.fs';
import zlib from '@ohos.zlib';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * GP-Next 原生桥：把网页侧的 Tauri 命令落到应用私有目录。
 *
 * 为什么需要它：GP-Next 的所有非内存功能（数据包 / 补丁 / 手动编辑 / 设置 / 导出）都经
 * `plugin:fs|*`、`plugin:dialog|*`、`plugin:opener|*` 调 Tauri 后端；HAP 里原本只有一个
 * localStorage 假文件系统，导致写入静默失败、zip 读不出、数据包无处导入。这里用真实文件系统
 * 替换它，目录为 `<filesDir>/gp-next/{packs,patches,__gpn_edits}`。
 *
 * 协议细节（来自 payload 的 @tauri-apps/plugin-fs 绑定，必须逐条对齐）：
 *  - `read_text_file` / `read_file` 的返回值会被 `Uint8Array.from(...)` + `TextDecoder` 处理 →
 *    必须回传字节，故统一以 `{ "__gpNextBytes": base64 }` 形式给注入脚本还原；
 *  - `write_text_file` 的路径在**第三参** `headers.path`（URI 编码），体是 Uint8Array（已是 base64）；
 *  - `read_dir` 的条目必须带正确的 `isFile`（假 FS 就是把这个判反了，导致 `*.zip` 被当成目录跳过）。
 *
 * 未兼容命令**刻意抛错**而不是返回 null：宁可让面板看到明确的失败，也不要"看似成功、实际没做"。
 */

interface GpNextHeaders {
  path: string;
  options?: string;
}

interface GpNextOptions {
  baseDir?: number;
  recursive?: boolean;
  encoding?: string;
  headers?: GpNextHeaders;
  defaultPath?: string;
  filters?: Object[];
}

interface GpNextArgs {
  path?: string;
  url?: string;
  directory?: number;
  options?: GpNextOptions;
  __gpNextBytes?: string;
  event?: string;
  eventId?: number;
  payload?: Object;
  handler?: number;
  target?: Object;
  protocol?: string;
}

interface GpNextRequest {
  command: string;
  args?: GpNextArgs;
  options?: GpNextOptions;
}

interface GpNextBytesValue {
  __gpNextBytes: string;
}

interface GpNextDirEntry {
  name: string;
  isDirectory: boolean;
  isFile: boolean;
  isSymlink: boolean;
}

/**
 * 宿主能力（都涉及 UI / 系统对话框）以函数参数传入，而不是用对象字面量实现接口——
 * ArkTS 的 arkts-no-untyped-obj-literals 不允许在调用处用字面量实现带方法的接口。
 */
export type GpNextOpenExternal = (url: string) => void;
export type GpNextPickSaveTarget = (fileName: string) => Promise<string | null>;
export type GpNextImportPackages = () => Promise<void>;

const GP_NEXT_DIR: string = 'gp-next';
const EXPORT_DIR: string = '.exports';
const INCOMING_DIR: string = '.incoming';

function errorText(err: Object): string {
  const businessError = err as BusinessError;
  if (businessError && businessError.message) {
    return businessError.message;
  }
  return String(err);
}

export class GpNextBridge {
  private openExternalHandler: GpNextOpenExternal;
  private pickSaveTargetHandler: GpNextPickSaveTarget;
  private importPackagesHandler: GpNextImportPackages;
  private baseDir: string;
  private root: string;
  private exportDir: string;
  private incomingDir: string;
  /** 另存为登记的"临时路径 → 用户选定 uri"，写完后由壳层复制过去 */
  private pendingExports: Map<string, string> = new Map();
  private base64: util.Base64Helper = new util.Base64Helper();

  constructor(context: common.UIAbilityContext,
    openExternal: GpNextOpenExternal,
    pickSaveTarget: GpNextPickSaveTarget,
    importPackages: GpNextImportPackages) {
    this.openExternalHandler = openExternal;
    this.pickSaveTargetHandler = pickSaveTarget;
    this.importPackagesHandler = importPackages;
    this.baseDir = GpNextBridge.trimTrailingSlash(context.filesDir);
    this.root = `${this.baseDir}/${GP_NEXT_DIR}`;
    this.exportDir = `${this.root}/${EXPORT_DIR}`;
    this.incomingDir = `${this.root}/${INCOMING_DIR}`;
    // 桌面版由安装器预建这些目录，这里补齐
    this.ensureDir(this.root);
    this.ensureDir(`${this.root}/packs`);
    this.ensureDir(`${this.root}/patches`);
    this.ensureDir(this.exportDir);
    this.ensureDir(this.incomingDir);
    console.info(`[gp-next-bridge] 数据根目录: ${this.root}`);
  }

  /** GP-Next 数据目录（含 packs/patches/__gpn_edits） */
  getRootPath(): string {
    return this.root;
  }

  /**
   * 注入脚本的调用入口：接收 JSON 请求，返回 JSON 响应。
   * 响应形如 {"ok":true,"value":...} 或 {"ok":false,"error":"...","code":"gp_next_error"}。
   */
  async invoke(requestJson: string): Promise<string> {
    let command: string = '';
    try {
      const request = JSON.parse(requestJson) as GpNextRequest;
      command = request.command;
      const valueJson: string = await this.dispatch(request);
      return `{"ok":true,"value":${valueJson}}`;
    } catch (err) {
      const message = errorText(err as Object);
      console.error(`[gp-next-bridge] ${command} 失败: ${message}`);
      return `{"ok":false,"error":${JSON.stringify(message)},"code":"gp_next_error"}`;
    }
  }

  /** 返回值统一为 JSON 片段，交给 invoke 拼装（避免 ArkTS 里 Object 与原始类型互转的麻烦） */
  private async dispatch(request: GpNextRequest): Promise<string> {
    const command: string = request.command;
    const args: GpNextArgs | undefined = request.args;
    switch (command) {
      // ---- 路径 ----
      case 'plugin:path|resolve_directory': {
        if (args && args.directory !== undefined && args.directory !== 14) {
          throw new Error(`不允许解析 Tauri directory ${args.directory}`);
        }
        // Tauri AppData（directory=14）：应用私有数据目录；GP-Next 之后会自行拼 gp-next/...
        return JSON.stringify(this.baseDir);
      }
      case 'plugin:path|basename': {
        const path = this.requirePath(args);
        const segments = path.split('/');
        return JSON.stringify(segments[segments.length - 1]);
      }
      case 'plugin:path|dirname': {
        const path = this.requirePath(args);
        return JSON.stringify(this.dirname(path));
      }

      // ---- 文件系统 ----
      case 'plugin:fs|read_text_file':
      case 'plugin:fs|read_file': {
        const target = this.resolve(this.requirePath(args), this.effectiveOptions(request));
        const bytes = this.readBytes(target);
        const value: GpNextBytesValue = { __gpNextBytes: this.base64.encodeToStringSync(bytes) };
        return JSON.stringify(value);
      }
      case 'plugin:fs|write_text_file': {
        return JSON.stringify(this.writeFile(request));
      }
      case 'plugin:fs|read_dir': {
        const target = this.resolve(this.requirePath(args), this.effectiveOptions(request));
        return JSON.stringify(this.readDir(target));
      }
      case 'plugin:fs|exists': {
        const target = this.resolve(this.requirePath(args), this.effectiveOptions(request));
        return fs.accessSync(target) ? 'true' : 'false';
      }
      case 'plugin:fs|mkdir': {
        const options = this.effectiveOptions(request);
        const target = this.resolve(this.requirePath(args), options);
        const recursive = !options || options.recursive === undefined ? true : options.recursive;
        this.ensureDir(target, recursive);
        return 'null';
      }
      case 'plugin:fs|remove': {
        const options = this.effectiveOptions(request);
        const target = this.resolve(this.requirePath(args), options);
        this.removePath(target);
        return 'null';
      }

      // ---- 对话框 ----
      case 'plugin:dialog|save': {
        const path = await this.prepareExport(args);
        return JSON.stringify(path);
      }

      // ---- 外部打开 ----
      case 'plugin:opener|open_url': {
        const url: string = args && args.url ? args.url : '';
        if (url.length > 0) {
          this.openExternalHandler(url);
        }
        return 'null';
      }
      case 'plugin:opener|open_path': {
        // 桌面版语义是"打开数据包目录"，移动端没有文件管理器能进应用沙箱 → 改成导入数据包
        await this.importPackagesHandler();
        return 'null';
      }

      // ---- 以下为移动端无意义或未接的能力，按"静默成功"处理 ----
      case 'plugin:deep-link|get_current':
        return '[]';
      case 'plugin:deep-link|is_registered':
        return 'false';
      case 'plugin:deep-link|register':
      case 'plugin:deep-link|unregister':
      case 'plugin:event|unlisten':
      case 'plugin:event|emit':
      case 'plugin:event|emit_to':
      case 'plugin:resources|close':
      case 'plugin:drpc|spawn_thread':
      case 'plugin:drpc|destroy_thread':
      case 'plugin:drpc|set_activity':
      case 'update_macos_menu':
      case 'open_devtools':
        return 'null';
      case 'plugin:drpc|is_running':
        return 'false';
      case 'plugin:event|listen':
        // 事件机制未接（GP-Next 只用它监听 macOS 菜单动作），返回一个不会被触发的 id
        return String(Date.now() % 1000000);
      case 'get_native_performance_snapshot':
        // 性能页会优雅降级成 unavailable，先不提供原生快照
        return 'null';

      default:
        return this.fallback(command);
    }
  }

  /** plugin:window|* / plugin:image|* 在桌面端由自动生成的绑定注册，移动端给一组安全默认值 */
  private fallback(command: string): string {
    if (command.startsWith('plugin:window|is_')) {
      return 'false';
    }
    if (command.startsWith('plugin:window|inner_size') || command.startsWith('plugin:window|outer_size')) {
      return '{"width":0,"height":0}';
    }
    if (command.startsWith('plugin:window|scale_factor')) {
      return '1';
    }
    if (command.startsWith('plugin:window|theme')) {
      return JSON.stringify('dark');
    }
    if (command.startsWith('plugin:window|title') || command.startsWith('plugin:window|activity_name')
      || command.startsWith('plugin:window|scene_identifier')) {
      return JSON.stringify('');
    }
    if (command.startsWith('plugin:window|')) {
      return 'null';
    }
    if (command.startsWith('plugin:image|')) {
      return 'null';
    }
    throw new Error(`未兼容的 GP-Next 命令：${command}`);
  }

  // ==================== 路径与沙箱 ====================

  private static trimTrailingSlash(path: string): string {
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }

  private dirname(path: string): string {
    const index = path.lastIndexOf('/');
    if (index <= 0) {
      return '/';
    }
    return path.substring(0, index);
  }

  private requirePath(args: GpNextArgs | undefined): string {
    const path: string | undefined = args ? args.path : undefined;
    if (!path || path.trim().length === 0) {
      throw new Error('GP-Next 文件路径为空');
    }
    return path;
  }

  /**
   * write_text_file 的 options 在第三参里，普通 fs 命令在 args.options 里，统一取出来。
   */
  private effectiveOptions(request: GpNextRequest): GpNextOptions | undefined {
    const args: GpNextArgs | undefined = request.args;
    if (args && args.options) {
      return args.options;
    }
    const headers: GpNextHeaders | undefined = request.options ? request.options.headers : undefined;
    if (headers && headers.options) {
      try {
        return JSON.parse(headers.options) as GpNextOptions;
      } catch (err) {
        console.warn(`[gp-next-bridge] 解析 options 失败: ${headers.options}`);
      }
    }
    return request.options;
  }

  /**
   * 归一化并把路径限制在应用私有目录内：
   * 相对路径挂在 filesDir 下（Tauri 的 baseDir=14 语义），绝对路径必须落在沙箱内；
   * 拒绝任何 . / .. 段，避免越过沙箱。
   */
  private resolve(rawPath: string, options: GpNextOptions | undefined): string {
    if (options && options.baseDir !== undefined && options.baseDir !== 14) {
      throw new Error(`不允许访问 Tauri baseDir ${options.baseDir}`);
    }
    let raw: string = rawPath.trim().replace(/\\/g, '/');
    if (raw.startsWith('file://')) {
      raw = raw.substring(7);
    }
    const combined: string = raw.startsWith('/') ? raw : `${this.baseDir}/${raw}`;
    const parts: string[] = [];
    const segments: string[] = combined.split('/');
    for (const segment of segments) {
      if (segment.length === 0) {
        continue;
      }
      if (segment === '.' || segment === '..') {
        throw new Error(`GP-Next 路径非法: ${rawPath}`);
      }
      parts.push(segment);
    }
    const normalized: string = `/${parts.join('/')}`;
    if (normalized !== this.baseDir && !normalized.startsWith(`${this.baseDir}/`)) {
      throw new Error(`GP-Next 路径越界: ${rawPath}`);
    }
    return normalized;
  }

  private ensureDir(path: string, recursive: boolean = true): void {
    if (path.length === 0 || path === '/') {
      return;
    }
    if (fs.accessSync(path)) {
      return;
    }
    try {
      fs.mkdirSync(path, recursive);
    } catch (err) {
      if (!fs.accessSync(path)) {
        throw err as Error;
      }
    }
  }

  // ==================== 文件读写 ====================

  private readBytes(path: string): Uint8Array {
    if (!fs.accessSync(path)) {
      throw new Error(`File not found: ${path}`);
    }
    const stat = fs.statSync(path);
    if (!stat.isFile()) {
      throw new Error(`Not a file: ${path}`);
    }
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(stat.size);
      const readLength = fs.readSync(file.fd, buffer);
      return new Uint8Array(buffer.slice(0, readLength));
    } finally {
      fs.closeSync(file);
    }
  }

  private writeFile(request: GpNextRequest): null {
    const args: GpNextArgs | undefined = request.args;
    const headers: GpNextHeaders | undefined = request.options ? request.options.headers : undefined;
    let path: string | undefined = headers ? decodeURIComponent(headers.path) : undefined;
    if (!path && args) {
      path = args.path;
    }
    if (!path) {
      throw new Error('GP-Next 写入路径缺失（headers.path）');
    }
    const target = this.resolve(path, this.effectiveOptions(request));
    const bytes: Uint8Array = args && args.__gpNextBytes
      ? this.base64.decodeSync(args.__gpNextBytes)
      : new Uint8Array(0);
    this.ensureDir(this.dirname(target));
    const file = fs.openSync(target, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, bytes.buffer as ArrayBuffer);
    } finally {
      fs.closeSync(file);
    }

    // 命中"另存为"登记的临时路径 → 复制到用户选定的位置并清掉临时文件
    const exportUri: string | undefined = this.pendingExports.get(target);
    if (exportUri) {
      this.pendingExports.delete(target);
      this.deliverExport(target, exportUri);
    }
    return null;
  }

  private readDir(path: string): GpNextDirEntry[] {
    if (!fs.accessSync(path)) {
      throw new Error(`File not found: ${path}`);
    }
    const entries: GpNextDirEntry[] = [];
    for (const name of fs.listFileSync(path)) {
      const full = `${path}/${name}`;
      try {
        const stat = fs.lstatSync(full);
        entries.push({
          name: name,
          isDirectory: stat.isDirectory(),
          isFile: stat.isFile(),
          isSymlink: stat.isSymbolicLink()
        });
      } catch (err) {
        console.warn(`[gp-next-bridge] 跳过无法访问的条目: ${full} (${errorText(err as Object)})`);
      }
    }
    return entries;
  }

  private removePath(path: string): void {
    if (!fs.accessSync(path)) {
      return;
    }
    if (path === this.root || path === this.baseDir) {
      throw new Error('拒绝删除 GP-Next 根目录');
    }
    const stat = fs.lstatSync(path);
    if (stat.isSymbolicLink()) {
      throw new Error(`拒绝操作符号链接: ${path}`);
    }
    if (stat.isDirectory()) {
      fs.rmdirSync(path);
    } else {
      fs.unlinkSync(path);
    }
  }

  // ==================== 另存为 ====================

  /**
   * Tauri 的 save 对话框语义：先问用户存哪儿，再返回一个可写路径。
   * 这里返回沙箱内的临时路径，等 GP-Next 写完再由 deliverExport 复制到用户选定的 uri。
   */
  private async prepareExport(args: GpNextArgs | undefined): Promise<string | null> {
    const options: GpNextOptions | undefined = args ? args.options : undefined;
    const suggested: string = options && options.defaultPath ? this.safeFileName(options.defaultPath) : 'export.json';
    const targetUri: string | null = await this.pickSaveTargetHandler(suggested);
    if (!targetUri) {
      console.info('[gp-next-bridge] 用户取消了另存为');
      return null;
    }
    this.ensureDir(this.exportDir);
    const tempPath: string = `${this.exportDir}/${Date.now()}-${suggested}`;
    this.pendingExports.set(tempPath, targetUri);
    return tempPath;
  }

  private deliverExport(tempPath: string, targetUri: string): void {
    try {
      this.copyPath(tempPath, targetUri);
      fs.unlinkSync(tempPath);
      console.info(`[gp-next-bridge] 已导出到用户选择的位置: ${targetUri}`);
    } catch (err) {
      console.error(`[gp-next-bridge] 导出落盘失败: ${errorText(err as Object)}`);
    }
  }

  private safeFileName(raw: string): string {
    const base = raw.replace(/\\/g, '/');
    const segments = base.split('/');
    const name = segments[segments.length - 1];
    const cleaned = name.replace(/[^A-Za-z0-9._-]/g, '_');
    return cleaned.length > 0 ? cleaned : 'export.json';
  }

  // ==================== 数据包导入 ====================

  /**
   * 导入用户选中的数据包（.zip）与单文件补丁（.json/.json5）。
   * 移动端没有"数据包目录"可让用户丢文件，只能由壳层代劳。
   */
  async importPackages(uris: string[]): Promise<string> {
    let imported = 0;
    const failures: string[] = [];
    for (const uri of uris) {
      const name = this.fileNameOf(uri);
      try {
        const lower = name.toLowerCase();
        if (lower.endsWith('.json') || lower.endsWith('.json5')) {
          const destination = this.uniquePath(`${this.root}/patches`, name);
          this.copyPath(uri, destination);
          imported++;
          console.info(`[gp-next-bridge] 单文件补丁已导入: ${destination}`);
        } else if (lower.endsWith('.zip')) {
          await this.importArchive(uri, name);
          imported++;
        } else {
          throw new Error('仅支持 .zip / .json / .json5');
        }
      } catch (err) {
        failures.push(`${name}: ${errorText(err as Object)}`);
      }
    }
    if (failures.length === 0) {
      return imported > 0 ? `已导入 ${imported} 个数据包` : '没有可导入的文件';
    }
    console.error(`[gp-next-bridge] 导入失败: ${failures.join(' | ')}`);
    return `成功 ${imported} 个，失败 ${failures.length} 个：${failures.join('；')}`;
  }

  private async importArchive(uri: string, name: string): Promise<void> {
    const incoming = `${this.incomingDir}/${Date.now()}-${name}`;
    const staging = `${this.incomingDir}/unzip-${Date.now()}`;
    this.copyPath(uri, incoming);
    try {
      this.ensureDir(staging);
      // GP-Next 支持"文件夹形式"的数据包，所以这里直接解压成目录，省掉重写 zip 的麻烦
      await zlib.decompressFile(incoming, staging);
      this.flattenPack(staging);
      if (!fs.accessSync(`${staging}/pack.json`)) {
        throw new Error('压缩包内缺少 pack.json（既不在根目录，也不在唯一的单层目录下）');
      }
      const destination = this.uniquePath(`${this.root}/packs`, name.replace(/\.zip$/i, ''));
      fs.renameSync(staging, destination);
      console.info(`[gp-next-bridge] 数据包已导入: ${destination}`);
    } catch (err) {
      this.safeRemove(staging);
      throw err as Error;
    } finally {
      this.safeRemove(incoming);
    }
  }

  /** 兼容"整个包被套在一层目录里"的压缩包：把内容提上来 */
  private flattenPack(staging: string): void {
    if (fs.accessSync(`${staging}/pack.json`)) {
      return;
    }
    const children: string[] = fs.listFileSync(staging)
      .filter((item: string) => item !== '__MACOSX' && item !== '.DS_Store');
    if (children.length !== 1) {
      return;
    }
    const wrapper = `${staging}/${children[0]}`;
    let isWrapper = false;
    try {
      isWrapper = fs.lstatSync(wrapper).isDirectory() && fs.accessSync(`${wrapper}/pack.json`);
    } catch (err) {
      isWrapper = false;
    }
    if (!isWrapper) {
      return;
    }
    for (const item of fs.listFileSync(wrapper)) {
      fs.renameSync(`${wrapper}/${item}`, `${staging}/${item}`);
    }
    fs.rmdirSync(wrapper);
    this.safeRemove(`${staging}/__MACOSX`);
    this.safeRemove(`${staging}/.DS_Store`);
  }

  private uniquePath(directory: string, baseName: string): string {
    let candidate = `${directory}/${baseName}`;
    let index = 2;
    while (fs.accessSync(candidate) && index <= 99) {
      candidate = `${directory}/${baseName}-${index}`;
      index++;
    }
    return candidate;
  }

  private fileNameOf(uri: string): string {
    const withoutQuery = uri.split('?')[0];
    const segments = withoutQuery.split('/');
    const name = segments[segments.length - 1];
    try {
      return decodeURIComponent(name);
    } catch (err) {
      return name;
    }
  }

  private copyPath(source: string, destination: string): void {
    this.ensureDir(this.dirname(destination));
    const sourceFile = fs.openSync(source, fs.OpenMode.READ_ONLY);
    try {
      const destinationFile = fs.openSync(destination,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(sourceFile.fd, destinationFile.fd);
      } finally {
        fs.closeSync(destinationFile);
      }
    } finally {
      fs.closeSync(sourceFile);
    }
  }

  private safeRemove(path: string): void {
    try {
      if (!fs.accessSync(path)) {
        return;
      }
      const stat = fs.lstatSync(path);
      if (stat.isDirectory()) {
        fs.rmdirSync(path);
      } else {
        fs.unlinkSync(path);
      }
    } catch (err) {
      console.warn(`[gp-next-bridge] 清理失败: ${path} (${errorText(err as Object)})`);
    }
  }
}
