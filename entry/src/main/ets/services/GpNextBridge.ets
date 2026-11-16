import { fileIo as fs } from '@kit.CoreFileKit';
import fileUri from '@ohos.file.fileuri';
import { zlib } from '@kit.BasicServicesKit';
import { util, process } from '@kit.ArkTS';
import { common, bundleManager } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';

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
 *
 * ⚠️ 例外：0.16.1 起 payload 在**启动最前面**加了一道"云存档日志"检查 —— 它调 `cloud_journal_read`，
 * 返回 null 表示"没有未完成的云操作"（放行），而**抛错会被当成致命错误**：
 * 实测缺该命令时游戏停在「云存档恢复尚未完成 / CLOUD_RECOVERY_INVALID」页面，完全不启动。
 * 因此云存档这一组命令按"本壳层没有云后端"的**真实语义**回值：
 * 日志不存在 ⇒ null；信任通道不可用 ⇒ {available:false}；纯上报型 ⇒ 静默接受。
 */

interface GpNextHeaders {
  path: string;
  options?: string;
}

interface GpNextOptions {
  baseDir?: number;
  /** 仅 plugin:fs|rename 使用：源 / 目标各自的 baseDir */
  oldPathBaseDir?: number;
  newPathBaseDir?: number;
  recursive?: boolean;
  /** 仅 plugin:dialog|open 使用：多选 / 选目录（对应 Tauri open 的选项） */
  multiple?: boolean;
  directory?: boolean;
  encoding?: string;
  headers?: GpNextHeaders;
  defaultPath?: string;
  filters?: Object[];
}

interface GpNextArgs {
  path?: string;
  /** plugin:path|join 用：任意段，前面段会被后面的绝对路径段替换（Tauri 语义） */
  paths?: string[];
  /** 0.16.27 包存储（gp_next_*）：内容寻址的包 digest */
  digest?: string;
  /** gp_next_install_pack 用：包内文件列表 */
  files?: GpNextPackFile[];
  /** gp_next_capture_local_pack 用：本地包源路径（如 gp-next/packs/xxx） */
  source?: string;
  oldPath?: string;
  newPath?: string;
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

/**
 * Tauri plugin-fs 的 `FileInfo`（`plugin:fs|lstat` / `plugin:fs|stat` 的返回值）。
 * 0.15.0 的数据包加载器靠它逐级校验路径祖先：`isSymlink` 为真就拒绝、`!isDirectory` 也拒绝，
 * 最后按 `isFile` 分流。旧负载里这条命令由页面内联的 polyfill 用 localStorage 桩糊过去，
 * 0.15.0 去掉 polyfill 后必须由原生桥提供 —— 实测缺失时报
 * 「[Files] 未兼容的 GP-Next 命令：plugin:fs|lstat」，模组页显示 1 项错误。
 */
interface GpNextFileInfo {
  isFile: boolean;
  isDirectory: boolean;
  isSymlink: boolean;
  size: number;
  mtime: number;
  atime: number;
  birthtime: number;
  readonly: boolean;
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
 * `gp_next_local_package_inventory` 的返回元素（0.16.27 新增）。
 * payload 只把它当作 Map 用：path → fingerprint，指纹只比相等，格式随意。
 */
interface GpNextLocalPackEntry {
  path: string;
  fingerprint: string;
}

/** 0.16.27 包存储里"一个包内文件"的传输形态（path + base64 内容） */
interface GpNextPackFile {
  path: string;
  base64: string;
}

/** gp_next_capture_local_pack 的返回：目录包给 files，zip 包给 zip 的 base64 */
interface GpNextCaptureResult {
  zip: string | null;
  files: GpNextPackFile[];
}

/**
 * 性能页"原生指标"块的数据结构，字段名必须和 payload 的 tab-performance 对齐：
 * 面板按 `native.status === 'available'` 决定是否渲染这些行，并按 `process.cpuStatus`
 * / `system.cpuStatus` 逐行判断（不设的话会被当成 available 去渲染 undefined）。
 */
interface GpNextSnapshotOs {
  name: string;
  longVersion: string;
  arch: string;
}

interface GpNextSnapshotApp {
  version: string;
}

interface GpNextSnapshotProcess {
  pid: number;
  cpuStatus: string;
  memoryBytes: number | null;
}

interface GpNextSnapshotSystem {
  cpuStatus: string;
  usedMemoryBytes: number | null;
  totalMemoryBytes: number | null;
}

interface GpNextNativeSnapshot {
  source: string;
  status: string;
  collectedAtMs: number;
  os: GpNextSnapshotOs;
  app: GpNextSnapshotApp;
  process: GpNextSnapshotProcess;
  system: GpNextSnapshotSystem;
}

/**
 * 宿主能力（都涉及 UI / 系统对话框）以函数参数传入，而不是用对象字面量实现接口——
 * ArkTS 的 arkts-no-untyped-obj-literals 不允许在调用处用字面量实现带方法的接口。
 */
export type GpNextOpenExternal = (url: string) => void;
export type GpNextPickSaveTarget = (fileName: string) => Promise<string | null>;
export type GpNextImportPackages = () => Promise<void>;
/**
 * 选文件（新版模组导入）：extensions 是**不带点**的后缀数组，multiple 为多选。
 * 返回用户选中的 uri 列表；用户取消时返回空数组（与"选择失败"合并处理，因为桥里两者结果都是"没有文件"）。
 */
export type GpNextPickOpenTargets = (extensions: string[], multiple: boolean, directory: boolean) => Promise<string[]>;

/**
 * 顶部提示（宿主页面实现）。导出失败时**必须**让用户看见原因：
 * 之前只写日志，用户只看到系统选择器建的空文件，完全不知道发生了什么。
 */
export type GpNextNotify = (message: string, duration: number) => void;

/** plugin:dialog|open 的 filters 元素 */
interface GpNextDialogFilter {
  name?: string;
  extensions?: string[];
}

/** gp-next/settings.json 的结构（与 payload 内 polyfill 预置的默认值保持一致） */
interface GpNextScrollSensitivity {
  enabled: boolean;
  wheel: number;
  discreteMinIntervalMs: number;
}

interface GpNextSettingsFile {
  version: number;
  packOrder: string[];
  disabledPacks: string[];
  scrollSensitivity: GpNextScrollSensitivity;
}

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
  private pickOpenTargetsHandler: GpNextPickOpenTargets;
  private notifyHandler: GpNextNotify;
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
    importPackages: GpNextImportPackages,
    pickOpenTargets: GpNextPickOpenTargets,
    notify: GpNextNotify) {
    this.openExternalHandler = openExternal;
    this.pickSaveTargetHandler = pickSaveTarget;
    this.importPackagesHandler = importPackages;
    this.pickOpenTargetsHandler = pickOpenTargets;
    this.notifyHandler = notify;
    this.baseDir = GpNextBridge.trimTrailingSlash(context.filesDir);
    this.root = `${this.baseDir}/${GP_NEXT_DIR}`;
    this.exportDir = `${this.root}/${EXPORT_DIR}`;
    this.incomingDir = `${this.root}/${INCOMING_DIR}`;
    this.ensureBaseDirs();
    console.info(`[gp-next-bridge] 数据根目录: ${this.root}`);
    this.seedDefaultSettings();
  }

