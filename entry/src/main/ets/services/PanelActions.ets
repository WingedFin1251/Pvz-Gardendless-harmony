/**
 * 壳层设置面板的「动作层」。
 *
 * ⚠️ 注意区分两个容易混淆的“设置”：
 *   · **壳层自己的偏好**（期望刷新率 / 铺满留边 / 提示只看一次）→ `services/ShellPrefs.ets`，写 **Preferences**
 *   · **页面里的 GP-Next 设置存储** `localStorage['gp-next-settings']`（帧率上限 / 实验开关 / overlayHotkey）
 *     → **本模块只是“读它、改它”，它归 GP-Next 自己所有**，并不在 Preferences 里
 *       （只有进了 `touchPatch.js` 白名单的键才会被镜像进 Preferences —— 见 docs/MODULES.md）
 *
 * 本模块的边界：
 *   · 只负责**与页面 / 引擎打交道并返回结果**；
 *   · **不持有任何 UI 状态，也不弹提示** —— 状态与提示由页面（`Index.ets`）决定。
 *   · 与页面的通信统一走调用方传入的 `runJs`（页面传 `webController.runJavaScript`），
 *     这样本模块不依赖 Web 组件，便于单独理解与测试。
 */

/** 面板需要的引擎侧读数 */
export interface PanelEngineReadout {
  /** 当前生效的帧率上限：`'不限'` / `'60 fps'` / `'未知'` */
  frameRateLabel: string;
  /** 「实验帧率调度」是否开启（平板上开着会明显卡顿） */
  schedulerOn: boolean;
  /** 实验调度的帧率标签（未开启时为 `'已关闭'`） */
  schedulerFrameRateLabel: string;
}

/** 读「帧率上限」的 JS：两个字段互不相干，实验调度开启时以实验值优先；-1 = 读不到 */
const JS_READ_FRAME_RATE: string = `(function(){
  try {
    var s = JSON.parse(localStorage.getItem('gp-next-settings') || '{}') || {};
    var ex = s.experimental || {};
    var v = (ex.frameScheduler === true) ? ex.frameRate : s.frameRate;
    if (v === undefined || v === null || v === '') { return -1; }
    var n = Number(v);
    return isNaN(n) ? -1 : n;
  } catch (e) { return -1; }
})()`;

/** 读「实验帧率调度」的 JS：-2 = 调度关闭；>=0 = 实验性帧率 */
const JS_READ_SCHEDULER: string = `(function(){
  try {
    var s = JSON.parse(localStorage.getItem('gp-next-settings') || '{}') || {};
    var ex = s.experimental || {};
    if (ex.frameScheduler !== true) { return -2; }
    var v = Number(ex.frameRate);
    return isNaN(v) ? -2 : v;
  } catch (e) { return -2; }
})()`;

/** 写「关闭实验帧率调度」的 JS：1 = 成功，-1 = 失败 */
const JS_DISABLE_SCHEDULER: string = `(function(){
  try {
    var s = JSON.parse(localStorage.getItem('gp-next-settings') || '{}') || {};
    s.experimental = s.experimental || {};
    s.experimental.frameScheduler = false;
    localStorage.setItem('gp-next-settings', JSON.stringify(s));
    return 1;
  } catch (e) { return -1; }
})()`;

/** 只读「实验帧率调度是否开启」的 JS：1 = 开，0 = 关，-1 = 读不到 */
const JS_IS_SCHEDULER_ON: string = `(function(){
  try {
    var s = JSON.parse(localStorage.getItem('gp-next-settings') || '{}') || {};
    var ex = s.experimental || {};
    return ex.frameScheduler === true ? 1 : 0;
  } catch (e) { return -1; }
})()`;

/**
 * 把引擎上限设为「不限」的 JS：
 *   1) 向引擎请求不限（GP-Next 暴露的 mod API，安全老路径，不涉及实验调度器）
 *   2) 同时把存档值写成字符串 '0' —— 上游性能页对 '0' 有特判（显示"不限"），
 *      否则它会拿存档里的旧数字（如 60）当"目标FPS"，看着像被限住
 */
