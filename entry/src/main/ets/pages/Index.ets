import { webview } from '@kit.ArkWeb';
import { common, Want } from '@kit.AbilityKit';
import { FilePickerHelper } from '../common/FilePickerHelper';  // 复用 FilePickerHelper
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit'; // 确保已导入
import { ResourceManager } from '../services/ResourceManager';
import { GpNextBridge } from '../services/GpNextBridge';
import { GPNEXT_SHIM } from '../common/GpNextShim';
import { SettingsPanel } from '../components/SettingsPanel';
import { StatusToast } from '../components/StatusToast';
import { GpFloatingButton } from '../components/GpFloatingButton';
import { RefreshVote, readDisplayInfo } from '../services/RefreshVote';
import { PayloadServer, PAYLOAD_DIR } from '../services/PayloadServer';
import { PanelActions } from '../services/PanelActions';
import { PreferenceStore } from '../services/PreferenceStore';
import { DownloadSaver } from '../services/DownloadSaver';
import { ShellPrefs, DEFAULT_EXPECTED_REFRESH } from '../services/ShellPrefs';
import { parseVp, computeAspectLayout } from '../common/AspectRatio';
import { util } from '@kit.ArkTS';


// GP 入口按钮的无操作自动贴边隐藏延迟（ms）。
// 按钮的外观与几何常量（大小 / 留白 / 贴边宽度 / 触摸容差）在 components/GpFloatingButton.ets
const GP_BUTTON_HIDE_DELAY: number = 4000;

// Web 调试开关（DevTools）：置 true 后可用 hdc fport + chrome://inspect 排查 GP-Next 的失败点。
// ArkWeb 默认关闭；正式发布保持 false（DevTools 常驻会带来额外开销与调试面暴露）。
// 需要排查时改回 true 重新构建即可。
const ENABLE_WEB_DEBUG: boolean = false;

// 网页弹框无人应答时的兜底超时（ms）：到点自动按"取消"回调 JsResult。
// 网页的 alert/confirm/prompt 是同步阻塞的，只要有一次没回调，render 进程就会一直卡住。
const JS_DIALOG_TIMEOUT: number = 120000;

// 画面比例约束区间（3:2 ~ 17:9）与换算逻辑都在 common/AspectRatio.ets

// ==================== 期望帧率投票（可变帧率 / LTPO） ====================
// 背景：鸿蒙的"控帧系统"收集应用的**期望绘制帧率**参与整机刷新率决策；没有高帧率投票时，
// 系统在无触摸/内容静止时会自适应降到 60Hz（真机实测：平板支持 30/60/90/120/144，但
// activeMode 常驻 60，有触摸时回到 120）。本 Web 组件属系统组件，拿不到 XComponent 那套
// 自绘制接口，只能用 displaySync 参与投票。
//
// 代价与限制（官方最佳实践：displaySync 滥用会增加功耗、干扰可变帧率机制）：
//   - 应用会按期望帧率接收 Vsync（回调里刻意不做任何工作）；
//   - 真实生效还取决于 GP-Next 面板的「帧率」设置（默认 60，设成 120 或"不限"才有意义）
//     以及屏幕硬件能力与系统功耗策略 —— 官方原文：期望帧率"不能代表最终实际效果"。
// 想关闭：把 ENABLE_HIGH_REFRESH_VOTE 改成 false。
const ENABLE_HIGH_REFRESH_VOTE: boolean = true;
const HIGH_REFRESH_EXPECTED: number = 120;
const HIGH_REFRESH_MIN: number = 60;


// 壳层自己的偏好键名与默认值都在 services/ShellPrefs.ets（与 PreferenceStore 分工不同）


// ==================== 负载目录 ====================
// 负载放在 rawfile/<PAYLOAD_DIR> 下；前缀规则、LRU 缓存与 MIME 都由 services/PayloadServer.ets
// 统一负责（单一真相点：想改名只改那里的常量 + .gitignore 一行）。
// 触摸/性能补丁的源文件（留在 rawfile 根，由壳层读入后注入页面，不再依赖 HTML 引用）
const TOUCH_PATCH_RAWFILE: string = 'touchPatch.js';


@Entry
@Component
struct CocosJSApp {
  private webController: webview.WebviewController = new webview.WebviewController();
  // 注入到页面的脚本 = GPNEXT_SHIM（接管 __TAURI_INTERNALS__）+ touchPatch.js（触摸/性能补丁）。
  // 必须合成**一条** ScriptItem：javaScriptOnDocumentStart 按**字典序**而不是数组序执行
  //（SDK 原文：executed in the lexicographic order instead of array sequence），
  // 拆成两条无法保证"先 shim、后 touchPatch"；顺序敏感时应整体改用 runJavaScriptOnDocumentStart。
  // 初值只给 shim，真正内容在 aboutToAppear 里读入 touchPatch.js 后拼接。
  private injectedScript: string = GPNEXT_SHIM;
  private filePickerHelper?: FilePickerHelper;
  private readonly downloadSaver: DownloadSaver = new DownloadSaver();   // 下载回调 + 落盘（见 services/DownloadSaver.ets）
  private readonly shellPrefs: ShellPrefs = new ShellPrefs();            // 壳层自己的偏好（见 services/ShellPrefs.ets）
  private timeoutId?: number;
  /** 状态提示淡出后清空文案的定时器（M1：原来没跟踪，导致新提示被旧定时器立刻清空） */
  private fadeOutTimer?: number;
  private hideButtonTimer?: number;
  private prefs?: preferences.Preferences;
  // GP-Next 原生桥：把网页侧的 Tauri 命令（fs / 另存为 / 打开目录）落到 filesDir/gp-next
  private gpNextBridge?: GpNextBridge;

  @State downloadStatus: string = '';
  @State statusOpacity: number = 1;
  @State isLoading: boolean = true;
  @State progress: number = 0;
  @State webReady: boolean = false;

