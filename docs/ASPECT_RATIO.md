# 游戏画面比例（宽高比）约束方案

> 本文档记录 Gardendless 鸿蒙版如何把游戏画面约束在 **3:2 ~ 17:9** 区间内、区间外留黑边，
> 以及如何调整区间与"铺满"开关。实现位置：`entry/src/main/ets/pages/Index.ets`。

---

## 1. 背景

- 游戏本体（Cocos Creator 3.8.4，位于 `entry/src/main/resources/rawfile/`）的
  **设计分辨率为 1024×640，即 16:10**：
  - 定义位置：`rawfile/src/settings.json` → `screen.designResolution`
    ```json
    "designResolution": { "width": 1024, "height": 640, "policy": 2 }
    ```
  - `policy: 2` 表示 Cocos 内部按 SHOW_ALL 适配（保持比例，**在 Canvas 内部**留黑边）。
- 壳层不再让 WebView 无脑铺满，而是按比例约束后居中；**四周黑边由壳层提供**
  （根 `Stack` 的黑色背景 + Web 居中），因此"黑边"出现在 Web 之外。

---

## 2. 约束规则（3:2 ~ 17:9）

设容器实测尺寸为 `w × h`（vp），目标尺寸 `targetW × targetH`：

| 条件 | 判定 | 处理 | 黑边 |
|:---|:---|:---|:---|
| `w/h > 171/90`（≈ 1.889） | **太宽**（20:9、21:9 等） | 以高度为基准，`targetW = h × 171/90` | 左右 |
| `w/h < 3/2`（= 1.5） | **太方 / 太高**（4:3、7:5 等） | 以宽度为基准，`targetH = w × 2/3` | 上下 |
| 其余 | 落在区间内 | 直接铺满 | 无 |

判定用**交叉相乘**而非除法，避免浮点误差：

```ts
if (w * MAX_ASPECT_H > h * MAX_ASPECT_W) {        // 太宽：> 17:9
  targetW = h * MAX_ASPECT_W / MAX_ASPECT_H;
} else if (w * MIN_ASPECT_H < h * MIN_ASPECT_W) { // 太方：< 3:2
  targetH = w * MIN_ASPECT_H / MIN_ASPECT_W;
}
```

Web 用 `.position()` 居中：`x = (w - targetW) / 2`、`y = (h - targetH) / 2`。

> 逻辑对齐安卓版 `AspectRatioFrameLayout.onMeasure`。安卓 v0.14.0 的区间是 **16:10 ~ 17:9**，
> 本工程把下限放宽到 **3:2**。

### 与 16:10 设计分辨率的关系（重要取舍）

游戏 Canvas 内部按 **16:10** 做 SHOW_ALL 适配，因此：

- 容器比 16:10 **更窄**（放到 3:2 = 1.5）→ 游戏在 Canvas 内部加**上下**黑边，
  画面实际占用降为 `1.5 / 1.6 = 93.75%`；
- 容器比 16:10 **更宽**（17:9）→ 游戏在内部加**左右**黑边。

即：下限放宽到 3:2 能让 **Web 视口更高**（GP-Next 等 HTML 面板可用空间变大），
但**游戏画面本身会变小**。若目标是"画面尽可能大"，下限应设 **16:10**。

---

## 3. 相关常量（`Index.ets` 顶部）

```ts
const MIN_ASPECT_W: number = 3;    // 最窄 3:2  ≈ 1.500
const MIN_ASPECT_H: number = 2;
const MAX_ASPECT_W: number = 171;  // 最宽 17:9 ≈ 1.889
const MAX_ASPECT_H: number = 90;
```

改这几个整数即可调整区间：

| 下限目标 | `MIN_ASPECT_W` | `MIN_ASPECT_H` |
|:---|:---:|:---:|
| **3:2（当前）** | 3 | 2 |
| 16:10（游戏原生，画面最大） | 160 | 100 |
| 4:3 | 4 | 3 |

上限同理（`MAX_ASPECT_W` / `MAX_ASPECT_H`）。

---

## 4. 容器尺寸来源：`onAreaChange`

```ts
.onAreaChange((_oldArea: Area, newArea: Area) => {
  const w = Number(newArea.width);
  const h = Number(newArea.height);
  if (w !== this.containerW || h !== this.containerH) {
    this.containerW = w;
    this.containerH = h;
    this.applyAspectRatio();
  }
})
```

**不用 `display.getDefaultDisplaySync()`**：它返回**全屏**尺寸，而本工程支持
`supportWindowMode: ["fullscreen", "split", "floating"]`；在小窗 / 分屏 / 2in1 窗口模式下
窗口小于屏幕，用 display 会让 Web 溢出窗口。`onAreaChange` 拿到的是容器实际尺寸，三种形态都正确。

首次回调前 `containerW/H` 为 0，此时 Web 先按 `100%` 铺满，测得尺寸后立即收敛到目标比例。

---

## 5. "铺满"开关与持久化

| 项 | 说明 |
|:---|:---|
| 状态 | `@State isFillScreen: boolean`，`true` 时 Web 铺满整屏（不约束比例） |
| 持久化 | `preferences`（`game_save` 库）键 `webview_fullscreen`，与安卓版 SharedPreferences 同名 |
| 切换方式 | **长按右下角的 GP-Next 按钮**，弹出「画面：铺满 / 画面：3:2 ~ 17:9 留边」提示 |
| 恢复时机 | `aboutToAppear()` 中读回该偏好 |

> 安卓版由游戏经 `GardendlessBridge` 桥接触发全屏切换；本工程目前提供手动开关。
> 若需网页侧驱动，可仿照安卓版注册 JS 代理（如 `GardendlessBridge.setFullscreen`）。

---

## 6. 注意事项

1. **黑边在 Web 之外**：触摸坐标映射不受影响（`touchPatch.js` 只处理 Web 内部坐标）；
   黑边区域不属于游戏视口，点不到游戏。
2. **尺寸变化会重排**：旋转屏幕 / 拖动窗口改变尺寸时 `onAreaChange` 会重算并调整 Web 尺寸，属预期行为。
3. **预览器**：`onAreaChange` 在预览器中可能不稳定，请在真机 / 模拟器验证。
4. **旧的 display 方案已废弃**：改用 `display` + `px2vp` 计算固定比例的写法见文档历史，
   不要再用。

---

## 7. 相关文件

| 文件 | 作用 |
|:---|:---|
| `entry/src/main/ets/pages/Index.ets` | 壳层：比例计算、居中布局、铺满开关 |
| `entry/src/main/resources/rawfile/src/settings.json` | 游戏设计分辨率（1024×640 = 16:10） |
| 安卓参考实现 | 第三方安卓工程中的 `AspectRatioFrameLayout.kt`（本仓库未纳入）；本工程的比例区间算法对齐其 `onMeasure` |
