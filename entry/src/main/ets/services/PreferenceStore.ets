import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 偏好存储（Preferences）落盘层。
 *
 * ⚠️ 它**不是"桥"** —— 桥是页面自己注册的 JS 代理对象 `NativeStorage`
 * （`registerJavaScriptProxy(this, 'NativeStorage', [...])`，注册的必须是页面本身，
 *   否则代理调用里的 `this` 绑定会变 —— 这一点不能动）。
 *
 * 调用链：网页 `touchPatch.js`（白名单）→ `window.NativeStorage.saveToNative()`
 *         → 页面的 public 方法（仍同名同签名，只转发一行）→ **本模块** → Preferences(store `game_save`)
 *
 * 本模块的职责：
 *   · `save()` 里 `put()` **立即执行**（先落到 Preferences 的内存缓存，不丢数据）
 *   · `flush()`（真正写磁盘）**去抖合并** —— 因为花园格子 / 骆驼关的 update() 会**逐帧**写存档
 *   · 但去抖**必须有上限**：持续不断的写入如果一直推迟尾沿，就会永远不落盘
 *     ⇒ 首次待刷写起算超过 `FLUSH_MAX_DELAY_MS` 时立即刷一次
 *   · `flushNow()` 供页面在 `onPageHide` / `aboutToDisappear` 时**强制**刷一次
 *     （否则被 force-stop 时可能丢掉最后一个去抖窗口内的写入）
 */

/** 尾沿去抖：最后一次写入之后等这么久再刷盘 */
const FLUSH_DEBOUNCE_MS: number = 400;
/** 去抖上限：从"首次有待刷写数据"起算，最多推迟这么久必须刷一次（防持续写入永不落盘） */
const FLUSH_MAX_DELAY_MS: number = 1500;

/**
 * A1：持久化键的判定规则 —— 固定键 ∪ 前缀匹配。
 * 与页面侧 `touchPatch.js` 的 `PERSIST_KEYS` / `PERSIST_PREFIXES` **必须保持一致**。
 * 前缀存在的理由：第三方模组的键名是动态的（如 gpn_killlevel_plantkills_v3），固定白名单列不全。
 */
const PERSIST_KEYS: string[] = ['PvZ2_PlayerProperties', 'PvZ2_Settings', 'gp-next-settings'];
const PERSIST_PREFIXES: string[] = ['gpn_'];
/** 护栏：单值上限（字符数，与页面侧一致：模组的玩家档备份约 175KB，故取 256KB） */
const PERSIST_MAX_VALUE_BYTES: number = 256 * 1024;

function isPersistKey(key: string): boolean {
  if (key.length === 0 || key.length > 128) { return false; }
  if (PERSIST_KEYS.indexOf(key) >= 0) { return true; }
  for (let i = 0; i < PERSIST_PREFIXES.length; i++) {
    if (key.startsWith(PERSIST_PREFIXES[i])) { return true; }
  }
  return false;
}
/** 刷盘失败后延迟重试的间隔（仅安排一次，避免失败时疯狂重试） */
const FLUSH_RETRY_DELAY_MS: number = 2000;

export class PreferenceStore {
  private prefs: preferences.Preferences | undefined = undefined;
  /** 是否有已 put 但还没 flush 的数据 */
  private flushPending: boolean = false;
  /** 首次出现待刷数据的时刻（用于去抖上限） */
  private firstPendingAt: number = 0;
  /** 去抖定时器 */
  private flushTimer: number = -1;
  /** 是否已经安排了一次"刷盘失败后的重试"（避免失败时疯狂重试） */
  private retryScheduled: boolean = false;

  /** 绑定 Preferences 实例（页面初始化完 prefs 之后调用一次） */
  attach(prefs: preferences.Preferences): void {
    this.prefs = prefs;
  }

  /** 是否已就绪（未就绪时读写都安全空转，与拆分前行为一致） */
  isReady(): boolean {
    return this.prefs !== undefined;
  }

