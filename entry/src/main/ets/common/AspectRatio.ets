/**
 * 画面比例约束（3:2 ~ 17:9）的纯计算。
 *
 * 从 `Index.ets` 的 `parseVp` / `applyAspectRatio` 里搬出来 —— 它们只做算术，不碰任何组件状态，
 * 所以放在 `common/`：页面只负责把结果写进 `@State`。
 *
 * 规则：
 *   · 太宽（> 17:9，如 20:9 / 21:9）：以高度为基准，宽度卡在 17:9，左右留黑边
 *   · 太方（< 3:2，如 4:3 / 7:5）：以宽度为基准，高度卡在 3:2，上下留黑边
 *   · 落在区间内：原样返回（相当于铺满）
 */

/** 最窄 3:2 ≈ 1.500 */
const MIN_ASPECT_W: number = 3;
const MIN_ASPECT_H: number = 2;
/** 最宽 17:9 ≈ 1.889 */
const MAX_ASPECT_W: number = 171;
const MAX_ASPECT_H: number = 90;

/** 比例计算的结果（单位 vp） */
export interface AspectLayout {
  width: number;
  height: number;
  /** 居中偏移 */
  x: number;
  y: number;
}

/**
 * 把 Area 的 Length 值安全转成 vp 数值。
 * 运行时该值可能是 `'720.00vp'` 这类带单位字符串，`Number()` 会得到 NaN 并污染布局，
 * 故用 parseFloat 兜底；解析失败返回 0，随后退化为 100% 铺满。
 */
export function parseVp(value: Length): number {
  const parsed = Number.parseFloat(value.toString());
  return Number.isNaN(parsed) ? 0 : parsed;
}

/**
 * 按 3:2 ~ 17:9 区间计算 Web 的目标尺寸与居中偏移。
 * 调用方需自行处理"铺满模式"与"尚未测量到容器尺寸"两种情况（那属于页面状态，不属于算术）。
 */
export function computeAspectLayout(containerW: number, containerH: number): AspectLayout {
  let targetW = containerW;
  let targetH = containerH;
  if (containerW * MAX_ASPECT_H > containerH * MAX_ASPECT_W) {
    // 太宽：> 17:9
    targetW = containerH * MAX_ASPECT_W / MAX_ASPECT_H;
  } else if (containerW * MIN_ASPECT_H < containerH * MIN_ASPECT_W) {
    // 太方：< 3:2
    targetH = containerW * MIN_ASPECT_H / MIN_ASPECT_W;
  }
  return {
    width: targetW,
    height: targetH,
    x: (containerW - targetW) / 2,
    y: (containerH - targetH) / 2
  };
}
