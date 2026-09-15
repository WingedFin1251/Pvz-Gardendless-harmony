# 模块说明

## 1. EntryAbility (`entryability/EntryAbility.ets`)

**职责**: 应用入口 Ability，管理应用生命周期和 WebView 引擎初始化。

| 生命周期方法 | 操作 |
|-------------|------|
| `onCreate()` | 初始化 ArkWeb 引擎：启用多进程模式、整页绘制（RENDER_SURFACE），设置 Web 存储内存上限（128MB） |
| `onWindowStageCreate()` | 先加载 `pages/Index`，再设置全屏 + 横屏定向（官方要求 `setWindowBackgroundColor()` 在 `loadContent()` 生效后调用，原实现并发存在竞态），注册内存压力回调 |
| `onMemoryLevel()` | 响应系统内存警告 |

**关键配置**:
```typescript
webview.WebviewController.setWebDebuggingAccess(true)    // 允许调试
webview.WebviewController.enableMultiprocess(true)      // 多进程隔离
webview.Web.SET_RENDER_MODE_WHOLE_PAGE_DRAWING(true)    // 全页渲染
webview.Web.WebStorage.setMaxStorageSize(128 * 1024 * 1024) // 128MB Web 存储
```

**设备类型分流（2in1）**: 顶部 `IS_2IN1 = deviceInfo.deviceType === TYPE_2IN1`。
`setWindowSystemBarEnable()` / `setPreferredOrientation()` 在 2in1（自由窗口、无传感器旋转）上
「不生效也不报错」，故 2in1 分支改用 `maximize()`（默认进入沉浸式全屏）并跳过方向设置；
竖屏锁定由 `module.json5` 的 `"orientation": "landscape"` 声明保证。
这类多设备告警用 `// @SuppressWarnings syscap`（注释形式只作用于紧邻的下一行语句）屏蔽。

---

## 2. Index 主页面 (`pages/Index.ets`)

**职责**: 应用唯一页面，承载 WebView、资源拦截、数据持久化、文件下载、画面比例约束。

### WebView 配置

| 属性 | 值 | 说明 |
|------|---|------|
| `src` | `https://cocos.local/index.html` | 虚拟域名，由拦截器映射到 rawfile |
| `renderMode` | `ASYNC_RENDER` | 异步渲染模式 |
| `javaScriptAccess` | `true` | 启用 JS 执行 |
| `domStorageAccess` | `true` | 启用 DOM 存储 |
| `mediaPlayGestureAccess` | `false` | 允许自动播放（绕过手势限制） |
| `enableWebAVSession` | `false` | 关闭音视频会话 |

### 画面比例约束（3:2 ~ 17:9）

| 项 | 说明 |
|------|------|
| 常量 | `MIN_ASPECT_W/H = 3/2`、`MAX_ASPECT_W/H = 171/90`，交叉相乘判定避免浮点误差 |
| 容器尺寸 | `onAreaChange` 实测（小窗 / 分屏 / 2in1 均正确），`parseVp` 兜底带单位字符串 |
| 布局 | Web 用 `.width/.height/.position()` 居中；四周黑边由根 `Stack` 的黑色背景提供 |
| 详细说明 | 见 `docs/ASPECT_RATIO.md` |

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
- **文件下载**: 见下方"下载流程"

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

### 隐形 GP-Next 调试按钮（已移除）

早期版本在 `(0, 0)` 放了一个 30×30 透明按钮，点击时依次尝试 `window.gpNext.open()`、
`window.Zt()`、模拟 `F10` 按键事件来打开 GP-Next 面板。

本仓库的 payload（`rawfile/`）中不存在任何 `gpNext` 挂载点（全目录 grep 无命中），
该按钮恒为死代码，并且会吞掉画面左上角 30×30 区域的游戏点击，故在壳层改进中删除。
若后续要接入 GP-Next（面板 + 入口按钮），做法可参考带 GP-Next 的变体发行版：
右下角可见按钮 + 无操作自动贴边隐藏 + `F9` 兜底热键。

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