  /** Web 侧 localStorage.setItem（白名单键）→ Preferences；put 立即，flush 去抖 */
  async save(key: string, value: string): Promise<void> {
    const store = this.prefs;
    // A1 护栏：超大值不入 Preferences（页面侧同样会跳过；这里是第二道网）
    if (value !== undefined && value !== null && value.length > PERSIST_MAX_VALUE_BYTES) {
      console.warn(`跳过持久化（值过大）: ${key} ${value.length} 字符`);
      return;
    }
    if (!store) {
      return;
    }
    try {
      await store.put(key, value);
      this.scheduleFlush(store);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`保存 ${key} 失败: ${error.message}`);
    }
  }

  /** Web 侧 localStorage.getItem ← Preferences（读不到返回空串） */
  /**
   * A1：列出"应当持久化"的键（固定键 ∪ 前缀匹配）。
   * 用途：清缓存后页面侧一个键都不知道，必须由原生侧枚举回来，否则启动时无从回填 ——
   * 这正是"模组数据清缓存就归零"的另一半原因。
   */
  async listPersistedKeys(): Promise<string[]> {
    const store = this.prefs;
    if (!store) {
      return [];
    }
    try {
      const all: Object = await store.getAll();
      const keys: string[] = [];
      for (const key of Object.keys(all)) {
        if (isPersistKey(key)) {
          keys.push(key);
        }
      }
      return keys;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`枚举持久化键失败: code=${error.code}, message=${error.message}`);
      return [];
    }
  }

  async load(key: string): Promise<string> {
    const store = this.prefs;
    if (!store) {
      return '';
    }
    try {
      const value = await store.get(key, '') as string;
      return value;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`读取 ${key} 失败: ${error.message}`);
      return '';
    }
  }

  /** 立刻把待刷数据写盘（页面隐藏 / 退出前调用；无待刷数据时是空操作） */
  flushNow(): void {
    const store = this.prefs;
    if (!store) {
      return;
    }
    if (this.flushTimer >= 0) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
    if (!this.flushPending) {
      return;
    }
    this.flushPending = false;
    this.firstPendingAt = 0;
    try {
      store.flush()
        .then(() => { /* 成功：无需日志 */ })
        .catch((err: BusinessError) => {
          // 失败：恢复待刷标志并安排一次重试，否则这一段写入（可能是玩家的存档）会永远丢
          this.onFlushFailed(store, err.message);
        });
    } catch (err) {
      const error = err as BusinessError;
      this.onFlushFailed(store, error.message);
    }
  }

  /** 刷盘失败后的收尾：恢复待刷标志 + 安排一次（仅一次）延迟重试 */
  private onFlushFailed(store: preferences.Preferences, message: string): void {
    this.flushPending = true;
    if (this.firstPendingAt === 0) {
      this.firstPendingAt = Date.now();
    }
    console.error(`刷写 Preferences 失败（已保留待刷标志，稍后重试）: ${message}`);
    if (this.retryScheduled) {
      return;   // 已经安排过重试，不重复安排
    }
    this.retryScheduled = true;
    setTimeout(() => {
      this.retryScheduled = false;
      this.flushNow();
    }, FLUSH_RETRY_DELAY_MS);
  }

  /** 安排一次去抖刷盘；若已超过去抖上限则立即刷 */
  private scheduleFlush(store: preferences.Preferences): void {
    this.flushPending = true;
    const now = Date.now();
    if (this.firstPendingAt === 0) {
      this.firstPendingAt = now;
    }
    // 持续写入导致尾沿一直被推迟时，用上限兜底，避免永远不落盘
    if (now - this.firstPendingAt >= FLUSH_MAX_DELAY_MS) {
      this.flushNow();
      return;
    }
    if (this.flushTimer >= 0) {
      clearTimeout(this.flushTimer);
    }
    this.flushTimer = setTimeout(() => {
      this.flushTimer = -1;
      this.flushNow();
    }, FLUSH_DEBOUNCE_MS);
  }
}
