import {
  PANEL_FS_TITLE, PANEL_FS_SECTION, PANEL_FS_BUTTON, PANEL_FS_VALUE, PANEL_FS_HINT,
  PANEL_C_PRIMARY, PANEL_C_SECONDARY, PANEL_C_SECTION, PANEL_C_WARN,
  PANEL_C_ACCENT, PANEL_C_BTN, PANEL_C_DANGER, PANEL_C_CARD, PANEL_C_MASK,
  PANEL_GAP_SECTION, PANEL_GAP_TITLE, PANEL_GAP_HINT
} from '../common/PanelStyle';

/**
 * 壳层设置面板（长按 GP 按钮打开）。
 *
 * 设计约定：**本组件只负责画和转发点击**，不持有任何业务状态、不做读写。
 * 所有显示值由父组件算好后通过 @Prop 传入（含已拼好的状态行文案），
 * 所有动作通过回调交回父组件执行 —— 这样刷新率投票/帧率读取等逻辑仍集中在 Index 一处。
 */
@Component
export struct SettingsPanel {
  // —— 显示值（父组件传入） ——
  @Prop isFillScreen: boolean = true;
  @Prop expectedRefresh: string = '120';
  @Prop statusLine: string = '';        // 例：当前 120 Hz ｜ 期望 120 ｜ 生效中 ✓
  @Prop supportedText: string = '';     // 例：屏幕档位：30 / 60 / 90 / 120 / 144 Hz
  @Prop engineFrameRate: string = '—';  // 帧率上限
  @Prop engineFpsMeasured: string = '—'; // 实测（引擎循环帧数）
  @Prop schedulerFrameRate: string = '已关闭';
  @Prop frameSchedulerOn: boolean = false;

  // —— 动作（父组件实现） ——
  onClose: () => void = () => { };
  onToggleFill: () => void = () => { };
  onPickRefresh: (value: string) => void = () => { };
  onRefreshEngine: () => void = () => { };
  onForceUnlimited: () => void = () => { };
  onOpenGpNext: () => void = () => { };
  onDisableScheduler: () => void = () => { };

