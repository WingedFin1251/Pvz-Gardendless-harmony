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
「不生效也不报错」，故 2in1 分支改用**普通最大化**并跳过方向设置：

```ts
await mainWindow.setWindowLayoutFullScreen(false);                    // 布局避让系统栏（任务栏）
await mainWindow.maximize(window.MaximizePresentation.EXIT_IMMERSIVE); // 最大化但不进入沉浸式全屏
```

**为什么必须显式传 `EXIT_IMMERSIVE`**：`maximize()` 不传参时默认是 `ENTER_IMMERSIVE`，即「最大化 + 进入全屏」——鸿蒙电脑上实测全屏会把显示边缘吞掉一点点，而普通最大化（保留任务栏）完全正常。手机/平板分支不变，仍是沉浸式布局 + 隐藏状态栏/导航栏。
竖屏锁定由 `module.json5` 的 `"orientation": "landscape"` 声明保证。
这类多设备告警用 `// @SuppressWarnings syscap`（注释形式只作用于紧邻的下一行语句）屏蔽。

---

## 2. Index 主页面 (`pages/Index.ets`)

**职责**: 应用唯一页面，承载 WebView、资源拦截、数据持久化、文件下载、画面比例约束。

### WebView 配置

| 属性 | 值 | 说明 |
|------|---|------|
| `src` | `https://cocos.local/game/index.html` | 虚拟域名，由拦截器映射到 `rawfile/game/` |
| `renderMode` | `ASYNC_RENDER` | 异步渲染模式 |
| `javaScriptAccess` | `true` | 启用 JS 执行 |
| `domStorageAccess` | `true` | 启用 DOM 存储 |
| `mediaPlayGestureAccess` | `false` | 允许自动播放（绕过手势限制） |
| `enableWebAVSession` | `false` | 关闭音视频会话 |
| `javaScriptOnDocumentStart` | `[{ script: injectedScript }]` | document-start 注入触摸补丁（`touchPatch.js` 内容在 `aboutToAppear` 里从 rawfile 读入；lite/gpnext 的注入内容为 `GPNEXT_SHIM + touchPatch.js`）。**不再依赖 `index.html` 里的 `<script src>`**，所以负载更新不会冲掉它 |

### 画面比例约束（3:2 ~ 17:9）

| 项 | 说明 |
|------|------|
| 常量 | `MIN_ASPECT_W/H = 3/2`、`MAX_ASPECT_W/H = 171/90`，交叉相乘判定避免浮点误差 |
| 容器尺寸 | `onAreaChange` 实测（小窗 / 分屏 / 2in1 均正确），`parseVp` 兜底带单位字符串 |
| 布局 | Web 用 `.width/.height/.position()` 居中；四周黑边由根 `Stack` 的黑色背景提供 |
| 详细说明 | 见 `docs/ASPECT_RATIO.md` |

### 资源拦截 (`onInterceptRequest`)

```typescript
URL: https://cocos.local/{path}
     → decodeURIComponent
     → 若 path 不以 PAYLOAD_DIR('game/') 开头、且不在 SHELL_ROOT_FILES 里，
       则补前缀：path = 'game/' + path        // 负载自带的 index.html 用根绝对路径 /assets/xxx.js
     → $rawfile(rawFilePath)
     → WebResourceResponse (MIME type 根据扩展名)
```

> ⚠️ 文件不存在时 `$rawfile()` 不抛错，返回的是 **200 + 空体**而不是 404；因此壳层在启动时自检
> `game/index.html` 与 `game/src/settings.json` 并在缺失时提示「负载缺失」（见
> [BUILD.md](BUILD.md) 的「负载目录约定与更新流程」）。

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

---

## 期望帧率投票（可变帧率 / LTPO）

**现象**：鸿蒙电脑 / 平板上，游戏内"有触摸时 120Hz，闲置一会儿掉到 60Hz"。

**原因（官方文档）**：鸿蒙的**控帧系统**收集应用的"期望绘制帧率"，参与**整机刷新率决策**：

