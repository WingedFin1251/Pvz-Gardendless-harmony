import { webview } from '@kit.ArkWeb';
import { common, Want } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { FilePickerHelper } from './FilePickerHelper';  // 复用 FilePickerHelper
import preferences from '@ohos.data.preferences';
import { BusinessError } from '@kit.BasicServicesKit'; // 确保已导入
import { ResourceManager } from '../utils/ResourceManager';
import { GpNextBridge } from '../utils/GpNextBridge';
import { GPNEXT_SHIM } from '../utils/GpNextShim';

// GP-Next 入口按钮（单位 vp）：改这两个值即可调整按钮大小与距右下角的留白
const GP_BUTTON_SIZE: number = 44;
const GP_BUTTON_MARGIN: number = 12;
// 无操作后自动贴边隐藏：延迟（ms）；隐藏后仍留在屏幕内、可见且可点的宽度（vp）
const GP_BUTTON_HIDE_DELAY: number = 4000;
const GP_BUTTON_SLIVER: number = 26;
// 隐藏态额外的触摸容差（vp）：把命中区域向屏幕内扩展，缓解贴边后不好点（可见态不扩展）
const GP_BUTTON_TOUCH_PAD: number = 10;

// Web 调试开关（DevTools）：置 true 后可用 hdc fport + chrome://inspect 排查 GP-Next 的失败点。
// ArkWeb 默认关闭，关闭时 DevTools 无法发现被调试的网页；正式发布前请改回 false。
const ENABLE_WEB_DEBUG: boolean = true;

// 网页弹框无人应答时的兜底超时（ms）：到点自动按"取消"回调 JsResult。
// 网页的 alert/confirm/prompt 是同步阻塞的，只要有一次没回调，render 进程就会一直卡住。
const JS_DIALOG_TIMEOUT: number = 120000;

// 画面比例约束区间 3:2 ~ 17:9。
// 用交叉相乘避免浮点比较：w/h > MAX 视为太宽，w/h < MIN 视为太方。
const MIN_ASPECT_W: number = 3;    // 最窄 3:2  ≈ 1.500
const MIN_ASPECT_H: number = 2;
const MAX_ASPECT_W: number = 171;  // 最宽 17:9 ≈ 1.889
const MAX_ASPECT_H: number = 90;

// "铺满画面"偏好在 preferences 中的键名
const PREF_WEB_FULLSCREEN: string = 'webview_fullscreen';


