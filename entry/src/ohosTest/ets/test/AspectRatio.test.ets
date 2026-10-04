import { describe, it, expect } from '@ohos/hypium';
import { parseVp, computeAspectLayout } from '../../../main/ets/common/AspectRatio';

/**
 * 比例布局的纯函数单测（M15）。
 * 这些逻辑原先只能靠"装到真机上看画面"来验证 —— 现在可以在设备上跑 aa test 自动回归。
 * 数值依据：区间为 3:2(1.5) ~ 19:10(1.9)，纯计算见 common/AspectRatio.ets。
 */
export default function aspectRatioTest() {
  describe('AspectRatio', () => {
    it('parseVp_accepts_number_and_unit_string', 0, () => {
      expect(parseVp(720)).assertEqual(720);
      // 运行时 Length 常常是 '720.00vp' 这类带单位字符串，Number() 会得到 NaN 并污染布局
      expect(parseVp('720.00vp')).assertEqual(720);
      // 解析失败必须退化为 0（随后布局回落成 100% 铺满），不能返回 NaN
      expect(parseVp('abc')).assertEqual(0);
    });

    it('computeAspectLayout_wide_screen_letterboxes_sides', 0, () => {
      // 2222x1000 = 2.22 > 1.9 ⇒ 太宽：以高度为基准，宽度卡在 19:10，左右留黑边
      const layout = computeAspectLayout(2222, 1000);
      const expectedWidth = 1000 * 19 / 10;
      expect(Math.abs(layout.width - expectedWidth) < 0.01).assertTrue();
      expect(layout.height).assertEqual(1000);
      expect(Math.abs(layout.x - (2222 - expectedWidth) / 2) < 0.01).assertTrue();
      expect(layout.y).assertEqual(0);
    });

    it('computeAspectLayout_square_screen_letterboxes_top_bottom', 0, () => {
      // 1200x900 = 1.33 < 1.5 ⇒ 太方：以宽度为基准，高度卡在 3:2，上下留黑边
      const layout = computeAspectLayout(1200, 900);
      expect(layout.width).assertEqual(1200);
      expect(Math.abs(layout.height - 1200 * 2 / 3) < 0.01).assertTrue();
      expect(layout.x).assertEqual(0);
      expect(Math.abs(layout.y - (900 - 800) / 2) < 0.01).assertTrue();
    });

    it('computeAspectLayout_in_range_uses_full_size', 0, () => {
      // 1600x1000 = 1.6 落在 [1.5, 1.9] 内 ⇒ 不约束，原样铺满
      const layout = computeAspectLayout(1600, 1000);
      expect(layout.width).assertEqual(1600);
      expect(layout.height).assertEqual(1000);
      expect(layout.x).assertEqual(0);
      expect(layout.y).assertEqual(0);
    });
  });
}