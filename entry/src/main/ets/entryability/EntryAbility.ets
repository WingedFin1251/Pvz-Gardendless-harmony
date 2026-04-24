import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';  // 新增导入，用于 WebView 性能优化

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    void want;
    void launchParam;

    // ========== 原有颜色模式设置 ==========
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', (err as BusinessError).message);
    }

    // ========== 新增 WebView 性能优化（来自第一个片段） ==========
    // 1. 设置渲染进程模式为多进程（根据设备性能决定）
    try {
      webview.WebviewController.setRenderProcessMode(webview.RenderProcessMode.MULTIPLE);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '设置渲染进程模式失败: %{public}s', (err as BusinessError).message);
    }

    // 2. 开启网页全量绘制能力（必须在Web初始化前调用）
    try {
      webview.WebviewController.enableWholeWebPageDrawing();
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '开启全量绘制失败: %{public}s', (err as BusinessError).message);
    }

    // 3. 初始化 Web 引擎
    webview.WebviewController.initializeWebEngine();

    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  // ========== 新增内存压力响应（来自第一个片段） ==========
  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    try {
      // 当内存压力为中等或严重时，释放 Webview 部分内存
      if (level >= AbilityConstant.MemoryLevel.MEMORY_LEVEL_MODERATE) {
        webview.WebviewController.trimMemoryByPressureLevel(webview.PressureLevel.MEMORY_PRESSURE_LEVEL_MODERATE);
      }
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '修剪内存失败: %{public}s', (err as BusinessError).message);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  // 全屏设置（异步）
  private async setFullScreen(mainWindow: window.Window): Promise<void> {
    try {
      await mainWindow.setWindowLayoutFullScreen(true);
      await mainWindow.setWindowSystemBarEnable([]);   // 隐藏状态栏和导航栏
      mainWindow.setWindowBackgroundColor('#000000');
      hilog.info(DOMAIN, 'testTag', '全屏沉浸设置成功');
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '设置全屏或系统栏失败: %{public}s', (err as BusinessError).message);
    }
  }

  // 横屏设置（异步）
  private async setLandscapeOrientation(mainWindow: window.Window): Promise<void> {
    try {
      await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE);
      hilog.info(DOMAIN, 'testTag', '横屏设置成功');
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '设置横屏方向失败: %{public}s', (err as BusinessError).message);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 获取主窗口，设置全屏 + 横屏
    windowStage.getMainWindow()
      .then(async (mainWindow) => {
        await this.setFullScreen(mainWindow);
        await this.setLandscapeOrientation(mainWindow);
      })
      .catch((err: BusinessError) => {
        hilog.error(DOMAIN, 'testTag', '获取主窗口失败: %{public}s', err.message);
      });

    // 加载页面
    windowStage.loadContent('pages/Index', (err) => {
      if (err && err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', err.message);
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}