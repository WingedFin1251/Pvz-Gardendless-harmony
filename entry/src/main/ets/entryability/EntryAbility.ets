import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';  // 新增导入，用于 WebView 性能优化

const DOMAIN = 0x0000;

/**
 * 是否为 PC/2in1 设备类型。
 *
 * 2in1 是自由窗口（PC 形态）设备：没有手机/平板式的状态栏与导航条，也不支持传感器旋转。
 * 官方文档在相关接口的「设备行为差异」中明确说明其在 2in1 上不生效，因此按设备类型分流，
 * 避免调用对本设备类型无效的接口。
 */
const IS_2IN1: boolean = deviceInfo.deviceType === deviceInfo.DeviceTypes.TYPE_2IN1;

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

    // ========== WebView 渲染进程模式 ==========
    // 官方《ArkWeb进程》：「默认策略：移动设备上共享渲染进程以节省内存，2in1 设备上独立渲染进程
    // 提升安全与稳定性」。本应用只有一个 Web 组件，强制 MULTIPLE 只会额外占用内存：真机实测
    // （MatePad 11.5"S / DMG-W00，8 GB + 6 GB swap）在 8 小时会话后 swap 用满、被系统以
    // `SwapFull` 与 `LowMemoryKill` 各杀过一次，因此手机/平板按平台默认走 SINGLE（共享），
    // 仅 2in1 保留 MULTIPLE。
    try {
      const mode: webview.RenderProcessMode = IS_2IN1
        ? webview.RenderProcessMode.MULTIPLE
        : webview.RenderProcessMode.SINGLE;
      webview.WebviewController.setRenderProcessMode(mode);
      hilog.info(DOMAIN, 'testTag', '渲染进程模式: %{public}s', IS_2IN1 ? 'MULTIPLE(2in1)' : 'SINGLE(移动设备,省内存)');
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '设置渲染进程模式失败: %{public}s', (err as BusinessError).message);
    }

    // 注意：不启用 enableWholeWebPageDrawing() — 游戏不需要离屏截图，
    // 它会每帧额外渲染一个离屏帧缓冲，直接损耗 FPS。

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
  // 注：方法内两处调用在 2in1 上属官方文档所述「不生效也不报错」的接口，
  // 用 // @SuppressWarnings syscap 屏蔽多设备告警（注释形式只作用于紧邻的下一行语句）。
  private async setFullScreen(mainWindow: window.Window): Promise<void> {
    try {
      // 沉浸式布局：三种设备类型均可正常调用，布局不避让系统栏
      await mainWindow.setWindowLayoutFullScreen(true);

      if (IS_2IN1) {
        // 2in1 无手机/平板式状态栏与导航条，setWindowSystemBarEnable 在此不生效（官方「设备行为差异」）。
        // 改用最大化窗口：maximize() 默认使用 MaximizePresentation.ENTER_IMMERSIVE，即最大化并进入全屏。
        await mainWindow.maximize();
      } else {
        // 手机/平板：隐藏状态栏和导航栏
        // @SuppressWarnings syscap
        await mainWindow.setWindowSystemBarEnable([]);
      }

      // 窗口背景色：Stage 模型下需在 loadContent() 生效后调用（见 onWindowStageCreate）
      // @SuppressWarnings syscap
      mainWindow.setWindowBackgroundColor('#000000');

      // 游戏过程中保持屏幕常亮：既符合游戏体感，也避免熄屏后应用转入后台被系统回收
      // （真机上曾观测到切到后台后因内存压力被 LowMemoryKill / SwapFull 杀掉）。
      await mainWindow.setWindowKeepScreenOn(true);

      hilog.info(DOMAIN, 'testTag', '全屏沉浸设置成功');
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '设置全屏或系统栏失败: %{public}s', (err as BusinessError).message);
    }
  }

  // 横屏设置（异步）
  private async setLandscapeOrientation(mainWindow: window.Window): Promise<void> {
    // 2in1 为自由窗口形态且不支持传感器旋转，setPreferredOrientation 调用不生效（官方「设备行为差异」：
    // 其他情况不生效不报错）。竖屏锁定由 module.json5 中 EntryAbility 的 "orientation": "landscape" 声明保证，
    // 因此 2in1 上直接跳过，避免调用无效接口。
    if (IS_2IN1) {
      hilog.info(DOMAIN, 'testTag', '2in1 无传感器旋转，跳过窗口方向设置');
      return;
    }
    try {
      // @SuppressWarnings syscap
      await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE);
      hilog.info(DOMAIN, 'testTag', '横屏设置成功');
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '设置横屏方向失败: %{public}s', (err as BusinessError).message);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 先加载页面，再配置窗口：官方文档要求 Stage 模型下 setWindowBackgroundColor()
    // 必须在 loadContent() 生效后调用，原实现两者并发执行存在竞态。
    windowStage.loadContent('pages/Index', (err) => {
      if (err && err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', err.message);
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');

      // 获取主窗口，设置全屏 + 横屏
      windowStage.getMainWindow()
        .then(async (mainWindow) => {
          await this.setFullScreen(mainWindow);
          await this.setLandscapeOrientation(mainWindow);
        })
        .catch((error: BusinessError) => {
          hilog.error(DOMAIN, 'testTag', '获取主窗口失败: %{public}s', error.message);
        });
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