  /** 单个刷新率按钮（M11：复用；只接收常量参数，选中态通过 this 读取状态） */
  @Builder
  rateButton(label: string, value: string) {
    Button(label)
      .fontSize(PANEL_FS_BUTTON)
      .backgroundColor(this.expectedRefresh === value ? PANEL_C_ACCENT : PANEL_C_BTN)
      .layoutWeight(1)
      .onClick(() => { this.onPickRefresh(value); })
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          // ── 标题行 ──
          Row() {
            Text('设置')
              .fontSize(PANEL_FS_TITLE)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
              .layoutWeight(1)
            Button('✕')
              .fontSize(PANEL_FS_BUTTON)
              .fontColor('#CFCFD6')
              .backgroundColor(PANEL_C_BTN)
              .width(34)
              .height(34)
              .accessibilityText('关闭设置')
              .onClick(() => { this.onClose(); })
          }
          .width('100%')
          .margin({ bottom: PANEL_GAP_SECTION })

          // ── 画面 ──
          Text('画面')
            .fontSize(PANEL_FS_SECTION)
            .fontColor(PANEL_C_SECTION)
            .width('100%')
            .margin({ bottom: PANEL_GAP_TITLE })
          Row({ space: 8 }) {
            Button(this.isFillScreen ? '铺满 ✓' : '铺满')
              .fontSize(PANEL_FS_BUTTON)
              .backgroundColor(this.isFillScreen ? PANEL_C_ACCENT : PANEL_C_BTN)
              .layoutWeight(1)
              .accessibilityText('画面铺满')
              .onClick(() => {
                if (!this.isFillScreen) {
                  this.onToggleFill();
                }
              })
            Button(!this.isFillScreen ? '留边 ✓' : '留边')
              .fontSize(PANEL_FS_BUTTON)
              .backgroundColor(!this.isFillScreen ? PANEL_C_ACCENT : PANEL_C_BTN)
              .layoutWeight(1)
              .accessibilityText('画面按比例留边')
              .onClick(() => {
                if (this.isFillScreen) {
                  this.onToggleFill();
                }
              })
          }
          .width('100%')
          .margin({ bottom: PANEL_GAP_HINT })
          Text('留边：按 3:2 ~ 19:10 比例显示，四周留黑边（不拉伸画面）')
            .fontSize(PANEL_FS_HINT)
            .fontColor(PANEL_C_SECONDARY)
            .width('100%')
            .margin({ bottom: PANEL_GAP_SECTION })

          // ── 期望刷新率 ──
          Text('期望刷新率')
            .fontSize(PANEL_FS_SECTION)
            .fontColor(PANEL_C_SECTION)
            .width('100%')
            .margin({ bottom: PANEL_GAP_TITLE })
          Row({ space: 6 }) {
            // M11：四个按钮形状完全相同，抽成 @Builder 复用。
            // 注意（官方文档）：@Builder 按值传参时，状态变量变化**不会**刷新其内部 UI，
            // 所以这里只传常量（label/value），选中态用 this.expectedRefresh 读取。
            this.rateButton('关闭', 'off')
            this.rateButton('60', '60')
            this.rateButton('120', '120')
            this.rateButton('最高', 'max')
          }
          .width('100%')
          .margin({ bottom: PANEL_GAP_TITLE })
          Text(this.statusLine)
            .fontSize(PANEL_FS_VALUE)
            .fontColor(PANEL_C_PRIMARY)
            .width('100%')
          Text(this.supportedText)
            .fontSize(PANEL_FS_HINT)
            .fontColor(PANEL_C_SECTION)
            .width('100%')
            .margin({ top: 2 })
          Text('这是向系统声明期望帧率（不是锁帧）。若只在触摸/操作时才到 120（松手几秒回落），先把「系统设置 → 显示和亮度 → 屏幕刷新率」改成"高"；若设为"高"后仍无效，则是本机系统策略不接受该声明（实测：平板有效，手机 BRA-AL00 无效）。')
            .fontSize(PANEL_FS_HINT)
            .fontColor(PANEL_C_SECONDARY)
            .width('100%')
            .margin({ top: PANEL_GAP_HINT, bottom: PANEL_GAP_SECTION })

          // ── 引擎帧率 ──
          Text('引擎帧率（GP-Next）')
            .fontSize(PANEL_FS_SECTION)
            .fontColor(PANEL_C_SECTION)
            .width('100%')
            .margin({ bottom: PANEL_GAP_TITLE })
          Row({ space: 8 }) {
            Column() {
              Text('帧率上限 ' + this.engineFrameRate + ' ｜ 实验调度 ' + this.schedulerFrameRate
                + ((this.frameSchedulerOn ? ' ⚠' : '')))
                .fontSize(PANEL_FS_VALUE)
                .fontColor(PANEL_C_PRIMARY)
                .width('100%')
              Text('实测 ' + this.engineFpsMeasured + '（引擎循环帧数，可能高于屏幕实际刷新率）')
                .fontSize(PANEL_FS_HINT)
                .fontColor(PANEL_C_SECTION)
                .width('100%')
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            Button('↻')
              .fontSize(PANEL_FS_BUTTON)
              .backgroundColor(PANEL_C_BTN)
              .width(38)
              .onClick(() => { this.onRefreshEngine(); })
            Button('设为不限')   // 兜底：若「实测」确实被限在某个值，用它直接向引擎请求不限
              .fontSize(PANEL_FS_BUTTON)
              .backgroundColor(PANEL_C_BTN)
              .onClick(() => { this.onForceUnlimited(); })
            Button('打开 GP-Next 设置')
              .fontSize(PANEL_FS_BUTTON)
              .backgroundColor(PANEL_C_BTN)
              .onClick(() => { this.onOpenGpNext(); })
          }
          .width('100%')
          .margin({ bottom: PANEL_GAP_HINT })
          Text('游戏内「无限制」生效与否看「实测」；GP-Next「性能」页的「目标FPS」在无限制时会显示存档旧值，不可信。')
            .fontSize(PANEL_FS_HINT)
            .fontColor(PANEL_C_SECONDARY)
            .width('100%')
            .margin({ bottom: PANEL_GAP_SECTION })
          if (this.frameSchedulerOn) {
            Text('⚠ 检测到「实验帧率调度」已开启：上游用纯 JS 节拍器接管帧循环，在平板上会造成明显卡顿，建议关闭。')
              .fontSize(PANEL_FS_HINT)
              .fontColor(PANEL_C_WARN)
              .width('100%')
              .margin({ bottom: PANEL_GAP_HINT })
            Button('关闭「实验帧率调度」（会重新加载页面）')
              .fontSize(PANEL_FS_BUTTON)
              .backgroundColor(PANEL_C_DANGER)
              .width('100%')
              .margin({ bottom: PANEL_GAP_SECTION })
              .onClick(() => { this.onDisableScheduler(); })
          }

          // ── 完成 ──
          Button('完成')
            .fontSize(PANEL_FS_BUTTON)
            .backgroundColor(PANEL_C_ACCENT)
            .width('100%')
            .onClick(() => { this.onClose(); })
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: '76%' })
      .width('84%')
      .padding(20)
      .backgroundColor(PANEL_C_CARD)
      .borderRadius(16)
      .onClick(() => { })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(PANEL_C_MASK)
    .onClick(() => { this.onClose(); })
  }
}
