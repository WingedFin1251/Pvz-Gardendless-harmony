# 游戏画面比例（宽高比）修改记录

> 本文档记录 Gardendless 鸿蒙版如何实现**固定宽高比 + 留黑边**的方案，
> 以及如何调整比例（例如 16:10 ↔ 16:9）。

---

## 1. 背景

- 游戏本体（Cocos Creator 3.8.4，位于 `entry/src/main/resources/rawfile/`）的
  **设计分辨率为 1024×640，即 16:10**。
  - 定义位置：`rawfile/src/settings.json` → `screen.designResolution`
    ```json
    "designResolution": { "width": 1024, "height": 640, "policy": 2 }
    ```
  - `policy: 2` 表示 Cocos 内部按 SHOW_ALL 适配（保持比例、留内部黑边）。
- 若壳层 WebView 直接铺满屏幕（`.width('100%').height('100%')`），
  游戏画面会按 Cocos 策略自适应，**不同屏幕比例下观感不一致**。
- 参考安卓版做法（原参考工程 `gardendless-android-main` 已从本仓库移除）：**壳层强制固定宽高比**，
  游戏区域居中，四周由黑色背景填充（黑边），保证任何设备上画面比例一致。

> 注意：安卓版当前写死 **16:9**（与游戏 16:10 设计分辨率不一致，会有内部缩放）；
> 鸿蒙版建议使用游戏原生 **16:10**。

---

## 2. 方案原理（与安卓版一致）

安卓版 `GameActivity.kt` 的核心逻辑（自定义 FrameLayout 重写 onMeasure）：

```kotlin
if (screenWidth * H > screenHeight * W) {
    // 屏幕更宽（比例 > W:H）→ 以高度为基准，左右留黑边
    targetWidth = screenHeight * W / H
} else {
    // 屏幕更方（比例 < W:H）→ 以宽度为基准，上下留黑边
    targetHeight = screenWidth * H / W
}
```

鸿蒙版 `Index.ets` 用同样的数学逻辑，只是把"容器测量"换成了"先算好 vp 尺寸，
再用 Stack 居中"。

---

## 3. 鸿蒙版具体改动（`entry/src/main/ets/pages/Index.ets`）

### 3.1 常量定义（文件顶部）

```typescript
// 游戏设计分辨率 1024×640 = 16:10（与 gardendless-android-main 相同的固定宽高比留边方案）
const GAME_ASPECT_W = 16;
const GAME_ASPECT_H = 10;
```

> 改成 16:9 时：`const GAME_ASPECT_W = 16; const GAME_ASPECT_H = 9;`

### 3.2 导入 display 模块

```typescript
import { display } from '@kit.ArkUI';
```

### 3.3 状态变量

```typescript
@State webBoxWidth: number = 0;   // 游戏区域宽度 (vp)
@State webBoxHeight: number = 0;  // 游戏区域高度 (vp)
```

### 3.4 在 `aboutToAppear()` 中计算目标尺寸

```typescript
async aboutToAppear() {
  // 计算固定比例游戏区域（与安卓版 onMeasure 逻辑一致）：
  // 屏幕更宽(比例>W:H) → 以高度为基准，左右留黑边；屏幕更方 → 以宽度为基准，上下留黑边
  // display 返回 px，需经 UIContext.px2vp 转成 vp 才能用于 .width()/.height()
  const screen = display.getDefaultDisplaySync();
  const screenWidth = this.getUIContext().px2vp(screen.width);
  const screenHeight = this.getUIContext().px2vp(screen.height);
  if (screenWidth * GAME_ASPECT_H > screenHeight * GAME_ASPECT_W) {
    this.webBoxWidth = screenHeight * GAME_ASPECT_W / GAME_ASPECT_H;
    this.webBoxHeight = screenHeight;
  } else {
    this.webBoxWidth = screenWidth;
    this.webBoxHeight = screenWidth * GAME_ASPECT_H / GAME_ASPECT_W;
  }

  // ...原有初始化逻辑
}
```

### 3.5 布局改造（`build()`）

把原来的 `Column`（Web 直接 100%×100%）改为：

```typescript
build() {
  Stack({ alignContent: Alignment.TopStart }) {
    // 游戏区域容器：黑底 + 固定宽高比居中（四周留黑边）
    Stack() {
      Web({ src: "https://cocos.local/index.html",
        controller: this.webController,
        renderMode: RenderMode.ASYNC_RENDER
      })
        .width(this.webBoxWidth)
        .height(this.webBoxHeight)
        .backgroundColor(Color.Black)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .mediaPlayGestureAccess(false)
        .enableWebAVSession(false)
        .overviewModeAccess(false)
        .zoomAccess(false)
        .verticalScrollBarAccess(false)
        // ...原有 Web 回调（onControllerAttached / onPageEnd / onInterceptRequest / onLoadIntercept 等）
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center) // 游戏区域居中，四周留黑边
    .backgroundColor(Color.Black)   // 黑边背景

    // 顶部覆盖层：状态提示 + 加载进度（保持原顶部堆叠行为）
    Column() {
      if (this.downloadStatus) { /* 原 Text */ }
      if (this.isLoading && this.progress < 100) { /* 原 Progress */ }
    }
    .width('100%')

    Button() // 原调试按钮，保持 .position({x:0,y:0})
  }
  .width('100%')
  .height('100%')
  .padding(0)
  .margin(0)
}
```

---

## 4. 调整比例（改数字即可）

| 目标比例 | `GAME_ASPECT_W` | `GAME_ASPECT_H` | 说明 |
|:---|:---:|:---:|:---|
| **16:10**（推荐，游戏原生） | 16 | 10 | 与 1024×640 设计分辨率完全一致，无内部缩放 |
| 16:9 | 16 | 9 | 与安卓版一致（安卓版当前即此值） |
| 4:3 | 4 | 3 | 老式屏幕 |
| 1:1 | 1 | 1 | 方形 |

只需修改常量，其余逻辑自动生效。

---

## 5. 注意事项

1. **px2vp 转换必须保留**：`display.getDefaultDisplaySync()` 返回的是物理像素 (px)，
   而 ArkUI 的 `.width()`/`.height()` 默认单位是 vp。不转换会导致尺寸错误。
2. **小窗 / 分屏模式**：`display` 返回全屏尺寸；应用开启
   `supportWindowMode: ["fullscreen", "split", "floating"]` 时，
   小窗下 Web 可能溢出窗口。如需精确适配小窗，可改用
   `onAreaChange` 监听窗口实际尺寸后重新计算。
3. **黑边在 Web 组件外部**：触摸坐标映射不受影响（`touchPatch.js` 只处理 Web 内部坐标）。
4. **预览器**：`display` 在预览器中可能返回不准确值，请在真机/模拟器验证。

---

## 6. 相关文件

| 文件 | 作用 |
|:---|:---|
| `entry/src/main/ets/pages/Index.ets` | 鸿蒙壳层：比例计算 + 布局 |
| `entry/src/main/resources/rawfile/src/settings.json` | 游戏设计分辨率（1024×640） |
| ~~`gardendless-android-main/app/src/main/java/com/fct/gardendless/GameActivity.kt`~~ | 安卓版参考实现（16:9），该工程已从仓库移除 |
