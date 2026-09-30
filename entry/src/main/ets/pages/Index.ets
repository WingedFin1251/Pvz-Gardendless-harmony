import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { FilePickerHelper } from './FilePickerHelper';  // 复用 FilePickerHelper
import preferences from '@ohos.data.preferences';
import { BusinessError } from '@kit.BasicServicesKit'; // 确保已导入
import { ResourceManager } from '../utils/ResourceManager';
import { util } from '@kit.ArkTS';
 import { displaySync } from '@kit.ArkGraphics2D';

// ==================== 负载目录（单一真相点） ====================
// 游戏负载（Cocos 构建产物，含它**自带的** index.html）统一放在 rawfile/<PAYLOAD_DIR> 下：
//   - 更新负载 = 整目录替换，壳层文件、.gitignore、构建脚本都不用动；
//   - 负载自带的 index.html 若用**根绝对路径**引用自己的模块（/assets/xxx.js），靠拦截器补这个前缀；
//   - 留在 rawfile 根、由壳层自己提供的文件不补前缀（见 SHELL_ROOT_FILES）。
// 想改名只需改这一处常量 + .gitignore 一行。
const PAYLOAD_DIR: string = 'game/';
const SHELL_ROOT_FILES: string[] = ['touchPatch.js'];
// 触摸补丁的源文件（留在 rawfile 根，由壳层读入后在 document-start 注入，不再依赖 HTML 引用）
const TOUCH_PATCH_RAWFILE: string = 'touchPatch.js';

// 画面比例约束区间 3:2 ~ 17:9。
// 用交叉相乘避免浮点比较：w/h > MAX 视为太宽，w/h < MIN 视为太方。
const MIN_ASPECT_W: number = 3;    // 最窄 3:2  ≈ 1.500
const MIN_ASPECT_H: number = 2;
const MAX_ASPECT_W: number = 171;  // 最宽 17:9 ≈ 1.889
const MAX_ASPECT_H: number = 90;

// ==================== 期望帧率投票（可变帧率 / LTPO） ====================
// 背景：鸿蒙的"控帧系统"收集应用的**期望绘制帧率**参与整机刷新率决策；没有高帧率投票时，
// 系统在无触摸/内容静止时会自适应降到 60Hz（真机实测：平板支持 30/60/90/120/144，但
// activeMode 常驻 60，有触摸时回到 120）。本 Web 组件属系统组件，拿不到 XComponent 那套
// 自绘制接口，只能用 displaySync 参与投票。
//
// 代价与限制（官方最佳实践：displaySync 滥用会增加功耗、干扰可变帧率机制）：
//   - 应用会按期望帧率接收 Vsync（回调里刻意不做任何工作）；
//   - 真实生效还取决于屏幕硬件能力与系统功耗策略 —— 官方原文：期望帧率
//     "不能代表最终实际效果"；游戏自身若限制在 60fps，系统同样没有理由保持高刷。
// 想关闭：把 ENABLE_HIGH_REFRESH_VOTE 改成 false。
const ENABLE_HIGH_REFRESH_VOTE: boolean = true;
const HIGH_REFRESH_EXPECTED: number = 120;
const HIGH_REFRESH_MIN: number = 60;

@Entry
@Component
struct CocosJSApp {
  private webController: webview.WebviewController = new webview.WebviewController();
  // document-start 注入脚本 = touchPatch.js 的内容（在 aboutToAppear 里从 rawfile 读入）。
  // 这样负载更新（整目录替换 game/）不会再冲掉对它的引用 —— 原先它靠 index.html 里的一行 <script src>。
  private injectedScript: string = '';
  private downloadDelegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
  private filePickerHelper?: FilePickerHelper;
  private tempDownloadPath: string = '';
  private finalSaveUri: string = '';
  private isDownloading: boolean = false;
  private timeoutId?: number;
  private prefs?: preferences.Preferences;

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

  /** 期望帧率投票实例（仅在页面可见期间持有，避免后台空刷帧） */
  private highRefreshVote: displaySync.DisplaySync | undefined = undefined;

  async aboutToAppear() {
    // 期望帧率投票（页面可见期间持有；不可见时在 onPageHide 里停掉）
    this.startHighRefreshVote();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      console.error('获取 Context 失败');
      return;
    }
    this.filePickerHelper = new FilePickerHelper(context);