> 应用层的多种 UI（动画组件、UI 绘制、XComponent 自绘制及非 UI 线程绘制）可以通过相对应的可变帧率接口
> （**expectedFrameRateRange、displaySync、OH_NativeXComponent_SetExpectedFrameRateRange 及 DisplaySoloist**）
> 接入到控帧系统。控帧系统收集 UI 设置的期望绘制帧率，参与到框架层的**整机刷新率决策**；服务端根据决策出的
> 刷新率结果进行绘制帧率分发……硬件层也会根据整机刷新率的决策结果，完成硬件器件的刷新率切换。

游戏的官方入口是 Graphics Accelerate Kit 的 **OpenGTX**（LTPO 三模式：`SCENE_MODE` / **`TOUCH_MODE`** /
`ADAPTIVE_MODE`）。本应用画面由**系统 Web 组件**承载：拿不到 XComponent 那套自绘制接口，也不在 OpenGTX 的
适用范围 —— 属于**不投票的 Vsync 请求者**（官方《Vsync 低功耗优化》把 WebView 单列为一类），因此系统在闲置时
会自适应降档。应用侧也无法直接设置刷新率（`@ohos.display` 只有只读的 `refreshRate` / `supportedRefreshRates`，
外加 `@ohos.settings.openScreenRefreshRateSettingsPage()` 让用户去系统设置里改）。

**做法**：壳层用 `displaySync` 参与投票（`pages/Index.ets`）：

```ts
const ENABLE_HIGH_REFRESH_VOTE: boolean = true;   // 想关掉就改 false
const HIGH_REFRESH_EXPECTED: number = 120;
const HIGH_REFRESH_MIN: number = 60;

const vote = displaySync.create();
vote.setExpectedFrameRateRange({ expected: 120, min: 60, max: 120 });
vote.on('frame', () => { /* 刻意留空：只为投票，不做任何绘制 */ });
vote.start();
```

只在**页面可见期间**持有（`onPageShow` / `onPageHide` / `aboutToDisappear` 里 start / stop），避免后台空刷帧。

### 用户可调：长按 GP 按钮 → 壳层设置面板

**长按右下角 GP 按钮**打开壳层设置面板（原先的"长按切换铺满 / 留边"已并入面板第一项，功能未丢）：

| 面板项 | 说明 |
| :--- | :--- |
| 画面：铺满 / 留边 | 等同原先的长按动作，持久化在 `PREF_WEB_FULLSCREEN` |
| 期望刷新率：关闭 / 60 / 120 / 最高 | 立即生效并持久化（`PREF_EXPECTED_REFRESH`）；`最高` = 取屏幕 `supportedRefreshRates` 的上限 |
| 当前屏幕刷新率 / 可用档位 | 只读；面板打开期间每秒刷新一次（`display.getDefaultDisplaySync()`） |

面板里同时提示：「引擎帧率由 GP-Next 面板 → 实验性 → 帧率 决定（默认 60），建议设为 120 或 不限」——
两个开关**相互独立**：面板管**系统刷新率决策**，GP-Next 管**引擎渲染上限**。

> `base` 变体没有悬浮 GP 按钮，因此它只有编译期开关（`ENABLE_HIGH_REFRESH_VOTE` + `DEFAULT_EXPECTED_REFRESH`），没有面板。

**实测**（平板 DMG-W00；读 `hidumper -s RenderService -a screen` 的 `activeMode`；全程零输入）：

| 条件（唯一变量=投票） | 场景 | GP-Next 帧率 | 引擎 frameRate | 显示刷新率（90 秒） |
| :--- | :--- | :--- | :--- | :--- |
| 投票关闭 | `mainScene` | `0`（不限） | `999` | **60Hz × 18（120 占比 0%）** |
| 投票开启 | `mainScene` | `0`（不限） | `999` | **120Hz × 18（120 占比 100%）** |

**代价与限制**：

- 官方最佳实践明确警告 `displaySync` 滥用会增加功耗、干扰可变帧率机制（"expected / min / max 都设 120"被点名）——
  这里把 `min` 设为 60 以避开该反模式，且回调刻意留空。
