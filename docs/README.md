# Gardendless — 开发文档

**版本**: 0.9.3  
**目标平台**: HarmonyOS NEXT (API 23 / 6.0.2+)  
**应用类型**: Cocos Creator 游戏 WebView 容器

---

## 文档目录

| 文档 | 说明 |
|------|------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | 项目架构概览、数据流、组件层级 |
| [MODULES.md](MODULES.md) | 各模块详细说明（Index、FilePickerHelper、ResourceManager 等） |
| [BUILD.md](BUILD.md) | 构建配置、签名、部署流程 |

---

## 快速开始

### 环境要求

- DevEco Studio 6.0 或更高版本
- HarmonyOS SDK API 23+
- HarmonyOS NEXT 真机或模拟器

### 打开项目

1. 启动 DevEco Studio
2. 选择 **File → Open**，打开本项目根目录
3. 等待 Hvigor 依赖解析完成

### 运行

1. 连接 HarmonyOS NEXT 设备
2. 点击工具栏 **Run → Run 'entry'** (或按 `Shift+F10`)
3. 应用将自动安装并启动

### 目录结构速览

```
Gardendless/
├── AppScope/              # 应用级配置（bundleName、图标、版本）
│   ├── app.json5
│   └── resources/
├── entry/                 # 主模块
│   ├── src/main/
│   │   ├── ets/
│   │   │   ├── entryability/      # UIAbility 入口
│   │   │   ├── pages/             # 页面组件
│   │   │   └── utils/             # 工具类
│   │   └── resources/rawfile/    # Cocos Creator 游戏资源
│   └── build-profile.json5
├── build-profile.json5    # 根构建配置
├── hvigorfile.ts          # Hvigor 构建入口
└── docs/                  # 开发文档（本目录）
```

---

## 核心技术栈

| 技术 | 用途 |
|------|------|
| ArkTS + ArkUI | 声明式 UI 框架 |
| `@kit.ArkWeb` | WebView 组件，承载 Cocos 游戏 |
| `@ohos.data.preferences` | 游戏数据键值对持久化 |
| `@ohos.file.fs` | 文件系统操作（下载） |
| Cocos Creator Web | 游戏引擎（rawfile 部署） |