    // 读入 touchPatch.js 作为 document-start 注入脚本
    try {
      const bytes = context.resourceManager.getRawFileContentSync(TOUCH_PATCH_RAWFILE);
      this.injectedScript = util.TextDecoder.create('utf-8').decodeToString(bytes);
      console.info(`注入脚本就绪: touchPatch ${this.injectedScript.length} B`);
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

    // 初始化 ResourceManager（LRU 缓存，80MB/300项上限）
    ResourceManager.getInstance().setContext(context);
    console.info('ResourceManager 已初始化');

    // 初始化 Preferences
    try {
      this.prefs = await preferences.getPreferences(context, 'game_save');
    } catch (err) {
      const error = err as BusinessError;
      console.error(`初始化 Preferences 失败: code=${error.code}, message=${error.message}`);
    }
  }

  /**
   * 把 Area 的 Length 值安全转成 vp 数值。
   * 运行时该值可能是 '720.00vp' 这类带单位字符串，`Number()` 会得到 NaN 并污染布局，
   * 故用 parseFloat 兜底；解析失败返回 0，随后退化为 100% 铺满。
   */
  /**
   * 向系统"投票"期望帧率（可变帧率机制）。
   * 只在页面可见期间持有；回调里不做任何工作 —— 它的唯一作用是让控帧系统知道
   * "这个页面期望高帧率"，从而在无触摸时也尽量维持高刷新率。
   */
  private startHighRefreshVote(): void {
    if (!ENABLE_HIGH_REFRESH_VOTE || this.highRefreshVote !== undefined) {
      return;
    }
    try {
      const vote = displaySync.create();
      vote.setExpectedFrameRateRange({
        expected: HIGH_REFRESH_EXPECTED,
        min: HIGH_REFRESH_MIN,
        max: HIGH_REFRESH_EXPECTED
      });
      vote.on('frame', () => {
        // 刻意留空：只为投票，不做任何绘制 / 计算
      });
      vote.start();
      this.highRefreshVote = vote;
      console.info(`期望帧率投票已开启: expected=${HIGH_REFRESH_EXPECTED} min=${HIGH_REFRESH_MIN}`);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`期望帧率投票失败: code=${error.code}, message=${error.message}`);
    }
  }

  /** 停止投票并释放实例（页面不可见 / 退出时调用） */
  private stopHighRefreshVote(): void {
    const vote = this.highRefreshVote;
    if (vote === undefined) {
      return;
    }
    this.highRefreshVote = undefined;
    try {
      vote.stop();
      vote.off('frame');
      console.info('期望帧率投票已停止');
    } catch (err) {
      const error = err as BusinessError;
      console.error(`停止期望帧率投票失败: code=${error.code}, message=${error.message}`);
    }
  }

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
    // 尚未测量到容器尺寸：交给 100% 尺寸
    if (w <= 0 || h <= 0) {
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

  /** 页面重新可见：恢复期望帧率投票 */
  onPageShow() {
    this.startHighRefreshVote();
  }

  /** 页面不可见（切后台 / 跳转）：停止投票，避免空刷帧与额外功耗 */
  onPageHide() {
    this.stopHighRefreshVote();
  }

  aboutToDisappear() {
    // 页面销毁：停掉期望帧率投票
    this.stopHighRefreshVote();
    if (this.timeoutId) clearTimeout(this.timeoutId);

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
    // 根容器用 Stack：Web 按比例铺满容器，状态提示叠加到顶部。
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
        // document-start 注入触摸补丁（负载更新不再会冲掉它）
        .javaScriptOnDocumentStart([{ script: this.injectedScript, scriptRules: ['*'] }])
        .onControllerAttached(() => {
          this.registerNativeStorage();  // 注册 localStorage 持久化代理
          // ... 其他代码
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

            // 负载在 rawfile/game/ 下（PAYLOAD_DIR）；壳层自带文件在 rawfile 根。
            // 负载自带的 index.html 若用根绝对路径引用自己的模块，故这里补前缀；
            // 已经是 game/ 开头的请求（来自页面的相对路径）不重复补。
            if (!rawFilePath.startsWith(PAYLOAD_DIR) && SHELL_ROOT_FILES.indexOf(rawFilePath) < 0) {
              rawFilePath = PAYLOAD_DIR + rawFilePath;
            }

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

          // 4. 外部链接 → 跳转系统浏览器
          try {
            const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
            if (context) {
              context.openLink(url);
              console.info(`已跳转到系统浏览器: ${url}`);
            }
          } catch (err) {
            console.error(`跳转失败: ${url}`, err);
          }
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
      // 其余一律按二进制：0.15.0 的 lite 用 .avif 纹理，先前 default=text/plain
      // 会让图片解码失败、引擎资源加载卡死（表现为面板一直「Waiting for engine…」）
      default: return 'application/octet-stream';
    }
  }
}