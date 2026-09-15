# PvZ2 Gardendless for HarmonyOS

本项目基于 [pvzge.com](https://pvzge.com/) 原版 **PvZ2 Gardendless（植物大战僵尸 2 无花园重制版，
原版仓库 [Gzh0821/pvzge_web](https://github.com/Gzh0821/pvzge_web)）**，迁移适配 **HarmonyOS / OpenHarmony**：
ArkTS 原生壳层 + ArkWeb 承载 Cocos 构建产物，保留原版核心玩法与工具链。

- 非 EA / PopCap 官方产品，为爱好者社群开源移植项目
- 一次开发、多端部署：支持鸿蒙手机、平板与 2in1（PC）形态
- 原生壳层：沉浸式全屏、横屏适配、画面比例约束、资源拦截与存档桥接

| | |
|:---|:---|
| 应用名 | **Gardendless**（Ability 标签 `Pvz2 Gardendless`） |
| 包名 | `com.Pvz2.gardendless` |
| 版本 | `0.14.0`（versionCode `1000007`） |
| 设备类型 | `phone`、`tablet`、`2in1` |
| SDK | `compatibleSdkVersion` 6.0.0(20) ／ `targetSdkVersion` 6.0.2(22) |

> 另有两个带 GP-Next 面板的变体（各自独立包名，可与本应用共存安装），不在本仓库中。

---

## 安装方法

您可以使用[小白调试助手 Auto-installer](https://github.com/likuai2010/auto-installer)进行安装。

> [!NOTE]
> 在 HarmonyOS NEXT 中，通过自签名方式侧载的 App 默认有效期为 **14 天**，进行
> [开发者实名认证](https://developer.huawei.com/consumer/cn/verified/enrollment)后，
> 可将有效期延长至 **180 天**。

前往 [Release](https://github.com/WingedFin1251/Pvz-Gardendless-harmony/releases) 页面下载 hap 包。

---

## ⚠️ 游戏负载不在本仓库中

`entry/src/main/resources/rawfile/` 下的**游戏负载不纳入版本管理**，仓库只保留两个手写壳层文件：

| 纳入 Git | 说明 |
|:---|:---|
| `index.html` | 壳层入口页 |
| `touchPatch.js` | 触摸转换补丁 |

缺少下列内容时，工程**可以编译通过，但运行会白屏**：

| 缺失内容 | 说明 |
|:---|:---|
| `rawfile/assets/` | Cocos 资源包（v0.14.0 约 1.27 GB） |
| `rawfile/cocos-js/` | Cocos 引擎运行时 |
| `rawfile/src/` | `settings.json` 等构建配置 |
| `rawfile/application.js`、`index.js`、`style.css` | Cocos 构建产物 |

**获取方式**：从 [Release](https://github.com/WingedFin1251/Pvz-Gardendless-harmony/releases) 下载 HAP
（解压后取其中的 `rawfile/`），或从 [pvzge.com](https://pvzge.com/) 获取游戏资源，放入
`entry/src/main/resources/rawfile/` 即可。

---

## 快速开始

### 环境准备

1. 安装 [DevEco Studio](https://developer.harmonyos.com/cn/develop/deveco-studio)
   （工程声明 `compatibleSdkVersion` 6.0.0(20)、`targetSdkVersion` 6.0.2(22)）
2. 放入游戏负载（见上文）
3. 在 `File → Project Structure → Signing Configs` 配置本机签名——
   仓库中的 `build-profile.json5` **不含 `signingConfigs`**（避免提交本机路径与签名材料），
   未配置时 `SignHap` 会失败

### 构建运行

```bash
# 克隆仓库
git clone https://github.com/WingedFin1251/Pvz-Gardendless-harmony.git
cd Pvz-Gardendless-harmony

# 使用 DevEco Studio 打开工程
# 连接鸿蒙设备或启动模拟器
# 点击“运行”生成 HAP 并安装
```

命令行构建（未配置签名时产物为 unsigned HAP）：

```bash
export DEVECO_SDK_HOME="<DevEco 安装目录>/sdk"

"<DevEco 安装目录>/tools/hvigor/bin/hvigorw" \
  --mode module -p product=default -p module=entry@default assembleHap --no-daemon
```

> `DEVECO_SDK_HOME` 必须指向 **sdk 根目录**；指向 `sdk/default/openharmony` 子目录会报
> `00303312 Cannot find the corresponding SDK version`。

### 目录说明

```
Pvz-Gardendless-harmony/
├── AppScope/                     # 应用级配置：包名、版本、图标
├── entry/                        # 主模块（entry HAP）
│   ├── src/main/
│   │   ├── ets/
│   │   │   ├── entryability/     # EntryAbility：沉浸式全屏、横屏、Web 引擎初始化
│   │   │   ├── entrybackupability/
│   │   │   ├── pages/            # Index 页面（Web 组件、请求拦截、下载、文件选择）
│   │   │   └── utils/            # 资源缓存、性能监控
│   │   ├── module.json5
│   │   └── resources/
│   │       ├── base/             # 图标、颜色、字符串、profile
│   │       ├── dark/
│   │       └── rawfile/          # 游戏负载（仅 index.html / touchPatch.js 纳入 Git）
│   ├── src/ohosTest/ · src/test/ # 测试
│   └── build-profile.json5
├── docs/                         # 文档（见下表）
├── hvigor/
├── build-profile.json5           # 工程配置：SDK 版本与产物（签名由本机配置）
└── oh-package.json5
```

---

## 壳层能力

| 文件 | 内容 |
|:---|:---|
| `entry/src/main/ets/pages/Index.ets` | **画面比例约束 3:2 ~ 17:9**（超出区间由壳层补黑边，逻辑对齐安卓版 `AspectRatioFrameLayout`）：`onAreaChange` 实测容器尺寸、`parseVp` 兜底带单位字符串、Web 用 `width/height/position` 居中；根容器 `Stack`，状态提示叠加在画面顶部并放行触摸 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 先 `loadContent` 再配置窗口（官方要求 `setWindowBackgroundColor()` 在 `loadContent()` 生效后调用）；`IS_2IN1` 分流：`2in1` 改用 `maximize()` 进入沉浸式全屏并跳过方向设置 |
| `entry/src/main/ets/utils/ResourceManager.ets` | `getRawFile`（API 9 起废弃）→ `getRawFileContent` |

---

## 文档

| 文档 | 内容 |
|:---|:---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 架构概览、数据流、组件层级 |
| [docs/MODULES.md](docs/MODULES.md) | 各模块详细说明 |
| [docs/BUILD.md](docs/BUILD.md) | 构建配置、签名、部署、常见问题 |
| [docs/ASPECT_RATIO.md](docs/ASPECT_RATIO.md) | 画面比例约束方案与取舍 |
| [docs/WEBVIEW_PERF.md](docs/WEBVIEW_PERF.md) | **ArkWeb 性能**：内核版本对应、负载实测、问题清单与优化优先级 |
| [docs/RELEASE_v0.14.0.md](docs/RELEASE_v0.14.0.md) | v0.14.0 更新说明 |
| [docs/PERFORMANCE_OPTIMIZATION.md](docs/PERFORMANCE_OPTIMIZATION.md) 等 | 性能优化与对比报告 |

---

## 贡献指南

欢迎提交 Issue、PR 参与共建：

1. Fork 本仓库
2. 创建功能分支（`feature/xxx` 或 `fix/xxx`）
3. 遵循 ArkTS 代码规范与鸿蒙工程规范
4. 提交 PR 并附清晰说明
5. 等待评审与合并

---

## 许可证

- **本移植项目**：**GPL-3.0 license**，完整许可文本见 [`LICENSE`](LICENSE)。
  作为 GPL-3.0 的衍生作品对外分发时，须同时提供完整对应源码（本仓库包含全部壳层源码；
  游戏负载为第三方内容、不随仓库分发）。
- **原版 PvZ2 Gardendless**：遵循 [pvzge.com](https://pvzge.com/) 社群授权协议，
  原版仓库 [Gzh0821/pvzge_web](https://github.com/Gzh0821/pvzge_web)。
- **游戏素材**：版权归原作者所有，本项目仅用于学习与交流。

## 免责声明

本项目为非官方开源移植作品，仅供学习与技术交流使用，严禁用于商业用途。使用本项目需遵守当地法律法规
与原版社群协议，因使用产生的任何风险由使用者自行承担。

---

🌟 如果本项目对你有帮助，欢迎 Star、Fork、分享！
📧 联系与反馈：GitHub Issues 或项目讨论区