- 期望帧率**不保证生效**：官方原文"不能代表最终实际效果，会受限于系统功耗性能约束和屏幕刷新率硬件能力限制"。
- 与 GP-Next 面板的「帧率」设置**相互独立**：后者决定**引擎**渲染上限（30/60/120/144/不限，默认 60），
  前者只影响**系统刷新率决策**；两者都设对才可能长期 > 60fps。
- 关闭方式：面板里选「关闭」（运行时、立即生效、持久化）；或把 `ENABLE_HIGH_REFRESH_VOTE` 改成 `false`（编译期；base 变体只有这条）。

---

## 帧率相关的三套设置、两个存档键（真机 + 源码核对）

> 本节描述的是**带 GP-Next 的变体**（`lite` / `gpnext`）。**base 变体的负载里没有 gpNext 挂载点**
> （全目录 grep 0 命中），因此下表后两行在 base 上不存在 —— base 只有"游戏内置帧率"这一套。

| 名称 | 在哪里设置 | 存到哪 | 语义 |
| :--- | :--- | :--- | :--- |
| **游戏内置帧率** | 游戏内右下角**扳手**页面 | `localStorage['PvZ2_Settings'].animationFrameRate` | `1`=24 / `2`=30 / `3`=60 / **其它值（0）= 无限制**（其 getter 返回 `Infinity`） |
| **GP-Next 帧率上限** | GP-Next 存档（**现版本 GP-Next 设置页已无此控件**，是历史遗留值） | `localStorage['gp-next-settings'].frameRate` | `'0'` = 不限；数字 = 上限 |
| **实验帧率调度** | GP-Next → 实验性 | `localStorage['gp-next-settings'].experimental.{frameScheduler,frameRate}` | 纯 JS 节拍器（MessageChannel + setTimeout），**平板上会造成明显卡顿，建议关闭** |

- 游戏存档（玩家列表）另用独立键；**壳层从不触碰任何游戏存档**（`PvZ2_Settings` 在 Index.ets 中出现 0 次）。
- **GP-Next 面板「性能」页的「目标FPS」不可信**：它先读引擎实时值，但只在
  `Number.isFinite(v) && v > 0` 时才采信；游戏选「无限制」时该值为 `Infinity`（非有限数）→
  被判为"取不到" → 回退到 `gp-next-settings.frameRate`，于是把**存档里的旧数字**当成目标帧率显示。
  - 手机存档 `'0'`：它另有特判 `if (r === '0') return null` → 显示"不限"（看着对）
  - 平板存档 `'60'`（旧值）→ 直接显示 60（看着像被限住，其实引擎不限：实测 119 fps）
- **正确判据 = 壳层设置面板里的「实测」**（1 秒采样 `cc.director` 帧数）。
- 壳层设置面板的「**设为不限**」按钮：调用 `window.gpNext.setFrameRate(999)`（安全老路径）+
  把 `gp-next-settings.frameRate` 写成 `'0'`（与手机一致），**不修改游戏存档**。

---

## 存储：什么存在哪里（真机实测 + 负载源码核对）

### base 变体：只有白名单里的两个键

base 变体自己**不写任何壳层偏好**（铺满 / 留边是按画面比例实时算出来的，不持久化），
所以 Preferences 里只有白名单中的游戏键：

| 键 | 是什么 |
| :--- | :--- |
| `PvZ2_PlayerProperties` | **玩家存档**（关卡进度、植物 / 僵尸图鉴、花园、危险室、升级、每日关……），百 KB 量级 |
| `PvZ2_Settings` | **游戏设置**（`AnimationFrameRate`、音量、键位、语言等 20 个字段），明文 JSON |

> `lite` / `gpnext` 变体还会多几个**壳层自己**的键：`expected_refresh`、`settings_hint_seen`、`webview_fullscreen`。

### 缓存 / 数据清除的影响

- base 的帧率设置就落在白名单内的 `PvZ2_Settings.AnimationFrameRate` ⇒ **清缓存不影响它**
  （清"数据"才会把存档与设置一起复位）