@Entry
@Component
struct CocosJSApp {
  private webController: webview.WebviewController = new webview.WebviewController();
  private downloadDelegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
  private filePickerHelper?: FilePickerHelper;
  private tempDownloadPath: string = '';
  private finalSaveUri: string = '';
  private isDownloading: boolean = false;
  private timeoutId?: number;
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
      this.prefs = await preferences.getPreferences(context, 'game_save');
      // 恢复"铺满画面"偏好
      this.isFillScreen = await this.prefs.get(PREF_WEB_FULLSCREEN, false) as boolean;
      // aboutToAppear 是异步的，首次布局触发的 onAreaChange 很可能先于这里完成，
      // 故读完偏好必须重算一次，否则保存过的"铺满"在启动时会被静默忽略。
      this.applyAspectRatio();
    } catch (err) {
      const error = err as BusinessError;
      console.error(`初始化 Preferences 失败: code=${error.code}, message=${error.message}`);
    }

    // 启动后开始计时：无操作一段时间后把 GP 按钮贴边隐藏
    this.scheduleGpHide();
  }

  /**
   * 把 Area 的 Length 值安全转成 vp 数值。
   * 运行时该值可能是 '720.00vp' 这类带单位字符串，`Number()` 会得到 NaN 并污染布局，
   * 故用 parseFloat 兜底；解析失败返回 0，随后退化为 100% 铺满。
   */
  private parseVp(value: Length): number {
    const n = Number.parseFloat(value.toString());
    return Number.isNaN(n) ? 0 : n;
  }

  /**
   * 按 3:2 ~ 17:9 区间计算 Web 的目标尺寸与居中偏移。
   *  - 太宽（> 17:9，如 20:9 / 21:9）：以高度为基准，宽度卡在 17:9，左右留黑边
   *  - 太方（< 3:2，如 4:3 / 7:5）：以宽度为基准，高度卡在 3:2，上下留黑边
   *  - 落在区间内：直接铺满
   */
  private applyAspectRatio(): void {
    const w = this.containerW;
    const h = this.containerH;
    // 尚未测量到容器尺寸，或处于铺满模式：交给 100% 尺寸
    if (w <= 0 || h <= 0 || this.isFillScreen) {
      this.webW = '100%';
      this.webH = '100%';
      this.webX = 0;
      this.webY = 0;
      return;
    }

    let targetW = w;
    let targetH = h;
    if (w * MAX_ASPECT_H > h * MAX_ASPECT_W) {
      // 太宽：> 17:9
      targetW = h * MAX_ASPECT_W / MAX_ASPECT_H;
    } else if (w * MIN_ASPECT_H < h * MIN_ASPECT_W) {
      // 太方：< 3:2
      targetH = w * MIN_ASPECT_H / MIN_ASPECT_W;
    }

    this.webW = targetW;
    this.webH = targetH;
    this.webX = (w - targetW) / 2;
    this.webY = (h - targetH) / 2;
  }

  /** 切换 铺满 / 按比例留边，并持久化（长按 GP-Next 按钮触发） */
  private async toggleFillScreen(): Promise<void> {
    this.isFillScreen = !this.isFillScreen;
    this.applyAspectRatio();
    this.showStatusMessage(this.isFillScreen ? '画面：铺满' : '画面：3:2 ~ 17:9 留边', 2000);

    if (!this.prefs) {
      return;
    }
    try {
      await this.prefs.put(PREF_WEB_FULLSCREEN, this.isFillScreen);
      await this.prefs.flush();
    } catch (err) {
      const error = err as BusinessError;
      console.error(`保存铺满偏好失败: code=${error.code}, message=${error.message}`);
    }
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

  /**
   * GP 按钮的命中区域：隐藏态向屏幕内扩 GP_BUTTON_TOUCH_PAD，补偿贴边后可见面积小、
   * 容易点不中的问题；可见态保持与按钮等大，避免在画面上留下不可见的死区。
   */
  private gpButtonResponseRegion(): Rectangle {
    const pad = this.gpButtonHidden ? GP_BUTTON_TOUCH_PAD : 0;
    return { x: -pad, y: -pad, width: GP_BUTTON_SIZE + pad * 2, height: GP_BUTTON_SIZE + pad * 2 };
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
  private async pickSaveTarget(fileName: string): Promise<string | null> {
    if (!this.filePickerHelper) {
      return null;
    }
    try {
      return await this.filePickerHelper.selectSavePath(fileName);
    } catch (err) {
      console.error('选择保存位置失败', err);
      return null;
    }
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
      this.webController.refresh();
    } catch (err) {
      console.error('注册 NativeStorage 失败', err);
    }
  }

  aboutToDisappear() {
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

  // 保存方法
  public async saveToNative(key: string, value: string): Promise<void> {
    if (!this.prefs) return;
    try {
      await this.prefs.put(key, value);
      await this.prefs.flush();
    } catch (err) {
      const error = err as BusinessError;
      console.error(`保存 ${key} 失败: ${error.message}`);
    }
  }

  // 读取方法
  public async loadFromNative(key: string): Promise<string> {
    if (!this.prefs) return '';
    try {
      const value = await this.prefs.get(key, '') as string;
      return value;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`读取 ${key} 失败: ${error.message}`);
      return '';
    }
  }



  private showStatusMessage(message: string, duration: number = 3000) {
    if (this.timeoutId) clearTimeout(this.timeoutId);
    this.statusOpacity = 1;
    this.downloadStatus = message;
    this.timeoutId = setTimeout(() => {
      this.getUIContext()?.animateTo({ duration: 300 }, () => { this.statusOpacity = 0; });
      setTimeout(() => {
        this.downloadStatus = '';
        this.statusOpacity = 1;
      }, 300);
      this.timeoutId = undefined;
    }, duration);
  }

  build() {
    // 根容器用 Stack：Web 铺满整屏，状态提示与 GP-Next 入口按钮分别叠加到顶部和右下角。
    // 叠加层只占用自身命中区域（状态栏另外放行触摸），不会遮挡游戏其余区域的操作。
    Stack({ alignContent: Alignment.BottomEnd }) {
      Web({ src: "https://cocos.local/index.html",
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
        // 返回 false：控制台消息仍旧写进 hilog（返回 true 会抑制默认日志）
        .onConsole((event) => {
          const message = event.message;
          console.info(`[web-console][${message.getMessageLevel()}] ${message.getMessage()}` +
            ` (${message.getSourceId()}:${message.getLineNumber()})`);
          return false;
        })
        // 在页面自身脚本之前注入 Tauri 兼容层：payload 自带的 localStorage polyfill 只在
        // window.__TAURI_INTERNALS__ 缺失时才安装，于是会自动让位给原生桥。
        .javaScriptOnDocumentStart([{ script: GPNEXT_SHIM, scriptRules: ['*'] }])
        .onControllerAttached(() => {
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
          this.webReady = true;
          // 注册下载委托
          this.setupDownloadDelegate();
          try {
            this.webController.setDownloadDelegate(this.downloadDelegate);
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
          const url = event.request.getRequestUrl();
          if (url.startsWith("https://cocos.local/")) {
            let rawFilePath = decodeURIComponent(url.replace("https://cocos.local/", ""));
            rawFilePath = rawFilePath.split('?')[0];

            // 1. 同步检查 ResourceManager LRU 缓存（快速路径，无异步开销）
            const resourceManager = ResourceManager.getInstance();
            const cachedData = resourceManager.getCachedSync(rawFilePath);
            if (cachedData) {
              const mimeType = this.getMimeType(rawFilePath);
              const response = new WebResourceResponse();
              response.setResponseData(cachedData);
              response.setResponseEncoding('utf-8');
              response.setResponseMimeType(mimeType);
              response.setResponseCode(200);
              response.setReasonMessage('OK');
              response.setResponseIsReady(true);
              return response;
            }

            // 2. 缓存未命中，从 rawfile 加载并返回
            try {
              const mimeType = this.getMimeType(rawFilePath);
              const response = new WebResourceResponse();
              response.setResponseData($rawfile(rawFilePath));
              response.setResponseEncoding('utf-8');
              response.setResponseMimeType(mimeType);
              response.setResponseCode(200);
              response.setReasonMessage('OK');
              response.setResponseIsReady(true);
              return response;
            } catch (error) {
              console.error(`拦截器读取文件失败: ${rawFilePath}`, error);
              return null;
            }
          }
          return null;
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
      // 下载/加载状态提示（叠加在画面顶部；放行触摸，避免盖住游戏操作区）
      Column() {
        if (this.downloadStatus) {
          Text(this.downloadStatus)
            .fontSize(14)
            .padding(8)
            .backgroundColor('#f0f0f0')
            .width('100%')
            .textAlign(TextAlign.Center)
            .opacity(this.statusOpacity)
            .animation({ duration: 300, curve: Curve.Linear })
        }

        if (this.isLoading && this.progress < 100) {
          Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
            .width('100%').height(4).color('#0A59F7')
        }
      }
      .width('100%')
      .position({ x: 0, y: 0 })
      .hitTestBehavior(HitTestMode.Transparent)

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

      // GP-Next 面板入口（可见按钮，贴在右下角）
      Button('GP', { type: ButtonType.Circle, stateEffect: true })
        .width(GP_BUTTON_SIZE)
        .height(GP_BUTTON_SIZE)
        .backgroundColor('#99000000')
        .fontColor(Color.White)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .borderWidth(1)
        .borderColor('#40FFFFFF')
        .margin({ right: GP_BUTTON_MARGIN, bottom: GP_BUTTON_MARGIN })
        // 贴边隐藏：向右移出屏幕，只留 GP_BUTTON_SLIVER 宽度可点；同时降低不透明度
        .translate({ x: this.gpButtonHidden ? (GP_BUTTON_MARGIN + GP_BUTTON_SIZE - GP_BUTTON_SLIVER) : 0 })
        .opacity(this.gpButtonHidden ? 0.45 : 1)
        // 隐藏态扩大命中区域，缓解"贴边后点不到"；可见态不扩展
        .responseRegion(this.gpButtonResponseRegion())
        .accessibilityText('打开 GP-Next 面板（长按切换铺满 / 留边）')
        .gesture(LongPressGesture().onAction(() => {
          if (this.gpButtonHidden) {   // 已隐藏时长按先唤出，避免误触切换
            this.setGpButtonHidden(false);
            return;
          }
          this.scheduleGpHide();
          this.toggleFillScreen();
        }))
        .onClick(async () => {
          if (this.gpButtonHidden) {   // 已隐藏时单击先唤出
            this.setGpButtonHidden(false);
            return;
          }
          this.scheduleGpHide();       // 可见态：执行动作并重新计时
          // 打开 GP-Next 面板
          try {
            // 切换 GP-Next 面板显隐。
            // payload（index-lw1dPoCM.js）真实挂载的是 window.gpNext = { toggle, show, hide, ... }，
            // 并没有 open 方法；兜底热键为 GP-Next 默认的 F9（gp-next-settings 的 overlayHotkey 默认值）。
            await this.webController.runJavaScript(`
            (function() {
              var g = window.gpNext;
              if (g) {
                if (typeof g.toggle === 'function') { g.toggle(); return; }
                if (typeof g.open === 'function') { g.open(); return; }
              }
              if (typeof window.Zt === 'function') { window.Zt(); return; }
              document.dispatchEvent(new KeyboardEvent('keydown', {
                key: 'F9', code: 'F9', keyCode: 120, bubbles: true
              }));
            })();
          `);
          } catch (error) {
            console.error('执行打开面板脚本失败:', error);
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)   // 比例留边时四周的黑边
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      // 用实际容器尺寸而非 display 尺寸：小窗 / 分屏 / 2in1 窗口模式下同样正确。
      // width/height 静态类型是 Length，可能是带单位字符串，故统一走 parseVp 兜底。
      const w = this.parseVp(newArea.width);
      const h = this.parseVp(newArea.height);
      if (w !== this.containerW || h !== this.containerH) {
        this.containerW = w;
        this.containerH = h;
        this.applyAspectRatio();
      }
    })
  }

  private setupDownloadDelegate() {
    this.downloadDelegate.onBeforeDownload(async (webDownloadItem: webview.WebDownloadItem) => {
      if (this.isDownloading) {
        console.log('已有下载任务在处理中');
        return;
      }
      this.isDownloading = true;
      this.showStatusMessage('正在准备下载...', 5000);

      try {
        let fileName = webDownloadItem.getSuggestedFileName();
        if (!fileName || fileName.includes('�')) {
          const url = webDownloadItem.getUrl();
          fileName = this.extractFileNameFromUrl(url) || `download_${Date.now()}`;
          fileName = fileName.replace(/[\\/:*?"<>|]/g, '_');
        }

        const saveUri = await this.filePickerHelper?.selectSavePath(fileName);
        if (!saveUri) {
          this.showStatusMessage('已取消下载', 2000);
          webDownloadItem.cancel();
          this.isDownloading = false;
          return;
        }
        this.finalSaveUri = saveUri;

        const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
        if (!context) return;
        const tempPath = `${context.cacheDir}/${fileName}`;
        this.tempDownloadPath = tempPath;

        this.showStatusMessage(`下载中: ${fileName}`, 10000);
        webDownloadItem.start(tempPath);
      } catch (err) {
        console.error('处理下载任务失败:', err);
        this.showStatusMessage('下载失败', 3000);
        this.isDownloading = false;
      }
    });

    this.downloadDelegate.onDownloadUpdated((webDownloadItem: webview.WebDownloadItem) => {
      const percent = webDownloadItem.getPercentComplete();
      if (this.downloadStatus.startsWith('下载中')) {
        this.downloadStatus = `下载中: ${percent}%`;
      }
    });

    this.downloadDelegate.onDownloadFailed(() => {
      this.showStatusMessage('下载失败', 3000);
      this.isDownloading = false;
      if (this.tempDownloadPath) {
        try { fs.unlinkSync(this.tempDownloadPath); } catch (e) {}
      }
    });

    this.downloadDelegate.onDownloadFinish(async () => {
      console.log('下载完成，开始复制到公共目录');
      if (!this.tempDownloadPath || !this.finalSaveUri) {
        this.showStatusMessage('下载失败，保存路径无效', 3000);
        this.isDownloading = false;
        return;
      }

      const getFileNameFromPath = (path: string): string => path.split('/').pop() || 'file';

      const createDirectoryIfNotExists = (uri: string): boolean => {
        try {
          try { if (fs.statSync(uri).isDirectory()) return true; } catch (e) {}
          fs.mkdirSync(uri, true);
          console.info(`目录创建成功: ${uri}`);
          return true;
        } catch (err) {
          console.error(`创建目录失败: ${uri}`, err);
          return false;
        }
      };

      const ensureParentDirectoryExists = (fileUri: string): boolean => {
        const lastSlash = fileUri.lastIndexOf('/');
        if (lastSlash <= 0) return true;
        const parentDir = fileUri.substring(0, lastSlash);
        return createDirectoryIfNotExists(parentDir);
      };

      const cleanPath = (path: string): string =>
      path.replace(/\/com\.example\.doubao\/com\.example\.doubao\//g, '/com.example.doubao/')
        .replace(/\/com\.example\.doubao\/\//g, '/com.example.doubao/');

      let destUri = cleanPath(this.finalSaveUri);
      let retry = false;
      let success = false;

      do {
        try {
          if (!ensureParentDirectoryExists(destUri)) break;
          const destFile = fs.openSync(destUri, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC | fs.OpenMode.CREATE);
          const srcFile = fs.openSync(this.tempDownloadPath, fs.OpenMode.READ_ONLY);
          fs.copyFileSync(srcFile.fd, destFile.fd);
          fs.closeSync(srcFile);
          fs.closeSync(destFile);
          fs.unlinkSync(this.tempDownloadPath);
          const stat = fs.statSync(destUri);
          this.showStatusMessage(`下载完成，大小: ${(stat.size / 1024).toFixed(1)} KB`, 2000);
          success = true;
          break;
        } catch (err) {
          if (!retry && err.message.includes('Is a directory')) {
            const fileName = getFileNameFromPath(this.tempDownloadPath);
            destUri = `${this.finalSaveUri}/${fileName}`;
            destUri = cleanPath(destUri);
            retry = true;
            continue;
          }
          console.error('复制文件失败:', err);
          // 备选：保存到应用私有目录
          const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
          if (!context) {
            this.showStatusMessage('保存失败，上下文无效', 3000);
            break;
          }
          const backupPath = `${context.filesDir}/${getFileNameFromPath(this.tempDownloadPath)}`;
          try {
            fs.copyFileSync(this.tempDownloadPath, backupPath);
            fs.unlinkSync(this.tempDownloadPath);
            this.showStatusMessage(`已保存到应用目录: ${backupPath}`, 3000);
            success = true;
          } catch (backupErr) {
            this.showStatusMessage('保存失败，请重试', 3000);
          }
          break;
        }
      } while (true);

      if (!success && this.tempDownloadPath) {
        try { fs.unlinkSync(this.tempDownloadPath); } catch (e) {}
      }
      this.isDownloading = false;
      this.tempDownloadPath = '';
      this.finalSaveUri = '';
    });
  }

  private extractFileNameFromUrl(url: string): string | null {
    try {
      const segments = url.split('/');
      const fileName = segments[segments.length - 1].split('?')[0];
      if (fileName && fileName.includes('.')) return decodeURIComponent(fileName);
      return null;
    } catch { return null; }
  }

  private getMimeType(fileName: string): string {
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
      case 'svg': return 'image/svg+xml';
      case 'data': return 'application/octet-stream';
      default: return 'text/plain';
    }
  }
}