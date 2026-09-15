# 架构概览

## 整体架构

```
┌──────────────────────────────────────────────┐
│                  EntryAbility                  │
│  ┌─────────────────────────────────────────┐ │
│  │        WebView Engine 初始化              │ │
│  │  - 多进程模式                              │ │
│  │  - 整页绘制                                │ │
│  │  - 全屏横屏                                │ │
│  └─────────────────────────────────────────┘ │
│                    │                           │
│                    ▼                           │
│  ┌─────────────────────────────────────────┐ │
│  │           pages/Index (主页面)            │ │
│  │                                           │ │
│  │  ┌────────────────────────────────┐      │ │
│  │  │         WebView 组件             │      │ │
│  │  │  src: https://cocos.local/     │      │ │
│  │  │                                │      │ │
│  │  │  ┌──────────────────────────┐ │      │ │
│  │  │  │   Cocos Creator 游戏      │ │      │ │
│  │  │  │   (HTML/CSS/JS/WASM)     │ │      │ │
│  │  │  │                          │ │      │ │
│  │  │  │  ┌────────────────────┐ │ │      │ │
│  │  │  │  │  NativeStorage JS  │ │ │      │ │
│  │  │  │  │  代理 (持久化桥接)   │ │ │      │ │
│  │  │  │  └────────────────────┘ │ │      │ │
│  │  │  └──────────────────────────┘ │      │ │
│  │  └────────────────────────────────┘      │ │
│  │                                           │ │
│  │  辅助组件:                                 │ │
│  │  - Text (下载状态)                         │ │
│  │  - Progress (加载进度)                     │ │
│  │  - Button (调试面板)                       │ │
│  └─────────────────────────────────────────┘ │
└──────────────────────────────────────────────┘
```

## 数据流

```
WebView (Cocos 游戏)
    │
    ├── 资源请求 ──► onInterceptRequest ──► $rawfile() 本地资源
    │
    ├── JS 数据持久化 ──► NativeStorage 代理
    │                        │
    │                  saveToNative() ──► preferences.put() + flush()
    │                  loadFromNative() ◄── preferences.get()
    │
    ├── Cookie ──► WebCookieManager.saveCookieAsync()
    │
    └── 文件下载 ──► WebDownloadDelegate
                        │
                  onBeforeDownload ──► FilePickerHelper.save() (用户选路径)
                        │
                  onDownloadFinish ──► fs.copyFileSync (tempDir → 目标路径)
```

## 核心设计决策

### 1. 虚拟域名 + 资源拦截

游戏资源通过 `https://cocos.local/` 虚拟域名访问，由 `onInterceptRequest` 拦截并映射到本地 `$rawfile()` 资源。这样做的优势：

- Cocos 引擎无需修改资源加载逻辑
- 所有资源预置在 APK 包内，无需网络
- MIME 类型根据文件扩展名动态设置

### 2. JS-Native 桥接持久化

游戏侧的 `localStorage` 操作通过 `registerJavaScriptProxy` 映射到原生 `preferences` 存储：

- `NativeStorage.saveToNative(key, value)` → `preferences.put(key, value)`
- `NativeStorage.loadFromNative(key)` → `preferences.get(key)`

相比直接使用 WebView 的 localStorage，这种方式避免了 Web 存储被系统清理的风险。

### 3. 下载流程

文件下载采用"先临时再移动"策略：

1. `onBeforeDownload` → 用户选择目标路径（`FilePickerHelper`）
2. 下载到应用 `cacheDir` 临时文件
3. `onDownloadFinish` → 复制到用户选择的公共目录（带目录自动创建和路径清洗）
4. 备选方案：复制失败的 fallback 保存到 `filesDir`

### 4. Context 获取方式

从 API 18 起，使用 `this.getUIContext().getHostContext()` 替代已废弃的 `getContext(this)`，确保 UI 上下文绑定明确。

## 生命周期

```
EntryAbility:onCreate()  →  EntryAbility:onWindowStageCreate()
                                        │
                              windowStage.loadContent('pages/Index')
                                        │
                                        ▼
                          Index.aboutToAppear()
                              │  getUIContext().getHostContext()
                              │  preferences.getPreferences('game_save')
                              │  new FilePickerHelper()
                              ▼
                          Index.build() → WebView 创建
                              │
                      WebView.onControllerAttached()
                              │  registerJavaScriptProxy('NativeStorage', ...)
                              ▼
                      WebView.onPageEnd()
                              │  setupDownloadDelegate()
                              │  WebCookieManager.saveCookieAsync()
                              ▼
                      Index.aboutToDisappear()
                              │  clearTimeout()
                              │  resourceCache.clear()
```

## 横屏 + 全屏配置

在 `EntryAbility.ets` 的 `onWindowStageCreate` 中设置：

```typescript
windowClass.setPreferredOrientation(window.Orientation.LANDSCAPE)
windowClass.setWindowLayoutMode(mode: WindowLayoutMode.FULL_WINDOW)
```

配合 `module.json5` 中的配置：
```json5
"orientation": "landscape"
"supportWindowMode": ["fullscreen", "split", "floating"]
```