const JS_FORCE_UNLIMITED: string = `(function(){
  try {
    var ok = 0;
    if (window.gpNext && typeof window.gpNext.setFrameRate === 'function') {
      window.gpNext.setFrameRate(999);
      ok = 1;
    }
    try {
      var s = JSON.parse(localStorage.getItem('gp-next-settings') || '{}') || {};
      s.frameRate = '0';
      localStorage.setItem('gp-next-settings', JSON.stringify(s));
      ok = 1;
    } catch (e2) { }
    return ok;
  } catch (e) { return -1; }
})()`;

/** 采样引擎总帧数的 JS：-1 = 引擎还没就绪 */
const JS_SAMPLE_TOTAL_FRAMES: string = `(function(){
  try { if (!window.cc || !cc.director) { return -1; } return cc.director.getTotalFrames(); }
  catch (e) { return -1; }
})()`;

/** 打开 GP-Next 面板的 JS：与 GP 按钮单击同一条路径（window.gpNext → window.Zt → F9 兜底） */
const JS_OPEN_GP_NEXT_PANEL: string = `
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
`;

/** 把 JS 返回值转成数字（非数字 → NaN） */
function toNumber(rawValue: string): number {
  const parsed = Number(String(rawValue).trim());
  return Number.isFinite(parsed) ? parsed : NaN;
}

/** 帧率数值 → 面板标签 */
function frameRateText(value: number): string | undefined {
  if (!Number.isFinite(value) || value < 0) {
    return undefined;
  }
  return (value === 0 || value === 999) ? '不限' : value + ' fps';
}

export class PanelActions {
  /** 读取「帧率上限」与「实验帧率调度」状态（面板打开时、点「↻」时调用） */
  static async readEngineReadout(runJs: (script: string) => Promise<string>): Promise<PanelEngineReadout> {
    const rawFrameRate = await runJs(JS_READ_FRAME_RATE);
    const frameRateLabel = frameRateText(toNumber(rawFrameRate)) ?? '未知';

    const rawScheduler = await runJs(JS_READ_SCHEDULER);
    const schedulerValue = toNumber(rawScheduler);
    const schedulerOn = Number.isFinite(schedulerValue) && schedulerValue >= 0;
    const schedulerFrameRateLabel = schedulerOn
      ? (frameRateText(schedulerValue) ?? '未知')
      : '已关闭';

    return {
      frameRateLabel: frameRateLabel,
      schedulerOn: schedulerOn,
      schedulerFrameRateLabel: schedulerFrameRateLabel
    };
  }

  /** 关闭「实验帧率调度」；返回是否写入成功（调用方负责重新加载页面与提示） */
  static async disableScheduler(runJs: (script: string) => Promise<string>): Promise<boolean> {
    const rawResult = await runJs(JS_DISABLE_SCHEDULER);
    return toNumber(rawResult) === 1;
  }

  /** 只查「实验帧率调度」是否开启（页面加载完成后的提示用） */
  static async isSchedulerOn(runJs: (script: string) => Promise<string>): Promise<boolean> {
    const rawResult = await runJs(JS_IS_SCHEDULER_ON);
    return toNumber(rawResult) === 1;
  }

  /** 把引擎上限与存档都设为「不限」；返回负载是否暴露了 setFrameRate */
  static async forceUnlimited(runJs: (script: string) => Promise<string>): Promise<boolean> {
    const rawResult = await runJs(JS_FORCE_UNLIMITED);
    return toNumber(rawResult) === 1;
  }

  /** 实测引擎帧率：间隔约 1 秒采样两次总帧数，返回 `'118 fps'` / `'不可用'` */
  static async measureFps(runJs: (script: string) => Promise<string>): Promise<string> {
    const first = toNumber(await runJs(JS_SAMPLE_TOTAL_FRAMES));
    if (!Number.isFinite(first) || first < 0) {
      return '不可用';
    }
    await new Promise<void>((resolve) => { setTimeout(() => { resolve(); }, 1000); });
    const second = toNumber(await runJs(JS_SAMPLE_TOTAL_FRAMES));
    if (!Number.isFinite(second) || second < first) {
      return '不可用';
    }
    return (second - first) + ' fps';
  }

  /** 打开 GP-Next 面板 */
  static async openGpNextPanel(runJs: (script: string) => Promise<string>): Promise<void> {
    await runJs(JS_OPEN_GP_NEXT_PANEL);
  }
}
