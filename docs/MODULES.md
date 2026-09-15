# 模块说明

## 1. EntryAbility (`entryability/EntryAbility.ets`)

**职责**: 应用入口 Ability，管理应用生命周期和 WebView 引擎初始化。

| 生命周期方法 | 操作 |
|-------------|------|
| `onCreate()` | 初始化 ArkWeb 引擎：启用多进程模式、整页绘制（RENDER_SURFACE），设置 Web 存储内存上限（128MB） |
| `onWindowStageCreate()` | 设置全屏 + 横屏定向，注册内存压力回调，加载 `pages/Index` |
| `onMemoryLevel()` | 响应系统内存警告 |

**关键配置**:
```typescript
webview.WebviewController.setWebDebuggingAccess(true)    // 允许调试
webview.WebviewController.enableMultiprocess(true)      // 多进程隔离
webview.Web.SET_RENDER_MODE_WHOLE_PAGE_DRAWING(true)    // 全页渲染
webview.Web.WebStorage.setMaxStorageSize(128 * 1024 * 1024) // 128MB Web 存储
```

---

## 2. Index 主页面 (`pages/Index.ets`)

**职责**: 应用唯一页面，承载 WebView、资源拦截、数据持久化、文件下载、调试入口。

### WebView 配置

| 属性 | 值 | 说明 |
|------|---|------|
| `src` | `https://cocos.local/index.html` | 虚拟域名，由拦截器映射到 rawfile |
| `renderMode` | `ASYNC_RENDER` | 异步渲染模式 |
| `javaScriptAccess` | `true` | 启用 JS 执行 |
| `domStorageAccess` | `true` | 启用 DOM 存储 |
| `mediaPlayGestureAccess` | `false` | 允许自动播放（绕过手势限制） |
| `enableWebAVSession` | `false` | 关闭音视频会话 |

### 资源拦截 (`onInterceptRequest`)

```typescript
URL: https://cocos.local/{rawfilePath}
     → decodeURIComponent
     → $rawfile(rawFilePath)
     → WebResourceResponse (MIME type 根据扩展名)
```

支持的 MIME 类型: `html`, `js`, `wasm`, `json`, `css`, `png`, `jpg/jpeg`, `webp`, `svg`, `data`

### 数据持久化

- **Preferences 键值对**: 通过 JS 代理 `NativeStorage` 暴露 `saveToNative(key, value)` / `loadFromNative(key)` 给 WebView
- **Cookie**: `onPageEnd` 时调用 `WebCookieManager.saveCookieAsync()`
- **画面"铺满"偏好**: `preferences`（`game_save` 库）键 `webview_fullscreen`，见"画面比例约束"
- **文件下载**: 见下方"下载流程"

### 画面比例约束（3:2 ~ 17:9）

Web 不再铺满整屏，而是按比例约束后居中，四周黑边由根 `Stack` 的黑色背景提供：

```typescript
applyAspectRatio()   // 由根 Stack 的 onAreaChange 触发
├── w/h > 171/90（> 17:9，如 20:9）→ 以高度为基准，宽度卡 17:9，左右留黑边
├── w/h < 3/2（< 3:2，如 4:3）    → 以宽度为基准，高度卡 3:2，上下留黑边
└── 落在区间内                    → 铺满
```

- 容器尺寸取自 `onAreaChange` 实测值，**不用 `display`**：小窗 / 分屏 / 2in1 窗口模式下同样正确。
- `@State isFillScreen` 为 `true` 时跳过约束、直接铺满；**长按 GP-Next 按钮**可切换并持久化。
- 详细规则、常量与取舍说明见 [ASPECT_RATIO.md](./ASPECT_RATIO.md)。

### 下载流程

```typescript
setupDownloadDelegate()
├── onBeforeDownload → 获取文件名 → FilePickerHelper.selectSavePath() → 下载到 cacheDir 临时文件
├── onDownloadUpdated → 更新下载进度百分比
├── onDownloadFailed → 清理临时文件
└── onDownloadFinish → 复制临时文件到用户选择路径
    ├── 正常: fs.copyFileSync(tempPath → savePath)
    ├── 目录错误: 自动拼接文件名后重试
    └── fallback: 复制失败则保存到 filesDir 备用
```

### GP-Next 入口按钮

**可见按钮**，贴在画面**右下角**（`Alignment.BottomEnd`），默认 44×44 vp、半透明黑底白字圆形，
标注 `GP`，点击时按以下顺序切换 GP-Next 面板显隐：

1. `window.gpNext.toggle()` —— payload 真实暴露的 API
   （`index-lw1dPoCM.js` 挂载 `window.gpNext = { toggle, show, hide, ... }`，**没有 `open` 方法**）