  // 画面比例约束：容器实测尺寸（vp）与 Web 的目标尺寸 / 居中偏移
  @State containerW: number = 0;
  @State containerH: number = 0;
  @State webW: Length = '100%';
  @State webH: Length = '100%';
  @State webX: number = 0;
  @State webY: number = 0;
  // true：Web 铺满整屏；false：约束在 3:2 ~ 17:9，超出部分留黑边
  @State isFillScreen: boolean = false;

  /** 期望帧率投票实例（仅在页面可见期间持有，避免后台空刷帧） */
  private readonly refreshVote: RefreshVote = new RefreshVote();   // 期望刷新率声明（见 services/RefreshVote.ets）
  private readonly preferenceStore: PreferenceStore = new PreferenceStore();   // Preferences 落盘（put 立即 + flush 去抖）
  @State expectedRefresh: string = DEFAULT_EXPECTED_REFRESH;
  @State shellSettingsOpen: boolean = false;
  @State currentRefresh: number = 0;
  @State supportedRefresh: number[] = [];
  @State engineFrameRate: string = '读取中…';   // GP-Next 的帧率设置值
  @State engineFpsMeasured: string = '—';        // 实测帧率（director 帧数采样）
  @State frameSchedulerOn: boolean = false;      // GP-Next「实验帧率调度」是否开启（平板上会明显卡顿）
  @State schedulerFrameRate: string = '已关闭';   // 实验性页的帧率（仅在调度开启时有意义）

  private schedulerWarned: boolean = false;       // 启动警告只提示一次
  private refreshPollTimer?: number;
  // GP 按钮是否已贴边隐藏（无操作一段时间后自动隐藏，单击唤出）
  @State gpButtonHidden: boolean = false;

  // ===== 网页弹框（alert / confirm / prompt）=====
  // ArkWeb 不提供默认弹框（官方文档："当前，ArkWeb 暂未提供默认的应用弹框"），
  // 且文档明确：不调用 JsResult 的 handleConfirm/handleCancel/handlePromptConfirm 会造成 render 进程阻塞。
  // 所以壳层必须接管这三种弹框——GP-Next 的"导出/另存为"正是靠 prompt 拿文件名的。
  @State jsDialogVisible: boolean = false;
  @State jsDialogKind: string = 'alert';   // alert | confirm | prompt
  @State jsDialogMessage: string = '';
  @State jsDialogInput: string = '';
  private jsDialogReply: ((ok: boolean, text: string) => void) | null = null;
  private jsDialogTimer?: number;

  async aboutToAppear() {
    // 打开 Web 调试（官方建议在 aboutToAppear 中设置）
    try {
      webview.WebviewController.setWebDebuggingAccess(ENABLE_WEB_DEBUG);
      console.info(`Web 调试: ${ENABLE_WEB_DEBUG ? '已开启' : '已关闭'}`);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`设置 Web 调试失败: code=${error.code}, message=${error.message}`);
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      console.error('获取 Context 失败');
      return;
    }
    this.filePickerHelper = new FilePickerHelper(context);

    // 读入 touchPatch.js，与 GPNEXT_SHIM 拼成一条注入脚本（原因见 injectedScript 的注释）。
    // 这样负载更新时不会再冲掉对 touchPatch.js 的引用 —— 原先它靠 index.html 里的一行 <script src>。
    try {
      const bytes = context.resourceManager.getRawFileContentSync(TOUCH_PATCH_RAWFILE);
      const touchPatch = util.TextDecoder.create('utf-8').decodeToString(bytes);
      if (touchPatch.length > 0) {
        this.injectedScript = GPNEXT_SHIM + '\n;\n' + touchPatch;
        console.info(`注入脚本就绪: shim ${GPNEXT_SHIM.length} B + touchPatch ${touchPatch.length} B`);
      } else {
        console.error('touchPatch.js 内容为空，仅注入 shim');
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`读取 ${TOUCH_PATCH_RAWFILE} 失败: code=${error.code}, message=${error.message}`);
    }

    // 负载自检：新布局下「更新负载 = 替换 game/ 目录」，但拦截器对**不存在的文件**返回的是
    // 200 + 空体（不是 404，见 docs/BUILD.md），所以换错/换漏目录会表现为静默黑屏。
    // 这里在启动时把两个关键文件读一遍，缺失就直接报出来。
    const missing: string[] = [];
    for (const rel of [PAYLOAD_DIR + 'index.html', PAYLOAD_DIR + 'src/settings.json']) {
      try {
        const bytes = context.resourceManager.getRawFileContentSync(rel);
        if (!bytes || bytes.byteLength === 0) {
          missing.push(rel);
        }
      } catch (err) {
        missing.push(rel);
      }
    }
    if (missing.length > 0) {
      console.error(`负载文件缺失: ${missing.join(', ')} —— 请确认 ${PAYLOAD_DIR} 目录已完整替换`);
      this.showStatusMessage(`负载缺失: ${missing.join('、')}`, 8000);
    } else {
      console.info(`负载自检通过: ${PAYLOAD_DIR}`);
    }

    // 原生桥需要宿主提供三件事：打开外链、另存为、导入数据包
    // （ArkTS 不允许用对象字面量实现带方法的接口，故直接传函数）
    this.gpNextBridge = new GpNextBridge(context,
      (url: string) => {
        this.openExternal(url);
      },
      (fileName: string) => this.pickSaveTarget(fileName),
      () => this.importPackages());

    // 初始化 ResourceManager（LRU 缓存，80MB/300项上限）
    ResourceManager.getInstance().setContext(context);
    console.info('ResourceManager 已初始化');

