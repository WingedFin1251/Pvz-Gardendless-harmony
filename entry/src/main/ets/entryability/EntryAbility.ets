import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    void want;
    void launchParam;
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', (err as BusinessError).message);
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  // 全屏设置 - 使用 try-catch + return 消除警告
  private setFullScreen(mainWindow: window.Window): void {
    try {
      mainWindow.setWindowLayoutFullScreen(true);
      mainWindow.setWindowBackgroundColor('#000000');
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '设置全屏或背景色失败: %{public}s', (err as BusinessError).message);
      return; // 明确已处理异常
    }
  }

  // 横屏设置 - 同样处理异常
  private setLandscapeOrientation(mainWindow: window.Window): void {
    try {
      mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '设置横屏方向失败: %{public}s', (err as BusinessError).message);
      return;
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 获取主窗口，设置全屏 + 横屏
    windowStage.getMainWindow().then((mainWindow) => {
      try {
        this.setFullScreen(mainWindow);
        this.setLandscapeOrientation(mainWindow);   // 关键：启动时横屏
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', '设置窗口属性时发生同步异常: %{public}s', (err as BusinessError).message);
      }
    }).catch((err: BusinessError) => {
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