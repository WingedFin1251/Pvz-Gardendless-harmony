/** GP 入口按钮（单位 vp）：改这两个值即可调整按钮大小与距右下角的留白 */
const GP_BUTTON_SIZE: number = 44;
const GP_BUTTON_MARGIN: number = 12;
/** 贴边隐藏后仍留在屏幕内、可见且可点的宽度（vp） */
const GP_BUTTON_SLIVER: number = 26;
/** 隐藏态额外的触摸容差（vp）：把命中区域向屏幕内扩展，缓解贴边后不好点（可见态不扩展） */
const GP_BUTTON_TOUCH_PAD: number = 10;

/**
 * 右下角的 GP 悬浮按钮（GP-Next 面板入口 + 长按打开壳层设置）。
 *
 * 只负责**外观与手势**：「隐藏态先唤出 / 重新计时 / 打开谁」都由父组件在回调里决定 ——
 * 这样"隐藏"这份状态仍然只由页面持有，组件不产生第二份真相。
 */
@Component
export struct GpFloatingButton {
  /** 是否处于贴边隐藏态（由页面持有） */
  @Prop hidden: boolean = false;
  /** 单击（页面决定：先唤出还是打开 GP-Next 面板） */
  onShortPress: () => void = () => { };
  /** 长按（页面决定：先唤出还是打开壳层设置面板） */
  onLongPress: () => void = () => { };

  /** 命中区域：隐藏态向屏幕内扩展，补偿贴边后可见面积小、不好点 */
  private computeResponseRegion(): Rectangle {
    const pad = this.hidden ? GP_BUTTON_TOUCH_PAD : 0;
    return { x: -pad, y: -pad, width: GP_BUTTON_SIZE + pad * 2, height: GP_BUTTON_SIZE + pad * 2 };
  }

  build() {
    Button('GP', { type: ButtonType.Circle, stateEffect: true })
      .width(GP_BUTTON_SIZE)
      .height(GP_BUTTON_SIZE)
      .backgroundColor($r('app.color.float_button_bg'))
      .fontColor(Color.White)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .borderWidth(1)
      .borderColor($r('app.color.float_button_border'))
      .margin({ right: GP_BUTTON_MARGIN, bottom: GP_BUTTON_MARGIN })
      // 贴边隐藏：向右移出屏幕，只留 GP_BUTTON_SLIVER 宽度可点；同时降低不透明度
      .translate({ x: this.hidden ? (GP_BUTTON_MARGIN + GP_BUTTON_SIZE - GP_BUTTON_SLIVER) : 0 })
      .opacity(this.hidden ? 0.45 : 1)
      .responseRegion(this.computeResponseRegion())
      .accessibilityText('打开 GP-Next 面板（长按打开设置）')
      .gesture(LongPressGesture().onAction(() => {
        this.onLongPress();
      }))
      .onClick(() => {
        this.onShortPress();
      })
  }
}
