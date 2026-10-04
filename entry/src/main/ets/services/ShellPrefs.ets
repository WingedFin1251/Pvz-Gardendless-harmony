import preferences from '@ohos.data.preferences';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 壳层**自己**的偏好读写。
 *
 * ⚠️ 与 `services/PreferenceStore.ets` 分工不同，别混：
 *   · **本文件**：壳层自己的键 —— `webview_fullscreen`（铺满/留边）、`expected_refresh`（期望刷新率）、
 *     `settings_hint_seen`（首次提示只弹一次）。键名与默认值都定义在这里，页面只调用方法。
 *   · `services/PreferenceStore.ets`：**网页侧**白名单键（`PvZ2_PlayerProperties` / `PvZ2_Settings`）
 *     的上报落盘与 `flush()` 去抖。
 * 两者共用同一个 Preferences store（`game_save`），但键名各自独立、互不影响。
 *
 * 这些键的写入很稀疏（用户点一下才写），因此**不做去抖**：put + flush 立即完成，语义最简单。
 */

/** "铺满画面"偏好的键名 */
export const PREF_WEB_FULLSCREEN: string = 'webview_fullscreen';
/** 期望刷新率偏好的键名（`off` / `60` / `120` / `max`） */
export const PREF_EXPECTED_REFRESH: string = 'expected_refresh';
/** 首次启动提示（长按 GP 按钮打开设置）的键名 */
export const PREF_SETTINGS_HINT_SEEN: string = 'settings_hint_seen';
/** 期望刷新率的首次启动默认值（面板可改，改完即持久化） */
export const DEFAULT_EXPECTED_REFRESH: string = '120';

export class ShellPrefs {
  private prefs: preferences.Preferences | undefined = undefined;

  /** 绑定 Preferences 实例（页面初始化完 prefs 之后调用一次） */
  attach(prefs: preferences.Preferences): void {
    this.prefs = prefs;
  }

  /** 是否已就绪（未就绪时读返回默认值、写安全空转） */
  isReady(): boolean {
    return this.prefs !== undefined;
  }

  /** 读"铺满 / 留边" */
  async loadFillScreen(): Promise<boolean> {
    const store = this.prefs;
    if (!store) {
      return false;
    }
    return await store.get(PREF_WEB_FULLSCREEN, false) as boolean;
  }

  /** 写"铺满 / 留边" */
  async saveFillScreen(value: boolean): Promise<void> {
    await this.put(PREF_WEB_FULLSCREEN, value, '铺满偏好');
  }

  /** 读期望刷新率 */
  async loadExpectedRefresh(): Promise<string> {
    const store = this.prefs;
    if (!store) {
      return DEFAULT_EXPECTED_REFRESH;
    }
    return await store.get(PREF_EXPECTED_REFRESH, DEFAULT_EXPECTED_REFRESH) as string;
  }

  /** 写期望刷新率 */
  async saveExpectedRefresh(value: string): Promise<void> {
    await this.put(PREF_EXPECTED_REFRESH, value, '期望刷新率');
  }

  /** 读"首次提示是否已弹过" */
  async loadHintSeen(): Promise<boolean> {
    const store = this.prefs;
    if (!store) {
      return true;   // 未就绪时当作"已弹过"，避免重复打扰
    }
    return await store.get(PREF_SETTINGS_HINT_SEEN, false) as boolean;
  }

  /** 记下"首次提示已弹过" */
  async markHintSeen(): Promise<void> {
    await this.put(PREF_SETTINGS_HINT_SEEN, true, '提示已读标记');
  }

  /** put + flush（这三个键写入稀疏，不做去抖） */
  private async put(key: string, value: preferences.ValueType, label: string): Promise<void> {
    const store = this.prefs;
    if (!store) {
      return;
    }
    try {
      await store.put(key, value);
      await store.flush();
    } catch (err) {
      const error = err as BusinessError;
      console.error(`保存${label}失败: code=${error.code}, message=${error.message}`);
    }
  }
}