    // 初始化 Preferences
    try {
      // M3：两种重载都有效 —— 官方文档把 Options 形式标为「10+」（API 10 新增能力），
      // 并没有废弃 getPreferences(context, name: string)。这里用 Options 形式只是因为键名显式、不易写错。
      this.prefs = await preferences.getPreferences(context, { name: 'game_save' });
      this.preferenceStore.attach(this.prefs);   // 交给落盘层（Web 侧白名单键的持久化）
      this.shellPrefs.attach(this.prefs);        // 交给壳层偏好（铺满 / 期望刷新率 / 提示标记）
      // 恢复"铺满画面"偏好
      this.isFillScreen = await this.shellPrefs.loadFillScreen();
      // 恢复"期望刷新率"偏好（面板里可改）
      this.expectedRefresh = await this.shellPrefs.loadExpectedRefresh();
      // 首次启动提示一次：设置面板在长按 GP 按钮里（发现性）
      const hintSeen = await this.shellPrefs.loadHintSeen();
      if (!hintSeen) {
        this.showStatusMessage('提示：长按右下角 GP 按钮可打开设置', 5000);
        await this.shellPrefs.markHintSeen();
      }
      // aboutToAppear 是异步的，首次布局触发的 onAreaChange 很可能先于这里完成，
      // 故读完偏好必须重算一次，否则保存过的"铺满"在启动时会被静默忽略。
      this.applyAspectRatio();
    } catch (err) {
      const error = err as BusinessError;
      console.error(`初始化 Preferences 失败: code=${error.code}, message=${error.message}`);
    }

    // 启动后开始计时：无操作一段时间后把 GP 按钮贴边隐藏
    this.scheduleGpHide();