- 但 **ArkWeb 自己的网页存储是在"清缓存"时被清掉的**：任何**没进白名单**的网页端设置都活不过一次清缓存
  （`lite` / `gpnext` 变体的 `gp-next-settings` 就是这种情况 —— 表现为"帧率回落 60，但存档与模组都还在"）

### 游戏侧：谁在什么时候写存档（负载源码核对）

| 键 | 写者 | 读者 |
| :--- | :--- | :--- |
| `PvZ2_PlayerProperties` | `assets/main/index.js` → `AllPlayerProperties.savePP()`：`localStorage.setItem('PvZ2_PlayerProperties', JSON.stringify(allPlayers))` | `getPlayer(index)` |
| `PvZ2_Settings` | 同文件 → `Setting.saveSettings()`：`localStorage.setItem('PvZ2_Settings', JSON.stringify(settings))` | `Setting.getSettings()` |

- **触发方式**：离散事件（关卡进度、解锁、货币、卡组、危险室、花园、世界地图…… 50+ 处），**没有防抖 / 节流**，
  也没有 `beforeunload` / `pagehide` 存档钩子
- ⚠️ **有两处会逐帧写盘**（真机上表现为持续的存储 I/O）：
  - 花园格子 `update()` → **每帧** `savePP()`
  - 骆驼关 `update()` → **每帧** `saveSettings()`
  两者都会经过下面的壳层桥 → `preferences.put()` + `flush()`，**桥本身也不节流**
- **格式**：裸 `JSON.stringify`，无压缩 / 加密 / 外层版本包裹；`PvZ2_Settings` 是 20 字段的明文对象（**没有 version 字段**）
- **启动读取**：`mainScene` 先 `getSettings().PlayerIndex` → 再 `getPlayer(index)`；
  缺失时建默认玩家（`name = "New Player"`）与默认设置；旧字段（数组 → 字典）的迁移散落在 `getLevelProps()` 等函数里，
  迁移后置 `undefined` 并立即存回
- 注意 `getPlayer()` 结尾会执行 `time = Date.now(); savePP()` ⇒ **每次进游戏都会重写一次存档**
- 健壮性提醒：`getSettings()` **没有 try/catch**，若 `PvZ2_Settings` 里的 JSON 非法会直接抛异常

### 壳层侧：`touchPatch.js` 的**硬编码白名单**（桥在这里，不在负载里）

`rawfile/touchPatch.js`（经 `.javaScriptOnDocumentStart` 注入，早于页面一切脚本）：

```js
var PERSIST_KEYS = ['PvZ2_PlayerProperties', 'PvZ2_Settings'];   // 只镜像这两个键
localStorage.setItem = function (key, value) {
  originalSetItem.call(localStorage, key, value);
  if (PERSIST_KEYS.indexOf(key) !== -1 && window.NativeStorage) {
    window.NativeStorage.saveToNative(key, value);              // → Preferences(store game_save)
  }
};
// 启动时反向回填：loadFromNative(key) → originalSetItem(...)，等 NativeStorage 就绪（最多 50 × 100ms）
```

- 因此 **Preferences 里只会出现白名单里的键**（外加壳层自己写的那几个）—— 与实测完全吻合
- 游戏与引擎（`sys.localStorage = window.localStorage`）读写的就是**被 patch 的同一个对象**

> 过期注释提醒：早期注释说"负载自带的 localStorage polyfill 只在 `__TAURI_INTERNALS__` 缺失时才安装"——
> 那只对 **0.14.0 负载**成立。**当前 0.15.0 负载没有该 polyfill**（`saveToNative` / `loadFromNative` /
> `plugin:store` 在负载里全部 0 命中），唯一的桥就是上面的 `touchPatch.js`。

### 上报（写）与回填（读）：两个方向、三个坑

`touchPatch.js` 双向工作的全部细节（这是**唯一**的持久化通路）：

**上报（页面写 → Preferences）**：覆写 `localStorage.setItem`

