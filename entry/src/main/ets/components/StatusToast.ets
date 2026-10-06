/**
 * 顶部状态提示条（叠加在画面顶部）。
 *
 * 纯展示组件：不持有状态、不处理点击 —— `message` / `opacity` / 进度都由父组件给。
 * 放行触摸（`HitTestMode.Transparent`），避免盖住游戏操作区。
 */
@Component
export struct StatusToast {
  /** 提示文字；空串时不显示 */
  @Prop message: string = '';
  /** 淡出用的不透明度 */
  @Prop statusOpacity: number = 1;
  /** 是否处于加载中（与 progress 一起决定是否显示进度条） */
  @Prop loading: boolean = false;
  /** 加载进度 0~100 */
  @Prop progress: number = 0;

  build() {
    Column() {
      if (this.message) {
        Text(this.message)
          .fontSize(14)
          // 固定深色半透明 + 白字：不随主题变化，深/浅色模式下都清晰
          .fontColor($r('app.color.toast_text'))
          .padding(8)
          .backgroundColor($r('app.color.toast_bg'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .opacity(this.statusOpacity)
          .animation({ duration: 300, curve: Curve.Linear })
      }

      if (this.loading && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%').height(4).color($r('app.color.progress_bar'))
      }
    }
    .width('100%')
    .position({ x: 0, y: 0 })
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