2. `window.gpNext.open()` —— 兼容其他 / 旧版本
3. `window.Zt()` —— 兼容旧壳层写法
4. 派发 `F9` 按键事件 —— GP-Next 的默认热键
   （`gp-next-settings` 的 `overlayHotkey` 默认 `{ key:'F9', code:'F9', 无修饰键 }`）

> 尺寸与边距由 `Index.ets` 顶部常量 `GP_BUTTON_SIZE` / `GP_BUTTON_MARGIN` 控制。
> **长按该按钮**可切换"铺满 / 3:2 ~ 17:9 留边"并记住选择（见"画面比例约束"）。
> **无操作一段时间后自动贴边隐藏**：延迟由 `GP_BUTTON_HIDE_DELAY`（默认 4000 ms）控制，
> 隐藏时向右移出屏幕、只保留 `GP_BUTTON_SLIVER`（默认 16 vp）宽度可点，不透明度降到 0.45，带 220 ms 过渡；
> 隐藏态下**单击 / 长按先唤出**（不执行动作），唤出后重新计时；任何与按钮的交互都会重置计时。
> 该按钮为 `Stack` 的叠加子节点，只占用自身命中区域，其余区域的触摸仍由 `Web` 接收；
> 顶部的下载/加载状态提示额外设置了 `HitTestMode.Transparent`，同样不拦截游戏操作。
> 注意：热键可在面板设置里改（存于 `gp-next-settings`）；改后第 4 级失效，前三级不受影响。

---

## 3. FilePickerHelper (`pages/FilePickerHelper.ets`)

**职责**: 封装 `DocumentViewPicker.save()`，让用户选择文件保存路径。

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `constructor(context)` | `UIAbilityContext` | — | 保存 Context 引用 |
| `selectSavePath(fileName)` | `string` | `Promise<string>` | 打开系统文件选择器，返回用户选择的 URI（含文件名拼接策略） |

**内部逻辑**:
1. 调用 `DocumentViewPicker.save({ newFileNames: fileName })` 
2. 监听权限错误（code 13900001）返回空字符串表示取消
3. 拼接用户选择的目录 + 文件名

---

## 4. ResourceManager (`utils/ResourceManager.ets`)

**职责**: LRU 缓存管理器（单例），提供资源预加载、并发控制、智能清理。

| 特征 | 说明 |
|------|------|
| 缓存上限 | 100 项 |
| 单文件上限 | 50MB |
| 清理阈值 | 80%（缓存数达上限时触发） |
| 优先级评分 | 综合频率、大小、类型、时间衰减 |
| 并发控制 | `maxConcurrent: 5` |
| 预加载 | 支持批量预加载 + 超时/重试 |

**关键方法**:
- `getInstance()` — 获取单例
- `get(key)` — 获取缓存项
- `set(key, value, size)` — 写入缓存
- `preload(urls)` — 批量预加载
- `getStats()` — 获取缓存统计

---

## 5. PerformanceMonitor (`utils/PerformanceMonitor.ets`)

**职责**: 性能监控单例，跟踪 FPS、内存、渲染耗时、缓存命中率。

| 指标 | 阈值 | 说明 |
|------|------|------|
| FPS | < 30 告警 | 帧率监控 |
| 内存 | > 200MB 告警 | 内存使用监控 |
| 渲染耗时 | > 16ms 告警 | 单帧渲染超时 |
| 缓存命中率 | — | 跟踪 ResourceManager 效率 |

**关键方法**:
- `getInstance()` — 获取单例
- `start(interval)` — 开始监控（默认 5s 采样间隔）
- `stop()` — 停止监控
- `getReport()` — 导出 JSON 报告
- `onCacheHit/miss()` — 缓存命中/未命中计数

---

## 6. EntryBackupAbility (`entrybackupability/EntryBackupAbility.ets`)

**职责**: 备份恢复扩展 Ability，提供 `onBackup()` 和 `onRestore()` 生命周期钩子，配合 HarmonyOS 备份框架使用。当前为空实现（stub）。

---

## 依赖关系图

```
Index.ets
├── EntryAbility.ets (加载此页面)
├── FilePickerHelper.ets (下载文件选择)
├── @kit.ArkWeb (WebView, WebCookieManager, WebDownloadDelegate)
├── @kit.AbilityKit (UIAbilityContext)
├── @ohos.data.preferences (键值对持久化)
├── @ohos.file.fs (文件操作)
├── ResourceManager.ets (独立工具，可用于缓存优化)
└── PerformanceMonitor.ets (独立工具，可用于性能监控)
```

> **注意**: `ResourceManager` 和 `PerformanceMonitor` 目前为独立工具类，未在 `Index.ets` 中集成。如需启用资源缓存和性能监控，需在 `Index.ets` 中实例化并挂钩。