  /**
   * 预建 gp-next 目录树（桌面版由安装器负责）。
   *
   * 两点考虑：
   *  1. 每个 ensureDir 单独 try/catch —— 它是 @throws 方法，而 IDE 的 ArkTSCheck 会在调用点
   *     报 28040（Function_may_throw_exceptions_Special_handling_is_required）；编译器对构造函数
   *     里的调用点是豁免的，两边规则不一致，包起来两边都干净。
   *  2. 更重要的是健壮性：构造函数抛异常会让原生桥整个注册不上，面板就彻底失去文件能力；
   *     某个目录建不出来时只记日志、继续走，剩下的能力仍然可用。
   */
  private ensureBaseDirs(): void {
    const dirs: string[] = [
      this.root,
      `${this.root}/packs`,
      `${this.root}/patches`,
      this.exportDir,
      this.incomingDir
    ];
    for (const dir of dirs) {
      try {
        this.ensureDir(dir);
      } catch (err) {
        console.error(`[gp-next-bridge] 创建目录失败: ${dir} (${errorText(err as Object)})`);
      }
    }
  }

  /**
   * 首次启动预置 gp-next/settings.json。
   *
   * 必要性：GP-Next 加载补丁的第一步就是读这个文件，而且**没有兜底捕获**——桌面版由安装器/首次保存
   * 保证它存在。页面自带的 polyfill 会把读失败吞成默认值，所以这个前提被掩盖；原生桥按 Tauri 语义
   * 抛错后，首次启动该读取失败会中断整个面板初始化（补丁 / 修改器 / 模组 / 数据页全部不加载）。
   * 因此这里按 polyfill 当初的默认结构预置一份；已存在则原样保留用户的设置。
   */
  private seedDefaultSettings(): void {
    const settingsPath = `${this.root}/settings.json`;
    try {
      if (fs.accessSync(settingsPath)) {
        return;
      }
      const defaults: GpNextSettingsFile = {
        version: 1,
        packOrder: [],
        disabledPacks: [],
        scrollSensitivity: {
          enabled: true,
          wheel: 1,
          discreteMinIntervalMs: 0
        }
      };
      const file = fs.openSync(settingsPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, JSON.stringify(defaults));
      } finally {
        fs.closeSync(file);
      }
      console.info(`[gp-next-bridge] 已预置默认设置文件: ${settingsPath}`);
    } catch (err) {
      console.error(`[gp-next-bridge] 预置默认设置文件失败: ${errorText(err as Object)}`);
    }
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
      // GP-Next 大量使用"探测式读取"（例如逐类型检查 __gpn_edits 里有没有手工编辑覆盖），
      // 文件不存在是它的正常分支。打 ERROR 会在每次启动时刷出上百行 hilog，这里降到 debug。
      if (message.startsWith('File not found:')) {
        console.debug(`[gp-next-bridge] ${command} 未命中: ${message}`);
      } else {
        console.error(`[gp-next-bridge] ${command} 失败: ${message}`);
      }
      return `{"ok":false,"error":${JSON.stringify(message)},"code":"gp_next_error"}`;
    }
  }

  /** 返回值统一为 JSON 片段，交给 invoke 拼装（避免 ArkTS 里 Object 与原始类型互转的麻烦） */
  /**
   * @throws { BusinessError } 文件系统调用失败时向上抛出，由 invoke 统一转成失败响应
   */  private async dispatch(request: GpNextRequest): Promise<string> {
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
      // 0.16.27 新增：Tauri 的 path.join(...segments)。见 joinPath 的语义说明。
      case 'plugin:path|join': {
        const segments: string[] = args && args.paths ? args.paths : [];
        return JSON.stringify(this.joinPath(segments));
      }
      // 0.16.27 新增：多屏全屏（移动端没有显示器概念）⇒ 静默接受
      case 'plugin:window|set_fullscreen_on_monitor':
        return 'null';

      // ---- 文件系统 ----
      case 'plugin:fs|read_text_file':
      case 'plugin:fs|read_file': {
        const target = this.resolve(this.requirePath(args), this.effectiveOptions(request));
        const bytes = this.readBytes(target);
        const value: GpNextBytesValue = { __gpNextBytes: this.base64.encodeToStringSync(bytes) };
        return JSON.stringify(value);
      }
      case 'plugin:fs|write_text_file':
      case 'plugin:fs|write_file': {
        return JSON.stringify(this.writeFile(request));
      }
      case 'plugin:fs|lstat':
      case 'plugin:fs|stat': {
        const target = this.resolve(this.requirePath(args), this.effectiveOptions(request));
        return JSON.stringify(this.statInfo(target, command === 'plugin:fs|lstat'));
      }
      case 'plugin:fs|rename': {
        if (!args || !args.oldPath || !args.newPath) {
          throw new Error('GP-Next rename 需要 oldPath / newPath');
        }
        const options: GpNextOptions | undefined = this.effectiveOptions(request);
        const oldOptions: GpNextOptions = { baseDir: options ? options.oldPathBaseDir : undefined };
        const newOptions: GpNextOptions = { baseDir: options ? options.newPathBaseDir : undefined };
        const oldTarget = this.resolve(args.oldPath, oldOptions);
        const newTarget = this.resolve(args.newPath, newOptions);
        this.ensureDir(this.dirname(newTarget));
        fs.renameSync(oldTarget, newTarget);
        return 'null';
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
        // Tauri 的 remove 只有显式传 recursive:true 才删非空目录；这里保持一致（默认 false）
        this.removePath(target, options !== undefined && options.recursive === true);
        return 'null';
      }

      // ---- 文件选择（payload 1.5.5 起，新版模组导入走这里）----
      // 桌面版把选中文件的路径直接交出去即可；移动端原生 fs 只能读沙箱（resolve() 会拒绝沙箱外路径），
      // 所以先把用户选中的文件拷进 .incoming/，再返回沙箱内的真实路径。
      // 负载随后用 lstat / read_dir / read_file 读它；zip 由负载自己的 inflate 解析，壳层不需要解压。
      case 'plugin:dialog|open': {
        const pickOptions: GpNextOptions | undefined = args ? args.options : undefined;
        const multiple: boolean = pickOptions !== undefined && pickOptions.multiple === true;
        const directory: boolean = pickOptions !== undefined && pickOptions.directory === true;

        const picked: string[] = await this.pickOpenTargetsHandler(this.openExtensionsOf(args), multiple, directory);
        if (picked.length === 0) {
          console.info('[gp-next-bridge] 用户取消了选择');
          return 'null';
        }
        this.ensureDir(this.incomingDir);
        const accepted: string[] = [];
        for (const uri of picked) {
          if (directory) {
            const landed: string = await this.copyDirectoryFromUri(uri, this.incomingDir);
            accepted.push(landed);
            console.info(`[gp-next-bridge] 已接收用户选择（目录）: ${landed}`);
            continue;
          }
          const destination: string = this.uniquePath(this.incomingDir, this.fileNameOf(uri));
          this.copyPath(uri, destination);
          accepted.push(destination);
          console.info(`[gp-next-bridge] 已接收用户选择: ${destination}`);
        }
        return multiple ? JSON.stringify(accepted) : JSON.stringify(accepted[0]);
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

      // ---- 本地数据包清单（0.16.27 新增，启动时 beforeEngineImport 会调）----
      // payload 用法：const m = new Map((await readInventory()).map(e => [e.path, e.fingerprint]))
      // 用来判断 gp-next/packs 下哪些包"自上次记录后没变"，从而跳过重复同步。
      // 之前未兼容 ⇒ 启动日志里一条 WARN「Local source synchronization failed」。
      case 'gp_next_local_package_inventory': {
        const inventory: GpNextLocalPackEntry[] = [];
        const packsDir: string = `${this.root}/packs`;
        try {
          if (fs.accessSync(packsDir)) {
            const names: string[] = fs.listFileSync(packsDir);
            for (let index = 0; index < names.length; index++) {
              const name: string = names[index];
              const full: string = `${packsDir}/${name}`;
              try {
                const info = fs.statSync(full);
                // 指纹只用于"是否变化"的相等比较：大小 + 修改时间（毫秒）
                inventory.push({
                  path: `gp-next/packs/${name}`,
                  fingerprint: `${info.size}-${Math.floor(info.mtime * 1000)}`
                });
              } catch (statErr) {
                console.warn(`[gp-next-bridge] 读取本地包信息失败: ${full}`);
              }
            }
          }
        } catch (listErr) {
          console.warn(`[gp-next-bridge] 列本地包目录失败: ${errorText(listErr as Object)}`);
        }
        return JSON.stringify(inventory);
      }

      // ---- 本地包存储后端（0.16.27 新增 gp_next_*，内容寻址）----
      // ⚠️ 语义要点：**抛错会被 payload 包成 `INSTALL_CORRUPT`**（启动日志里
      //    「Installed package is corrupt」就是这么来的）；返回 `null` 则被当成"没有这个包"，无害。
      // 读类命令：返回真实内容或 null；写类命令（安装/抓取）：明确报未实现，不假装成功。
      case 'gp_next_read_package_index': {
        // 本壳层没有维护包索引文件（install_pack 未实现）⇒ 一律"没有该包"
        const digest: string = args && args.digest ? args.digest : '';
        const packDir: string = `${this.root}/installed/${digest}`;
        let hasContent: boolean = false;
        try {
          if (digest.length > 0 && fs.accessSync(packDir)) {
            hasContent = fs.listFileSync(packDir).length > 0;
          }
        } catch (indexErr) {
          hasContent = false;
        }
        if (!hasContent) {
          return 'null';
        }
        // 目录里有内容但没有索引：返回"没有索引"比编造一份更诚实
        console.warn(`[gp-next-bridge] 包 ${digest} 有内容但无索引，按无索引处理`);
        return 'null';
      }
      case 'gp_next_read_installed_pack': {
        const digest: string = args && args.digest ? args.digest : '';
        const packDir: string = `${this.root}/installed/${digest}`;
        if (digest.length === 0 || !fs.accessSync(packDir)) {
          return 'null';
        }
        const files: GpNextPackFile[] = [];
        try {
          const names: string[] = fs.listFileSync(packDir);
          for (let index = 0; index < names.length; index++) {
            const name: string = names[index];
            const full: string = `${packDir}/${name}`;
            const info = fs.statSync(full);
            if (!info.isFile()) {
              continue;
            }
            files.push({ path: name, base64: this.base64.encodeToStringSync(this.readBytes(full)) });
          }
        } catch (readErr) {
          console.warn(`[gp-next-bridge] 读取已安装包失败: ${errorText(readErr as Object)}`);
          return 'null';
        }
        return JSON.stringify(files);
      }
      case 'gp_next_read_package_file': {
        const digest: string = args && args.digest ? args.digest : '';
        const relative: string = args && args.path ? args.path : '';
        const full: string = `${this.root}/installed/${digest}/${relative}`;
        const resolved: string = this.resolve(full, undefined);
        const value: GpNextPackFile = {
          path: relative,
          base64: this.base64.encodeToStringSync(this.readBytes(resolved))
        };
        return JSON.stringify(value);
      }
      // 写类：安装本地包到内容寻址目录（0.16.27 的包存储）
      // ⚠️ 这里**不能抛错**：它跑在 beforeEngineImport 里，抛错 = Cocos 启动失败。
      case 'gp_next_install_pack': {
        const digest: string = args && args.digest ? args.digest : '';
        if (digest.length === 0) {
          return 'null';
        }
        const files: GpNextPackFile[] = args && args.files ? args.files : [];
        const packDir: string = `${this.root}/installed/${digest}`;
        this.ensureDir(packDir);
        for (let index = 0; index < files.length; index++) {
          const entry: GpNextPackFile = files[index];
          const relative: string = entry.path.replace(/^\/+/, '');
          if (relative.length === 0) {
            continue;
          }
          const target: string = this.resolve(`${packDir}/${relative}`, undefined);
          this.ensureDir(this.dirname(target));
          const bytes: Uint8Array = this.base64.decodeSync(entry.base64);
          const file = fs.openSync(target, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
          try {
            fs.writeSync(file.fd, bytes.buffer as ArrayBuffer);
          } finally {
            fs.closeSync(file);
          }
        }
        console.info(`[gp-next-bridge] 已安装本地包 ${digest}（${files.length} 个文件）`);
        return 'null';
      }
      // 抓取本地包源（目录 → 文件列表；zip 文件 → zip 的 base64）
      // 返回 null 会让 payload 抛 "Package source is missing" ⇒ 启动失败，所以空目录返回空 files。
      case 'gp_next_capture_local_pack': {
        const source: string = args && args.source ? args.source : '';
        const captured: GpNextCaptureResult = { zip: null, files: [] };
        if (source.length === 0) {
          return JSON.stringify(captured);
        }
        let resolved: string;
        try {
          resolved = this.resolve(source, { baseDir: 14 });
        } catch (resolveErr) {
          console.warn(`[gp-next-bridge] capture 路径越界: ${source}`);
          return JSON.stringify(captured);
        }
        if (!fs.accessSync(resolved)) {
          return JSON.stringify(captured);
        }
        const info = fs.statSync(resolved);
        if (info.isFile()) {
          captured.zip = this.base64.encodeToStringSync(this.readBytes(resolved));
          return JSON.stringify(captured);
        }
        const collected: GpNextPackFile[] = [];
        this.collectFiles(resolved, '', collected, 0);
        captured.files = collected;
        return JSON.stringify(captured);
      }

      // ---- 云存档（payload 0.16.1 新增；本壳层没有云后端，按真实语义回值）----
      // 启动最前面那道检查：null = "没有未完成的云操作" ⇒ 放行。
      // ⚠️ 这条**不能抛错**，否则 payload 会判成 CLOUD_RECOVERY_INVALID 并停止启动。
      case 'cloud_journal_read':
        return 'null';
      // 云面板会读 .available；false ⇒ 面板显示"云端已阻止"，而不是抛错或假装可用
      case 'cloud_trusted_status':
        return '{"available":false}';
      // 纯上报型（启动结果 / 保存失败原因）：本壳层没有接收方，静默接受
      case 'cloud_startup_result':
      case 'cloud_save_failed':
        return 'null';

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
        // 性能页的"原生指标"块：只填确实拿得到的（OS/架构/应用版本/PID/进程 RSS），
        // CPU 与系统内存 HarmonyOS 不给普通应用接口，显式标 unavailable。
        return JSON.stringify(this.nativeSnapshot());

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

  /**
   * Tauri `path.join(...segments)` 的语义（= Rust `PathBuf::push`）：
   * 逐段拼接；遇到**绝对段**（以 `/` 开头）就丢弃之前的结果重新开始；
   * 空段忽略；重复斜杠折叠。
   * 注意：这里不做 `..` 归一（Rust 的 push 也不做），交给后续 resolve() 去拒绝越界。
   */
  private joinPath(segments: string[]): string {
    let joined: string = '';
    for (let index = 0; index < segments.length; index++) {
      const raw: string = segments[index];
      if (raw === undefined || raw === null) {
        continue;
      }
      const segment: string = raw.trim().replace(/\\/g, '/');
      if (segment.length === 0) {
        continue;
      }
      if (segment.startsWith('/')) {
        joined = segment;
        continue;
      }
      if (joined.length === 0) {
        joined = segment;
      } else if (joined.endsWith('/')) {
        joined = joined + segment;
      } else {
        joined = joined + '/' + segment;
      }
    }
    return joined;
  }

  /**
   * 递归收集目录下的文件（供 gp_next_capture_local_pack 用）。
   * 深度上限 8、文件数上限 4000，避免异常目录把内存/时间打爆。
   */
  private collectFiles(dir: string, prefix: string, out: GpNextPackFile[], depth: number): void {
    if (depth > 8 || out.length >= 4000) {
      return;
    }
    let names: string[];
    try {
      names = fs.listFileSync(dir);
    } catch (listErr) {
      return;
    }
    for (let index = 0; index < names.length; index++) {
      if (out.length >= 4000) {
        return;
      }
      const name: string = names[index];
      const full: string = `${dir}/${name}`;
      const relative: string = prefix.length === 0 ? name : `${prefix}/${name}`;
      try {
        const info = fs.statSync(full);
        if (info.isDirectory()) {
          this.collectFiles(full, relative, out, depth + 1);
        } else if (info.isFile()) {
          out.push({ path: relative, base64: this.base64.encodeToStringSync(this.readBytes(full)) });
        }
      } catch (statErr) {
        continue;
      }
    }
  }

  private requirePath(args: GpNextArgs | undefined): string {    const path: string | undefined = args ? args.path : undefined;
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

  /**
   * @throws { BusinessError } 文件系统调用失败时向上抛出，由 invoke 统一转成失败响应
   */  private ensureDir(path: string, recursive: boolean = true): void {
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

  /**
   * @throws { BusinessError } 文件系统调用失败时向上抛出，由 invoke 统一转成失败响应
   */  private readBytes(path: string): Uint8Array {
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

  /** Tauri FileInfo：lstat/stat 的返回值（见 GpNextFileInfo 的说明） */
  private statInfo(path: string, noFollow: boolean): GpNextFileInfo {
    // ⚠️ fs.*Sync 必须**字面落在 try 内**：ArkTS Check 看的是"调用点所在的作用域"，
    // 把它们挪到另一个函数里、再由 try 包住调用方 —— 检查器照样报"函数可能抛异常"（实测）。
    try {
      const stat = noFollow ? fs.lstatSync(path) : fs.statSync(path);
      const info: GpNextFileInfo = {
        isFile: stat.isFile(),
        isDirectory: stat.isDirectory(),
        isSymlink: stat.isSymbolicLink(),
        size: stat.size,
        // Tauri 的 FileInfo 用毫秒；HarmonyOS 的 Stat.mtime/atime/ctime 是秒
        mtime: stat.mtime * 1000,
        atime: stat.atime * 1000,
        birthtime: stat.ctime * 1000,
        readonly: false
      };
      return info;
    } catch (err) {
      const error = err as BusinessError;
      console.warn(`stat 失败: ${path}: code=${error.code}, message=${error.message}`);
      throw new Error(`stat 失败: ${path}: code=${error.code}, message=${error.message}`);
    }
  }

  /**
   * @throws { BusinessError } 文件系统调用失败时向上抛出，由 invoke 统一转成失败响应
   */
  private writeFile(request: GpNextRequest): null {
    const args: GpNextArgs | undefined = request.args;
    const headers: GpNextHeaders | undefined = request.options ? request.options.headers : undefined;
    let path: string | undefined = headers ? decodeURIComponent(headers.path) : undefined;
    if (!path && args) {
      path = args.path;
    }
    // 兼容：还有调用者把路径**直接当第二参**传成字符串（而不是 { path }）。
    // 这类调用此前会落到下面的"路径缺失"分支；字符串参数含义无歧义，直接当路径用。
    if (!path && args) {
      const argsAsObject: Object = args as Object;
      if (typeof argsAsObject === 'string') {
        path = argsAsObject as string;
      }
    }
    if (!path) {
      // 诊断：把这次调用的"形状"打出来（只打键名与类型，不打内容，避免日志里出现大块数据）
      const argsKeys: string = args ? Object.keys(args as Object).join(',') : 'none';
      const optionsKeys: string = request.options ? Object.keys(request.options as Object).join(',') : 'none';
      const headersKeys: string = headers ? Object.keys(headers as Object).join(',') : 'none';
      const argsType: string = args === undefined ? 'undefined' : typeof (args as Object);
      console.error(`[gp-next-bridge] write_text_file shape: argsType=${argsType} argsKeys=[${argsKeys}] ` +
        `optionsKeys=[${optionsKeys}] headersKeys=[${headersKeys}]`);
      throw new Error('GP-Next 写入路径缺失（headers.path）');
    }
    const target = this.resolve(path, this.effectiveOptions(request));
    const bytes: Uint8Array = args && args.__gpNextBytes
      ? this.base64.decodeSync(args.__gpNextBytes)
      : new Uint8Array(0);
    // 导出链路：0 字节是"内容没到桥"的硬故障，不能把空文件交给用户。
    if (this.pendingExports.has(target) && bytes.byteLength === 0) {
      this.pendingExports.delete(target);
      throw new Error('导出内容为空（0 字节），已中止');
    }
    this.ensureDir(this.dirname(target));
    const file = fs.openSync(target, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      // ⚠️ 不能写 bytes.buffer：那会忽略视图的 byteOffset/byteLength。
      // 也不能用 WriteOptions.offset —— 官方语义是"**文件**写入位置"，不是缓冲区偏移。
      // 视图覆盖整块（最常见）时直接写，零拷贝；否则先切出精确区间。
      if (bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength) {
        fs.writeSync(file.fd, bytes.buffer as ArrayBuffer);
      } else {
        const exact = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
        fs.writeSync(file.fd, exact as ArrayBuffer);
      }
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

  /**
   * @throws { BusinessError } 文件系统调用失败时向上抛出，由 invoke 统一转成失败响应
   */  private readDir(path: string): GpNextDirEntry[] {
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

  /**
   * @throws { BusinessError } 文件系统调用失败时向上抛出，由 invoke 统一转成失败响应
   */  private removePath(path: string, recursive: boolean): void {
    // 先判根目录：原来这一步在"路径是否存在"之后，路径不存在时根本走不到
    if (path === this.root || path === this.baseDir) {
      throw new Error('拒绝删除 GP-Next 根目录');
    }
    if (!fs.accessSync(path)) {
      // Tauri 的 remove 对不存在的路径报 NotFound；此处不再"静默成功"，让面板看到明确失败
      throw new Error(`要删除的路径不存在: ${path}`);
    }
    const stat = fs.lstatSync(path);
    if (stat.isSymbolicLink()) {
      throw new Error(`拒绝操作符号链接: ${path}`);
    }
    if (stat.isDirectory()) {
      if (recursive) {
        this.removeDirectoryRecursive(path);
      } else {
        // 非递归：只允许删空目录（fs.rmdirSync 对非空目录会报错）
        try {
          fs.rmdirSync(path);
        } catch (err) {
          console.warn(`[gp-next-bridge] 非递归删除失败（目录可能非空，需 recursive:true）: ${path}`);
          throw err as Error;
        }
      }
    } else {
      fs.unlinkSync(path);
    }
  }

  /**
   * 手动递归删除目录（先删子项、再删目录自身）。
   * 注意：本版本 SDK **没有** fs.rmSync，rmdirSync 只能删空目录，所以只能自己递归。
   */
  private removeDirectoryRecursive(path: string): void {
    // ⚠️ 同 statInfo：fs.*Sync 必须字面落在 try 内，否则 ArkTS Check 仍会报"可能抛异常"。
    try {
      const children: string[] = fs.listFileSync(path);
      for (let index = 0; index < children.length; index++) {
        const childPath = `${path}/${children[index]}`;
        const childStat = fs.lstatSync(childPath);
        if (childStat.isSymbolicLink()) {
          throw new Error(`拒绝操作符号链接: ${childPath}`);
        }
        if (childStat.isDirectory()) {
          this.removeDirectoryRecursive(childPath);
        } else {
          fs.unlinkSync(childPath);
        }
      }
      fs.rmdirSync(path);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`删除目录失败: ${path}: code=${error.code}, message=${error.message}`);
      throw new Error(`删除目录失败: ${path}: code=${error.code}, message=${error.message}`);
    }
  }

  // ==================== 另存为 ====================

  /**
   * Tauri 的 save 对话框语义：先问用户存哪儿，再返回一个可写路径。
   * 这里返回沙箱内的临时路径，等 GP-Next 写完再由 deliverExport 复制到用户选定的 uri。
   */
  /**
   * @throws { BusinessError } 文件系统调用失败时向上抛出，由 invoke 统一转成失败响应
   */  private async prepareExport(args: GpNextArgs | undefined): Promise<string | null> {
    const options: GpNextOptions | undefined = args ? args.options : undefined;
    const suggested: string = options && options.defaultPath ? this.safeFileName(options.defaultPath) : 'export.json';
    const targetUri: string | null = await this.pickSaveTargetHandler(suggested);
    if (!targetUri) {
      console.info('[gp-next-bridge] 用户取消了另存为');
      return null;
    }
    this.ensureDir(this.exportDir);
    const tempPath: string = `${this.exportDir}/${Date.now()}-${suggested}`;
    // 记录"临时路径 → 用户位置"的登记，便于排查交付是否命中
    console.info(`[gp-next-bridge] 另存为登记 temp=${tempPath}, target=${targetUri}`);
    this.pendingExports.set(tempPath, targetUri);
    return tempPath;
  }

  private deliverExport(tempPath: string, targetUri: string): void {
    let tempSize: number = -1;
    try {
      tempSize = fs.statSync(tempPath).size;
    } catch (sizeErr) {
      tempSize = -1;
    }
    try {
      this.copyPath(tempPath, targetUri);
      fs.unlinkSync(tempPath);
      console.info(`[gp-next-bridge] 已导出到用户选择的位置: ${targetUri} (${tempSize} 字节)`);
      this.notifyHandler(`存档已导出（${Math.max(1, Math.round(tempSize / 1024))} KB）`, 3000);
    } catch (err) {
      const error = err as BusinessError;
      // 失败必须让用户看见：以前只写日志，用户只看到系统选择器建的空文件。
      // 临时文件**保留**（里面是完整的存档内容），并提示用户路径，便于反馈。
      console.warn(`[gp-next-bridge] 导出落盘失败 code=${error.code}, message=${error.message}, ` +
        `tempSize=${tempSize}, isUri=${targetUri.startsWith('file://')}`);
      this.notifyHandler(`导出失败：${error.message}（数据已暂存在应用目录）`, 6000);
    }
  }

  /** plugin:dialog|open 的 filters → 不带点的后缀数组 */
  private openExtensionsOf(args: GpNextArgs | undefined): string[] {
    const result: string[] = [];
    const options: GpNextOptions | undefined = args ? args.options : undefined;
    if (options === undefined || options.filters === undefined) {
      return result;
    }
    for (let index = 0; index < options.filters.length; index++) {
      const filter: GpNextDialogFilter = options.filters[index] as GpNextDialogFilter;
      const extensions: string[] | undefined = filter.extensions;
      if (extensions === undefined) {
        continue;
      }
      for (let item = 0; item < extensions.length; item++) {
        const text: string = extensions[item].trim();
        if (text.length > 0) {
          result.push(text.startsWith('.') ? text.substring(1) : text);
        }
      }
    }
    return result;
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

  /**
   * @throws { BusinessError } 文件系统调用失败时向上抛出，由 invoke 统一转成失败响应
   */  private async importArchive(uri: string, name: string): Promise<void> {
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
  /**
   * @throws { BusinessError } 文件系统调用失败时向上抛出，由 invoke 统一转成失败响应
   */  private flattenPack(staging: string): void {
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

  /**
   * @throws { BusinessError } 文件系统调用失败时向上抛出，由 invoke 统一转成失败响应
   */  private uniquePath(directory: string, baseName: string): string {
    let candidate = `${directory}/${baseName}`;
    let index = 2;
    while (fs.accessSync(candidate) && index <= 99) {
      candidate = `${directory}/${baseName}-${index}`;
      index++;
    }
    // 99 次都没找到空位：绝不能把已存在的路径返回给 copyPath（那边是 TRUNCATE，会静默覆盖用户文件）
    if (fs.accessSync(candidate)) {
      const stamp = Date.now();
      candidate = `${directory}/${baseName}-${stamp}`;
      let tieBreaker = 1;
      while (fs.accessSync(candidate) && tieBreaker <= 999) {
        candidate = `${directory}/${baseName}-${stamp}-${tieBreaker}`;
        tieBreaker++;
      }
      if (fs.accessSync(candidate)) {
        throw new Error(`无法为 ${baseName} 找到可用的唯一文件名`);
      }
      console.warn(`[gp-next-bridge] 同名文件已达上限，改用时间戳命名: ${candidate}`);
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

  /**
   * @throws { BusinessError } 文件系统调用失败时向上抛出，由 invoke 统一转成失败响应
   */  private copyPath(source: string, destination: string): void {
    // ⚠️ 只有目标是**沙箱路径**时才建父目录。目标是选择器给的 `file://docs/...` 时：
    //    · 父目录已存在（系统选择器保证），建目录纯属多余；
    //    · 那层权限只覆盖"这一个文件"，别去碰它的父目录。
    if (!destination.startsWith('file://')) {
      this.ensureDir(this.dirname(destination));
    }
    const sourceFile = fs.openSync(source, fs.OpenMode.READ_ONLY);
    try {
      // ⚠️ 必须是 **WRITE_ONLY**：系统选择器对目标文件只授予"写"权限，
      //    用 READ_WRITE 打开会报 13900012 Permission denied（真机实测：
      //    gpnext 用 READ_WRITE 失败、A6 与 base 用 WRITE_ONLY 都成功）。
      const destinationFile = fs.openSync(destination,
        fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(sourceFile.fd, destinationFile.fd);
      } finally {
        fs.closeSync(destinationFile);
      }
    } finally {
      fs.closeSync(sourceFile);
    }
  }

  /**
   * 把用户选中的**整个目录**（picker 给的是 uri）复制进沙箱。
   * fs.copyFileSync 的文档明确写了可传"文件或目录的 URI"并会递归复制，所以不用自己遍历。
   */
  /**
   * @throws { BusinessError } 复制失败时向上抛出，由 invoke 统一转成失败响应
   */
  /**
   * 把用户选中的**整个目录**（picker 给的 uri）复制进沙箱的 incomingDir，返回复制后的沙箱路径。
   *
   * 踩过的坑：
   *  1) fs.copyFileSync(目录uri, 沙箱路径) ⇒ 13900002：copyFileSync 的 dest 也必须是 URI；
   *  2) fs.copy(目录uri, 不存在的目标uri) ⇒ 13900020 Invalid argument：
   *     目标 URI 必须指向**已存在**的目录，让系统把源目录**复制进去**（而不是当作"目标路径"）。
   * 所以这里固定复制进 incomingDir（存在），再把实际落地路径算出来返回给负载。
   */
  private async copyDirectoryFromUri(sourceUri: string, incomingParent: string): Promise<string> {
    const detail: string[] = [];
    const parentUri: string = fileUri.getUriFromPath(incomingParent);
    const src: string = sourceUri.endsWith('/') ? sourceUri.substring(0, sourceUri.length - 1) : sourceUri;
    const attempts: string[] = [];
    try {
      await fs.copy(src, parentUri);
      attempts.push('copy-intro-existing-ok');
    } catch (first) {
      detail.push(`copy(${src} → ${parentUri}) 失败: ${errorText(first as Object)}`);
      try {
        const parentWithSlash: string = parentUri.endsWith('/') ? parentUri : `${parentUri}/`;
        await fs.copy(`${src}/`, parentWithSlash);
        attempts.push('copy-with-trailing-slash-ok');
      } catch (second) {
        detail.push(`copy(${src}/ → ${parentUri}/) 失败: ${errorText(second as Object)}`);
        throw new Error(`复制文件夹失败（incoming=${incomingParent}）：${detail.join(' | ')}`);
      }
    }
    const landed: string = `${incomingParent}/${this.fileNameOf(src)}`;
    let exists = false;
    try {
      exists = fs.accessSync(landed);
    } catch (inner) {
      exists = false;
    }
    if (!exists) {
      // 个别实现会把目录内容直接铺进父目录，而不建同名子目录
      throw new Error(`复制文件夹失败：落地路径不存在（${landed}）；尝试=${attempts.join(',')}`);
    }
    return landed;
  }

  /** 「打开目录」用：列出 gp-next 下的顶层条目（名字 + 文件数/大小），供壳层展示 */
  summarizeDataDir(): string {
    let names: string[] = [];
    try {
      if (!fs.accessSync(this.root)) {
        return 'gp-next 目录尚未创建';
      }
      names = fs.listFileSync(this.root);
    } catch (err) {
      return `读取 gp-next 目录失败：${errorText(err as Object)}`;
    }
    const rows: string[] = [];
    for (const name of names) {
      const full: string = `${this.root}/${name}`;
      try {
        const stat: fs.Stat = fs.lstatSync(full);
        if (stat.isDirectory()) {
          let count = 0;
          try {
            count = fs.listFileSync(full).length;
          } catch (inner) {
            count = 0;
          }
          rows.push(`${name}/ · ${count} 项`);
        } else {
          rows.push(`${name} · ${this.humanSize(stat.size)}`);
        }
      } catch (err) {
        continue;
      }
    }
    if (rows.length === 0) {
      return 'gp-next 目录为空';
    }
    return `gp-next：${rows.join('　|　')}`;
  }

  private humanSize(bytes: number): string {
    if (bytes >= 1024 * 1024) {
      return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    }
    if (bytes >= 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    }
    return `${bytes} B`;
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

  // ==================== 性能页原生指标 ====================

  /**
   * 应用版本；取不到返回空串（面板会显示 unavailable，不会渲染成 undefined）。
   * 内部已 try/catch 兜底，本身不抛异常——标注 @throws 反而会让调用点触发
   * ArkTS 28040（Function_may_throw_exceptions_Special_handling_is_required）。
   */
  private appVersion(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName ? info.versionName : '';
    } catch (err) {
      console.warn(`[gp-next-bridge] 读取应用版本失败: ${errorText(err as Object)}`);
      return '';
    }
  }

  /**
   * 进程 RSS（字节）。
   *
   * HarmonyOS 没有给普通应用查询内存的公开接口（`@ohos.hidebug` 是系统应用专属），
   * 只能试读 /proc/self/statm——第 2 列是驻留页数，页大小按 4K 算。沙箱不允许读时返回 null。
   * 同样内部兜底、不抛异常（原因见 appVersion）。
   */
  private processMemoryBytes(): number | null {
    try {
      const statm: string = fs.readTextSync('/proc/self/statm');
      const parts: string[] = statm.trim().split(' ');
      if (parts.length < 2) {
        return null;
      }
      const pages: number = Number(parts[1]);
      if (!Number.isFinite(pages) || pages <= 0) {
        return null;
      }
      return pages * 4096;
    } catch (err) {
      return null;
    }
  }

  private nativeSnapshot(): GpNextNativeSnapshot {
    const os: GpNextSnapshotOs = {
      name: deviceInfo.osFullName,
      longVersion: deviceInfo.osFullName,
      arch: deviceInfo.abiList
    };
    const app: GpNextSnapshotApp = { version: this.appVersion() };
    const proc: GpNextSnapshotProcess = {
      pid: process.pid,
      cpuStatus: 'unavailable',
      memoryBytes: this.processMemoryBytes()
    };
    const system: GpNextSnapshotSystem = {
      cpuStatus: 'unavailable',
      usedMemoryBytes: null,
      totalMemoryBytes: null
    };
    const snapshot: GpNextNativeSnapshot = {
      source: 'harmonyos/arkts',
      status: 'available',
      collectedAtMs: Date.now(),
      os: os,
      app: app,
      process: proc,
      system: system
    };
    return snapshot;
  }
}