    // 期望帧率投票（页面可见期间持有；页面不可见时在 onPageHide 里停掉）
    this.startHighRefreshVote();
  }

  /** 把算好的比例结果写进布局状态（纯计算见 common/AspectRatio.ets 的 computeAspectLayout） */
  private applyAspectRatio(): void {
    // 尚未测量到容器尺寸，或处于铺满模式：交给 100% 尺寸
    if (this.containerW <= 0 || this.containerH <= 0 || this.isFillScreen) {
      this.webW = '100%';
      this.webH = '100%';
      this.webX = 0;
      this.webY = 0;
      return;
    }
    const layout = computeAspectLayout(this.containerW, this.containerH);
    this.webW = layout.width;
    this.webH = layout.height;
    this.webX = layout.x;
    this.webY = layout.y;
  }

  /**
   * 向系统"投票"期望帧率（可变帧率机制）。
   * 只在页面可见期间持有；回调里不做任何工作 —— 它的唯一作用是让控帧系统知道
   * "这个页面期望高帧率"，从而在无触摸时也尽量维持高刷新率。
   */
  private startHighRefreshVote(): void {
    this.stopHighRefreshVote();
    if (!ENABLE_HIGH_REFRESH_VOTE || this.expectedRefresh === 'off') {
      return;
    }
    // 期望帧率：max = 屏幕可用上限；否则取面板选择的数值
    let expected = HIGH_REFRESH_EXPECTED;
    if (this.expectedRefresh === 'max') {
      if (this.supportedRefresh.length === 0) {
        this.refreshDisplayInfo();
      }
      let top = 0;
      for (let i = 0; i < this.supportedRefresh.length; i++) {
        if (this.supportedRefresh[i] > top) {
          top = this.supportedRefresh[i];
        }
      }
      if (top > 0) {
        expected = top;
      }
    } else {
      expected = Number(this.expectedRefresh);
      if (!Number.isFinite(expected) || expected <= 0) {
        expected = HIGH_REFRESH_EXPECTED;
      }
    }
    // 声明范围保持 [60, expected]（不是单值）：单值写法在手机上一样无效，而平板的有效性是在
    // 这个宽松范围下验证过的 —— 具体实现与说明见 services/RefreshVote.ets 与 docs/MODULES.md。
    this.refreshVote.start(expected, HIGH_REFRESH_MIN);
  }

  /** 停止投票并释放实例（页面不可见 / 退出时调用） */
  private stopHighRefreshVote(): void {
    this.refreshVote.stop();
  }

  /** 读取当前/可用屏幕刷新率（只读，仅用于面板显示） */
  private refreshDisplayInfo(): void {
    try {
      const info = readDisplayInfo();
      this.currentRefresh = info.refreshRate;
      const next: number[] = info.supported;
      // 仅在真正变化时写状态，避免每秒一次无谓重渲染
      let same = next.length === this.supportedRefresh.length;
      if (same) {
        for (let i = 0; i < next.length; i++) {
          if (next[i] !== this.supportedRefresh[i]) {
            same = false;
            break;
          }
        }
      }
      if (!same) {
        this.supportedRefresh = next;
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`读取屏幕刷新率失败: code=${error.code}, message=${error.message}`);
    }
  }

  /** 长按 GP 按钮：打开壳层设置面板（画面模式 + 期望刷新率） */
  private openShellSettings(): void {
    this.refreshDisplayInfo();
    this.readEngineFrameRate();   // 只读展示：GP-Next 的「帧率」设置
    this.measureEngineFps();      // 实测一次（约 1 秒后出结果）
    this.shellSettingsOpen = true;
    if (this.refreshPollTimer === undefined) {
      this.refreshPollTimer = setInterval(() => {
        this.refreshDisplayInfo();
      }, 1000);
    }
  }

  /** 关闭设置面板并停掉刷新率轮询 */
  private closeShellSettings(): void {
    this.shellSettingsOpen = false;
    if (this.refreshPollTimer !== undefined) {
      clearInterval(this.refreshPollTimer);
      this.refreshPollTimer = undefined;
    }
  }

  /** 面板里切换期望刷新率：立即生效 + 持久化 */
  private setExpectedRefresh(value: string): void {
    this.expectedRefresh = value;
    this.startHighRefreshVote();
    const label = value === 'off' ? '关闭' : (value === 'max' ? '最高' : value + 'Hz');
    this.showStatusMessage(`期望刷新率：${label}`, 2000);
    this.persistExpectedRefresh();
  }

  private async persistExpectedRefresh(): Promise<void> {
    await this.shellPrefs.saveExpectedRefresh(this.expectedRefresh);
  }

  /** 面板用：期望刷新率的可读文案 */
  private expectedRefreshLabel(): string {
    if (this.expectedRefresh === 'off') {
      return '已关闭';
    }
    if (this.expectedRefresh === 'max') {
      return '最高';
    }
    return this.expectedRefresh + ' Hz';
  }

  /** 面板用：判断投票看起来是否已生效（只做展示，不参与逻辑） */
  private voteStatusText(): string {
    if (this.expectedRefresh === 'off') {
      return '未声明，由系统自行决定';
    }
    let top = 0;
    for (let i = 0; i < this.supportedRefresh.length; i++) {
      if (this.supportedRefresh[i] > top) {
        top = this.supportedRefresh[i];
      }
    }
    let want = 0;
    if (this.expectedRefresh === 'max') {
      want = top;
    } else {
      want = Number(this.expectedRefresh);
    }
    if (want > 0 && this.currentRefresh >= want) {
      return '生效中 ✓';
    }
    if (top > 0 && top <= 60) {
      return '本机屏幕只有 60 Hz';
    }
    // 高刷已经上去了、只是没到期望值（例如期望「最高」=144 而屏幕上到 120）——
    // 这种情况说明声明是生效的，只是被系统按能力/策略封顶，不能说成"未接受"。
    if (this.currentRefresh > 60) {
      return '部分生效（当前 ' + this.currentRefresh + ' < 期望 ' + want + '）';
    }
    // 仍停在 60：实测（手机 BRA-AL00）声明 120 与关闭都稳在 60 —— 系统不接受该声明。
    // 可操作建议：把「系统设置 → 显示和亮度 → 屏幕刷新率」从"智能"改为"高"。
    return '系统未接受该声明（可把系统刷新率设为"高"再试）';
  }

  /** 读页面里 GP-Next 的「帧率」设置（只读展示；设置入口在 GP-Next 面板 → 实验性） */
  // ==================== 设置面板的动作（实现见 services/PanelActions.ets）====================
  // 本页只负责：把结果写进 @State、以及决定要不要弹提示。
  // 与页面 / 引擎打交道的内嵌 JS 全部在服务里（那里也写清了“壳层面板”与“GP-Next 设置”的区别）。

  /** 读取「帧率上限」与「实验帧率调度」状态（打开面板时、点「↻」时调用） */
  private async readEngineFrameRate(): Promise<void> {
    try {
      const readout = await PanelActions.readEngineReadout(
        (script: string) => this.webController.runJavaScript(script));
      this.engineFrameRate = readout.frameRateLabel;
      this.frameSchedulerOn = readout.schedulerOn;
      this.schedulerFrameRate = readout.schedulerFrameRateLabel;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`读取 GP-Next 帧率失败: code=${error.code}, message=${error.message}`);
      this.engineFrameRate = '未知';
    }
  }

  /**
   * 关闭 GP-Next 的「实验帧率调度」：写回设置并重新加载页面（会让游戏重新进入）。
   * 该调度器是纯 JS 节拍器（MessageChannel + setTimeout），在平板上会造成明显卡顿。
   */
  private async disableExperimentalScheduler(): Promise<void> {
    try {
      const ok = await PanelActions.disableScheduler(
        (script: string) => this.webController.runJavaScript(script));
      if (ok) {
        this.frameSchedulerOn = false;
        this.showStatusMessage('已关闭「实验帧率调度」，正在重新加载页面…', 4000);
        setTimeout(() => { this.webController.refresh(); }, 600);
      } else {
        this.showStatusMessage('关闭失败，请到 GP-Next 面板 → 实验性 里手动关闭', 4000);
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`关闭实验帧率调度失败: code=${error.code}, message=${error.message}`);
      this.showStatusMessage('关闭失败，请到 GP-Next 面板 → 实验性 里手动关闭', 4000);
    }
  }

  /** 页面加载完成后检查一次：开着实验帧率调度就提示一次 */
  private async warnIfExperimentalSchedulerOn(): Promise<void> {
    try {
      const on = await PanelActions.isSchedulerOn(
        (script: string) => this.webController.runJavaScript(script));
      this.frameSchedulerOn = on;
      if (on && !this.schedulerWarned) {
        this.schedulerWarned = true;
        this.showStatusMessage('提示：GP-Next「实验帧率调度」已开启，平板上可能明显卡顿；长按 GP 按钮可在设置里一键关闭', 6000);
      }
    } catch (err) {
      // 读不到就静默：这只是提示，不影响功能
    }
  }

  /**
   * 把引擎帧率上限设为「不限」：直接调用 GP-Next 暴露的 mod API（window.gpNext.setFrameRate）。
   * 这是安全的老路径（不涉及「实验帧率调度」那个纯 JS 节拍器），用于游戏内「无限制」不生效时兜底。
   */
  private async forceUnlimitedFrameRate(): Promise<void> {
    try {
      const ok = await PanelActions.forceUnlimited(
        (script: string) => this.webController.runJavaScript(script));
      if (ok) {
        this.showStatusMessage('已把引擎上限与存档都设为「不限」（看下面"实测"确认）', 4500);
      } else {
        this.showStatusMessage('此负载未暴露 setFrameRate，请用游戏内扳手页面设置', 4000);
      }
      this.readEngineFrameRate();
      this.measureEngineFps();
    } catch (err) {
      const error = err as BusinessError;
      console.error(`设置不限帧率失败: code=${error.code}, message=${error.message}`);
      this.showStatusMessage('设置失败', 3000);
    }
  }

  /** 实测引擎帧率：间隔约 1 秒采样两次 cc.director.getTotalFrames()（设置 ≠ 实际时能看出来） */
  private async measureEngineFps(): Promise<void> {
    try {
      this.engineFpsMeasured = await PanelActions.measureFps(
        (script: string) => this.webController.runJavaScript(script));
    } catch (err) {
      this.engineFpsMeasured = '不可用';
    }
  }

  /** 打开 GP-Next 面板（与 GP 按钮单击走同一条路径：window.gpNext.toggle → F9 兜底） */
  private async openGpNextPanel(): Promise<void> {
    try {
      await PanelActions.openGpNextPanel(
        (script: string) => this.webController.runJavaScript(script));
    } catch (err) {
      const error = err as BusinessError;
      console.error(`打开 GP-Next 面板失败: code=${error.code}, message=${error.message}`);
    }
  }
  /** 壳层设置面板（长按 GP 按钮打开） */
  /** 切换 铺满 / 按比例留边，并持久化（面板里触发） */
  /** 切换 铺满 / 按比例留边，并持久化（长按 GP-Next 按钮触发） */
  private async toggleFillScreen(): Promise<void> {
    this.isFillScreen = !this.isFillScreen;
    this.applyAspectRatio();
    this.showStatusMessage(this.isFillScreen ? '画面：铺满' : '画面：3:2 ~ 17:9 留边', 2000);

    await this.shellPrefs.saveFillScreen(this.isFillScreen);
  }

  /** 让 GP 按钮在无操作一段时间后自动贴边隐藏；任何与它的交互都会重新计时 */
  private scheduleGpHide(): void {
    if (this.hideButtonTimer !== undefined) {
      clearTimeout(this.hideButtonTimer);
    }
    this.hideButtonTimer = setTimeout(() => {
      this.hideButtonTimer = undefined;
      this.setGpButtonHidden(true);
    }, GP_BUTTON_HIDE_DELAY);
  }

  /** 显示 / 贴边隐藏 GP 按钮（带过渡动画）；唤出后重新计时 */
  private setGpButtonHidden(hidden: boolean): void {
    if (this.gpButtonHidden === hidden) {
      return;
    }
    this.getUIContext()?.animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.gpButtonHidden = hidden;
    });
    if (!hidden) {
      this.scheduleGpHide();
    }
  }


  /** 弹出网页对话框；同一时刻只允许一个，避免未决的 JsResult 卡住 render 进程 */
  private showJsDialog(kind: string, message: string, defaultValue: string,
    reply: (ok: boolean, text: string) => void): void {
    if (this.jsDialogReply !== null) {
      this.finishJsDialog(false);
    }
    this.jsDialogKind = kind;
    this.jsDialogMessage = message;
    this.jsDialogInput = defaultValue;
    this.jsDialogReply = reply;
    this.jsDialogVisible = true;
    // 兜底：即使界面异常（例如触摸被别的浮层吃掉）导致用户点不到按钮，也必须让 JsResult 最终被回调，
    // 否则网页侧 prompt()/confirm() 永不返回，render 进程会一直阻塞，整个面板失去响应。
    if (this.jsDialogTimer !== undefined) {
      clearTimeout(this.jsDialogTimer);
    }
    this.jsDialogTimer = setTimeout(() => {
      this.jsDialogTimer = undefined;
      if (this.jsDialogVisible) {
        console.error(`网页弹框超时未响应，自动取消: ${this.jsDialogMessage}`);
        this.finishJsDialog(false);
      }
    }, JS_DIALOG_TIMEOUT);
  }

  /** 结束网页对话框并把结果回给 Web 内核（必须回调，否则 render 进程阻塞） */
  private finishJsDialog(ok: boolean): void {
    if (this.jsDialogTimer !== undefined) {
      clearTimeout(this.jsDialogTimer);
      this.jsDialogTimer = undefined;
    }
    const reply = this.jsDialogReply;
    this.jsDialogReply = null;
    this.jsDialogVisible = false;
    if (reply !== null) {
      try {
        reply(ok, this.jsDialogInput);
      } catch (err) {
        // JsResult 回调本身失败不应再抛出去，否则界面会卡在这个状态
        console.error('回调网页弹框结果失败:', err);
      }
    }
  }

  /** 外部链接交给系统浏览器；startAbility 失败时退回 App Linking（openLink） */
  private openExternal(url: string): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      console.error(`打开外链失败：Context 无效 ${url}`);
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url,
      parameters: { 'ohos.ability.params.showDefaultPicker': true }
    };
    context.startAbility(want)
      .then(() => {
        console.info(`已交由系统浏览器打开: ${url}`);
      })
      .catch((err: BusinessError) => {
        console.error(`startAbility 打开外链失败: code=${err.code}, message=${err.message}，改用 openLink`);
        context.openLink(url).catch((linkErr: BusinessError) => {
          console.error(`openLink 亦失败: code=${linkErr.code}, message=${linkErr.message}`);
        });
      });
  }

  /** 注册 GP-Next 原生桥：注入脚本通过 window.__gpNextNative.invoke 调用它 */
  private registerGpNextBridge(): void {
    if (!this.gpNextBridge) {
      console.error('GP-Next 原生桥未初始化，跳过注册');
      return;
    }
    try {
      this.webController.registerJavaScriptProxy(this.gpNextBridge, '__gpNextNative', ['invoke']);
      console.info('GP-Next 原生桥已注册: __gpNextNative.invoke');
    } catch (err) {
      console.error('注册 GP-Next 原生桥失败', err);
    }
  }

  /** 网页发起"另存为"：弹系统保存对话框，返回用户选定的 uri（取消返回 null） */
  /**
   * 选保存位置（宽容版，供导出流程用）：失败时把**真实原因**提示给用户，再返回 null。
   * 注意：selectSavePath 只在"用户取消"时返回 null，失败会抛错 —— 这里必须提示，不能再让它看起来像取消。
   */
  private async pickSaveTarget(fileName: string): Promise<string | null> {
    if (!this.filePickerHelper) {
      return null;
    }
    try {
      return await this.filePickerHelper.selectSavePath(fileName);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`选择保存位置失败: ${error.message}`);
      this.showStatusMessage(error.message, 4000);
      return null;
    }
  }

  /** 选保存位置（严格版，供下载流程用）：失败时抛出，让下载侧能区分"用户取消"和"选择失败" */
  private async pickSaveTargetStrict(fileName: string): Promise<string | null> {
    if (!this.filePickerHelper) {
      throw new Error('文件选择器尚未初始化');
    }
    return await this.filePickerHelper.selectSavePath(fileName);
  }

  /** 网页点"打开数据包目录"：移动端没有能让用户丢文件的目录，改成从系统选择器导入 */
  private async importPackages(): Promise<void> {
    if (!this.filePickerHelper || !this.gpNextBridge) {
      return;
    }
    const uris = await this.filePickerHelper.selectPackFiles();
    if (uris.length === 0) {
      this.showStatusMessage('已取消导入', 2000);
      return;
    }
    this.showStatusMessage('正在导入数据包…', 60000);
    const summary = await this.gpNextBridge.importPackages(uris);
    this.showStatusMessage(summary, 6000);
    // 导入的是磁盘上的包，需要让面板重新扫描。注意 gpNext 的公开 API 里并没有 reload，
    // 所以直接点补丁页的"重新加载所有补丁"按钮（导入入口就在该页，按钮必定已在 DOM 中）。
    try {
      await this.webController.runJavaScript(`(function(){
        var hits = Array.prototype.slice.call(document.querySelectorAll('button')).filter(function (b) {
          return /重新加载所有补丁|Reload All Patches/i.test(b.innerText || '');
        });
        if (hits.length > 0) { hits[0].click(); return; }
        var g = window.gpNext;
        if (g && typeof g.reload === 'function') { g.reload(); }
      })();`);
    } catch (err) {
      console.error('通知 GP-Next 重载失败', err);
    }
  }

  // 在 onControllerAttached 中注册代理
  private registerNativeStorage() {
    try {
      this.webController.registerJavaScriptProxy(
        this,
        'NativeStorage',
        ['saveToNative', 'loadFromNative']
      );
      // ⚠️ 这里**不要**再调 refresh()。
      // 官方开发指南《前端页面调用应用侧函数》写得很明确：
      //   · 在 onControllerAttached（页面加载**前**）注册 ⇒ 官方原话「在页面加载前注册，页面加载完成后生效」，无需 refresh；
      //   · 只有在 onPageEnd（页面加载**后**）注册，才需要 refresh 重新加载才生效。
      // 而本页面的两个代理都在 onControllerAttached 里注册，原来那句 refresh() 只会白白多加载一遍整页。
    } catch (err) {
      console.error('注册 NativeStorage 失败', err);
    }
  }

  /** 页面重新可见：恢复期望帧率投票 */
  onPageShow() {
    this.startHighRefreshVote();
  }

  /** 页面不可见（切后台 / 跳转）：停止投票，避免空刷帧与额外功耗 */
  onPageHide() {
    this.stopHighRefreshVote();
    this.closeShellSettings();   // 顺带关掉设置面板并清理轮询定时器
    this.preferenceStore.flushNow();   // 页面不可见：把去抖中的存档立刻落盘
  }

  aboutToDisappear() {
    // 页面销毁：停掉期望帧率投票 + 关掉设置面板（清理轮询定时器）
    this.stopHighRefreshVote();
    this.closeShellSettings();
    this.preferenceStore.flushNow();   // 页面销毁前把去抖中的存档落盘
    if (this.timeoutId) clearTimeout(this.timeoutId);
    if (this.hideButtonTimer !== undefined) {
      clearTimeout(this.hideButtonTimer);
      this.hideButtonTimer = undefined;
    }

    // 资源缓存统计
    const cacheStats = ResourceManager.getInstance().getCacheStats();
    console.info(`ResourceManager: ${cacheStats.totalItems}项, ` +
      `${(cacheStats.totalSize / 1024 / 1024).toFixed(2)}MB / ${(cacheStats.maxSize / 1024 / 1024).toFixed(0)}MB, ` +
      `命中率: ${cacheStats.hitRate}%`);

  }

  // ==================== NativeStorage 代理方法（实现见 services/PreferenceStore.ets）====================
  // ⚠️ 这两个方法**必须留在页面上**、名字与签名不能变：
  //    页面是用 registerJavaScriptProxy(this, 'NativeStorage', [...]) 把自己注册成代理的，
  //    换成别的对象会改变代理调用里的 this 绑定（第 4 步拆分就踩过这个坑，已回退）。
  //    这里只做一行转发，落盘策略（put 立即 + flush 去抖）在 PreferenceStore 里。

  /** Web 侧 localStorage.setItem（白名单键）→ Preferences */
  public async saveToNative(key: string, value: string): Promise<void> {
    return this.preferenceStore.save(key, value);
  }

  /** Web 侧 localStorage.getItem ← Preferences */
  public async loadFromNative(key: string): Promise<string> {
    return this.preferenceStore.load(key);
  }



  private showStatusMessage(message: string, duration: number = 3000) {
    if (this.timeoutId) clearTimeout(this.timeoutId);
    // 关键：上一条提示的"淡出后清空"定时器也要取消，否则它会在新提示刚出现时把文案清掉
    if (this.fadeOutTimer !== undefined) {
      clearTimeout(this.fadeOutTimer);
      this.fadeOutTimer = undefined;
    }
    this.statusOpacity = 1;
    this.downloadStatus = message;
    this.timeoutId = setTimeout(() => {
      this.getUIContext()?.animateTo({ duration: 300 }, () => { this.statusOpacity = 0; });
      this.fadeOutTimer = setTimeout(() => {
        this.downloadStatus = '';
        this.statusOpacity = 1;
        this.fadeOutTimer = undefined;
      }, 300);
      this.timeoutId = undefined;
    }, duration);
  }

  build() {
    // 根容器用 Stack：Web 铺满整屏，状态提示与 GP-Next 入口按钮分别叠加到顶部和右下角。
    // 叠加层只占用自身命中区域（状态栏另外放行触摸），不会遮挡游戏其余区域的操作。
    Stack({ alignContent: Alignment.BottomEnd }) {
      Web({ src: "https://cocos.local/game/index.html",
        controller: this.webController,
        renderMode: RenderMode.ASYNC_RENDER // 不阻塞ArkUI主线程
      })
        .width(this.webW)
        .height(this.webH)
        .position({ x: this.webX, y: this.webY })   // 比例留边时居中，四周黑边由根 Stack 提供
        .backgroundColor(Color.Black)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .mediaPlayGestureAccess(false)
        .enableWebAVSession(false)
        // @SuppressWarnings syscap
        .overviewModeAccess(false)       // 禁用概览模式（减少手势处理开销）
        .zoomAccess(false)               // 禁用缩放（游戏不需要）
        .verticalScrollBarAccess(false)
        // 网页里 window.open / target=_blank 需要开启多窗口，且必须实现 onWindowNew（否则 render 进程阻塞）。
        // 我们不创建新窗口：外部 http(s) 链接交给系统浏览器，其余一律置 null 通知内核。
        .multiWindowAccess(true)
        .onWindowNew((event) => {
          const target: string = event.targetUrl;
          const isExternal: boolean = (target.startsWith('http://') || target.startsWith('https://'))
            && !target.startsWith('https://cocos.local/');
          if (isExternal) {
            this.openExternal(target);
          }
          event.handler.setWebController(null);
        })
        // ArkWeb 无默认弹框：alert / confirm / prompt 全部由壳层自绘并回调 JsResult。
        // 否则网页侧 confirm() 恒为 false、prompt() 恒为 null，且不回调会阻塞 render 进程。
        .onAlert((event) => {
          this.showJsDialog('alert', event.message, '', (ok: boolean) => {
            if (ok) {
              event.result.handleConfirm();
            } else {
              event.result.handleCancel();
            }
          });
          return true;
        })
        .onConfirm((event) => {
          this.showJsDialog('confirm', event.message, '', (ok: boolean) => {
            if (ok) {
              event.result.handleConfirm();
            } else {
              event.result.handleCancel();
            }
          });
          return true;
        })
        .onPrompt((event) => {
          this.showJsDialog('prompt', event.message, event.value, (ok: boolean, text: string) => {
            if (ok) {
              event.result.handlePromptConfirm(text);
            } else {
              event.result.handleCancel();
            }
          });
          return true;
        })
        // 控制台只转发 warn/error，并 return true 抑制 ArkWeb 的默认日志：官方《Web帧率问题分析》
        // 把「大量 JSB 任务阻塞应用主线程」列为丢帧典型根因，而逐条 console 回传正是这种逐帧 JSB；
        // 游戏的 info 级日志在运行期没有价值，丢弃可显著减少跨进程调用。
        .onConsole((event) => {
          const message = event.message;
          const level = message.getMessageLevel();
          if (level === MessageLevel.Warn || level === MessageLevel.Error) {
            console.info(`[web-console][${level}] ${message.getMessage()}` +
              ` (${message.getSourceId()}:${message.getLineNumber()})`);
          }
          return true;
        })
        // 在页面自身脚本之前注入：GPNEXT_SHIM（Tauri 兼容层）+ touchPatch.js（触摸/性能补丁 + localStorage 白名单桥）。
        // 注：0.14.0 负载的 index.html 自带一个残缺 polyfill（只在 __TAURI_INTERNALS__ 缺失时才装），
        // 0.15.0 负载已无该 polyfill；存档落盘这条链路完全由 touchPatch.js 的白名单负责（见 docs/MODULES.md）。
        .javaScriptOnDocumentStart([{ script: this.injectedScript, scriptRules: ['*'] }])
        .onControllerAttached(() => {
          // 这里注册即可：onControllerAttached 在页面加载前触发，注册后随本次加载生效（官方指南），
          // 因此两个注册方法内部都不需要再调 refresh()。
          this.registerNativeStorage();  // 注册 localStorage 持久化代理
          this.registerGpNextBridge();   // 注册 GP-Next 原生桥（__gpNextNative.invoke）
        })
        .onPageBegin(() => {
          this.isLoading = true;
          this.webReady = false;
        })
        .onProgressChange((event) => { this.progress = event.newProgress; })
        .onPageEnd(() => {
          this.isLoading = false;
          this.warnIfExperimentalSchedulerOn();   // 实验帧率调度开着时提示一次（平板会卡）
          this.webReady = true;
          // 注册下载委托
          // 下载委托：服务负责回调与落盘，这里只把委托交给控制器
          try {
            this.webController.setDownloadDelegate(this.setupDownloadDelegate());
            console.log('下载委托已注册');
          } catch (err) {
            console.error('注册下载委托失败:', err);
          }
          // Cookie 持久化（可选）
          try {
            webview.WebCookieManager.saveCookieAsync(() => console.log('Cookie 已保存'));
          } catch (err) { console.error('保存 Cookie 失败', err); }
        })
        .onInterceptRequest((event) => {
          if (!event) return null;
          // 负载请求一律交给 PayloadServer：前缀规则、LRU 缓存、MIME 都在那里；
          // rawfile 的读取函数由这里传入（$rawfile 是 UI 全局），数据来源与改动前一致。
          return PayloadServer.serve(event.request.getRequestUrl(), (path: string) => $rawfile(path));
        })
        .onLoadIntercept((event) => {
          if (!event) return false;
          const url = event.data.getRequestUrl();

          // 1. 特殊协议一律放行（data:/blob:/javascript:/about:/chrome:/arkweb:）
          if (!url.startsWith("http://") && !url.startsWith("https://")) {
            return false;
          }

          // 2. 仅拦截主框架导航，子资源请求（图片/脚本/XHR）放行
          if (!event.data.isMainFrame()) {
            return false;
          }

          // 3. 游戏内部资源放行
          if (url.startsWith("https://cocos.local/")) {
            return false;
          }

          // 4. 外部链接 → 跳转系统浏览器（viewData + browsable；openLink 依赖域名校验，仅作兜底）
          this.openExternal(url);
          return true;
        })
      // 状态提示 + 加载进度条（叠加在画面顶部，放行触摸；组件见 components/StatusToast.ets）
      StatusToast({
        message: this.downloadStatus,
        statusOpacity: this.statusOpacity,
        loading: this.isLoading,
        progress: this.progress
      })

      // 网页弹框层（alert / confirm / prompt）：ArkWeb 无默认弹框，这里自绘一个模态卡片
      if (this.jsDialogVisible) {
        Column() {
          Column({ space: 12 }) {
            Text(this.jsDialogMessage)
              .fontSize(15)
              .fontColor(Color.White)
              .width('100%')
              .maxLines(6)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.jsDialogKind === 'prompt') {
              TextInput({ text: this.jsDialogInput })
                .fontSize(14)
                .width('100%')
                .defaultFocus(true)
                .onChange((value: string) => {
                  this.jsDialogInput = value;
                })
            }
            Row({ space: 10 }) {
              if (this.jsDialogKind !== 'alert') {
                Button('取消')
                  .layoutWeight(1)
                  .fontSize(14)
                  .backgroundColor('#33FFFFFF')
                  .fontColor(Color.White)
                  .onClick(() => {
                    this.finishJsDialog(false);
                  })
              }
              Button(this.jsDialogKind === 'prompt' ? '保存' : '确定')
                .layoutWeight(1)
                .fontSize(14)
                .backgroundColor('#0A59F7')
                .fontColor(Color.White)
                .onClick(() => {
                  this.finishJsDialog(true);
                })
            }
            .width('100%')
          }
          .width('78%')
          .padding(16)
          .backgroundColor('#F01C1C1C')
          .borderRadius(12)
          .borderWidth(1)
          .borderColor('#40FFFFFF')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#66000000')
        // 必须用 Default：自身命中即阻塞兄弟节点（挡住下面的 Web 与 GP 按钮），但不阻塞子组件。
        // 若用 HitTestMode.Block，官方语义是"阻塞子组件的触摸测试"——按钮会点不动，
        // JsResult 永不回调，网页侧 prompt() 卡住不返回，render 进程阻塞，整个面板失去响应。
        .hitTestBehavior(HitTestMode.Default)
        .zIndex(10)
      }

      // GP-Next 面板入口（组件只管外观与手势；唤醒 / 重新计时 / 打开哪个面板由本页决定）
      GpFloatingButton({
        hidden: this.gpButtonHidden,
        onShortPress: () => {
          if (this.gpButtonHidden) {   // 已隐藏时单击先唤出
            this.setGpButtonHidden(false);
            return;
          }
          this.scheduleGpHide();       // 可见态：执行动作并重新计时
          this.openGpNextPanel();      // 打开 GP-Next 面板（实现见 services/PanelActions.ets）
        },
        onLongPress: () => {
          if (this.gpButtonHidden) {   // 已隐藏时长按先唤出，避免误触切换
            this.setGpButtonHidden(false);
            return;
          }
          this.scheduleGpHide();
          this.openShellSettings();    // 长按 = 壳层设置面板（画面模式 / 期望刷新率）
        }
      })      // 壳层设置面板（长按 GP 按钮打开）；放最后 = 图层最上，可拦截触摸
      if (this.shellSettingsOpen) {
        SettingsPanel({
          isFillScreen: this.isFillScreen,
          expectedRefresh: this.expectedRefresh,
          statusLine: `当前 ${this.currentRefresh} Hz ｜ 期望 ${this.expectedRefreshLabel()} ｜ ${this.voteStatusText()}`,
          supportedText: '屏幕档位：' + (this.supportedRefresh.length > 0 ? this.supportedRefresh.join(' / ') + ' Hz' : '读取中…'),
          engineFrameRate: this.engineFrameRate,
          engineFpsMeasured: this.engineFpsMeasured,
          schedulerFrameRate: this.schedulerFrameRate,
          frameSchedulerOn: this.frameSchedulerOn,
          onClose: () => { this.closeShellSettings(); },
          onToggleFill: () => { this.toggleFillScreen(); },
          onPickRefresh: (value: string) => { this.setExpectedRefresh(value); },
          onRefreshEngine: () => { this.readEngineFrameRate(); this.measureEngineFps(); },
          onForceUnlimited: () => { this.forceUnlimitedFrameRate(); },
          onOpenGpNext: () => { this.openGpNextPanel(); },
          onDisableScheduler: () => { this.disableExperimentalScheduler(); }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)   // 比例留边时四周的黑边
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      // 用实际容器尺寸而非 display 尺寸：小窗 / 分屏 / 2in1 窗口模式下同样正确。
      // width/height 静态类型是 Length，可能是带单位字符串，故统一走 parseVp 兜底。
      const w = parseVp(newArea.width);
      const h = parseVp(newArea.height);
      if (w !== this.containerW || h !== this.containerH) {
        this.containerW = w;
        this.containerH = h;
        this.applyAspectRatio();
      }
    })
  }

  /**
   * 安装下载委托：把"顶部状态 / 提示 / 选保存位置 / 取 Context"四个回调交给服务，
   * 返回底层委托由调用方交给 `webController.setDownloadDelegate`。
   * 回调里保留了两处原本属于页面状态的判断（是否采纳进度、取消时的文案）。
   */
  private setupDownloadDelegate(): webview.WebDownloadDelegate {
    return this.downloadSaver.install({
      updateProgress: (percent: number) => {
        // 仅当当前文案是"下载中"才刷新百分比，避免覆盖刚弹出的其它提示
        if (this.downloadStatus.startsWith('下载中')) {
          this.downloadStatus = `下载中: ${percent}%`;
        }
      },
      notify: (message: string, duration: number) => {
        this.showStatusMessage(message, duration);
      },
      pickSavePath: (fileName: string) => {
        // 用严格版：失败会抛错，DownloadSaver 就不会把"权限被拒"误报成"已取消下载"
        return this.pickSaveTargetStrict(fileName);
      },
      getContext: () => {
        return this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      }
    });
  }
}