```js
var PERSIST_KEYS = ['PvZ2_PlayerProperties', 'PvZ2_Settings'];   // 硬编码白名单
var originalSetItem = localStorage.setItem;

localStorage.setItem = function (key, value) {
  originalSetItem.call(localStorage, key, value);        // ① 同步写进 WebView 自己的存储
  if (PERSIST_KEYS.indexOf(key) !== -1 && window.NativeStorage) {
    window.NativeStorage.saveToNative(key, value)        // ② 异步上报（不 await，失败只打日志）
      .catch(function (e) { console.error('[localStorage] 保存 ' + key + ' 失败', e); });
  }
};
```

**回填（Preferences → 页面）**：轮询等原生代理就绪后反向写回

```js
waitForNativeStorage(function () {                        // 每 100ms 一次，最多 50 次（≈5 秒）
  Promise.all(PERSIST_KEYS.map(function (key) {
    return window.NativeStorage.loadFromNative(key).then(function (nativeValue) {
      if (nativeValue && !originalGetItem.call(localStorage, key)) {  // 只在“页面里还没有值”时
        originalSetItem.call(localStorage, key, nativeValue);         // 用 original* ⇒ 不触发上报
      }
    });
  }));
});
```

**一次启动的时序**

```
① document-start 注入 GPNEXT_SHIM + touchPatch.js（早于页面任何脚本）
② 页面脚本开跑（引擎 → 游戏 → 读 PvZ2_Settings / PvZ2_PlayerProperties）
③ onControllerAttached → registerNativeStorage() 注册代理（+ refresh）
④ touchPatch 轮询到代理就绪 → loadFromNative ×2 → originalSetItem 回填
```

⚠️ **三个必须知道的坑**

| # | 现象 | 原因 |
| :---: | :--- | :--- |
| 1 | 回填可能**晚于**游戏首次读取 ⇒ 这次启动读到默认值 | 回填是轮询触发的异步动作，可能几秒后才发生 |
| 2 | 页面里**已经有值**时不回填 ⇒ 恢复被挡住 | 回填条件是 `!originalGetItem(...)` |
| 3 | **早于**代理注册的写入会被静默丢弃 | 上报条件里带 `&& window.NativeStorage`，不排队、不补发，失败也不重试 |

> 坑 2 直接影响"把 `gp-next-settings` 加进白名单"这件事：shim 会在 document-start 就写这个键，
> 于是回填会被判为"页面已有值"而**跳过** ⇒ 那一步必须把回填改成**合并 / 覆盖**，不能只加白名单。

### `AnimationFrameRate` 的语义（源码核对）

```js
switch (animationFrameRate) {          // PvZ2_Settings.animationFrameRate
  case 1: return 24;  case 2: return 30;  case 3: return 60;
}
return animationFrameRate = 0, Infinity;   // 其它值（含 0）= 无限制，并被强制归 0
```

- **唯一生效点**是把结果赋给引擎：`cc.game.frameRate = 该值` → 影响 pacer 的 `targetFrameRate`
- 引擎**初始恒为 60**，直到设置面板加载后才按上面的值调整
- `gp-next-settings.frameRate`（字符串 `'0'` / `'30'` / `'60'`）**不驱动引擎**，只用于面板显示兜底与导入校验；
  真正改引擎的是 `experimental.frameScheduler/frameRate`、`window.gpNext.setFrameRate()` 或 mod-api 的 `setFrameRate`

### 排查方法（开发者模式可直接读，不必加日志）

```powershell
hdc -t <设备> file recv `
  /data/app/el2/100/base/com.gardendless.<变体>/haps/entry/preferences/game_save `
  <本地路径>
# 内容是 <preferences> 结构的 XML，键名与值都是明文
```

> 🔒 该文件里**包含玩家的完整存档**：只在本地查看，**不要提交进仓库、不要贴进 release 正文**。

### 判定"持久化是否正常"的正确做法

「帧率上限 60 fps」**不是**故障信号 —— 它本来就是存档为空时的默认值。要判定：

1. 面板点「**设为不限**」（写入非默认值）
2. `hdc shell "aa force-stop <bundle>"` 杀掉应用
3. 重开 → 打开面板：仍显示「**不限**」⇒ DOM Storage 持久化正常；回到「60」⇒ 网页存储被清过
