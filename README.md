# Gardendless Lite

基于 [PvZ2 Gardendless](https://pvzge.com/)（植物大战僵尸 2 无花园重制版）的 **HarmonyOS / OpenHarmony 移植工程**，
与本项目原仓库 [WingedFin1251/Pvz-Gardendless-harmony](https://github.com/WingedFin1251/Pvz-Gardendless-harmony)
同源（同一作者维护），共用同一套壳层代码。

| | |
|:---|:---|
| 应用名 | **Gardendless Lite** |
| 包名 | `com.gardendless.lite` |
| 版本 | `0.14.0`（versionCode `1000007`） |
| 设备类型 | `phone`、`tablet`、`2in1` |
| SDK | `compatibleSdkVersion` 6.0.0(20) ／ `targetSdkVersion` 6.0.2(22) |

> **非 EA / PopCap 官方产品**，为爱好者社群的开源移植项目。
>
> 本工程是**三仓库体系**中的「精简版」（仓库层面精简的 GP-Next 版）。另两个仓库为：
> 原仓库 / 基础版 `Gardendless`（无 GP-Next）、以及 GP-Next 版 `Gardendless-gpnext`（独立包名）。
> 三者的定位、共享/身份文件划分与同步方式见 **[docs/REPOS.md](docs/REPOS.md)**。

---

## 安装（面向使用者）

| 方式 | 说明 |
|:---|:---|
| 小白调试助手 Auto-installer | 使用 [likuai2010/auto-installer](https://github.com/likuai2010/auto-installer) 侧载 HAP，无需 DevEco Studio |
| 原仓库 Release 的 HAP | 从原仓库 [Release](https://github.com/WingedFin1251/Pvz-Gardendless-harmony/releases) 页面下载。注意该 HAP 的包名 / 应用名是 `Gardendless`，与本应用的 `com.gardendless.lite` **不同**，因此两者可共存、但无法互相覆盖安装 |

> [!NOTE]
> HarmonyOS NEXT 中通过自签名侧载的应用默认有效期为 **14 天**；完成
> [开发者实名认证](https://developer.huawei.com/consumer/cn/verified/enrollment) 后可延长至 **180 天**。
> 本仓库尚未发布自己的 Release，自行构建见下文「快速开始」。

---

## ⚠️ 重要：游戏资源不在本仓库中

`entry/src/main/resources/rawfile/` 下的**游戏负载不纳入版本管理**，仓库只保留两个手写壳层文件：

| 纳入 Git | 说明 |
|:---|:---|
| `index.html` | 壳层入口页 |
| `touchPatch.js` | 触摸 / GP-Next 面板补丁 |

缺少下列内容时，工程**可以编译通过，但运行会白屏**：

| 缺失内容 | 说明 |
|:---|:---|
| `rawfile/assets/` | Cocos 资源包（约 570 MB） |
| `rawfile/cocos-js/` | Cocos 引擎运行时 |
| `rawfile/src/` | `settings.json` 等构建配置 |
| `rawfile/application.js`、`index.js`、`style.css` | Cocos 构建产物 |

**获取方式**：从原仓库的 [Release](https://github.com/WingedFin1251/Pvz-Gardendless-harmony/releases) 下载 HAP
（解压后取其中的 `rawfile/`），或从 [pvzge.com](https://pvzge.com/) 获取游戏资源，放入
`entry/src/main/resources/rawfile/` 即可。

---

## 架构

采用 **ArkTS 原生壳层 + ArkWeb 承载 Cocos 构建产物**：游戏本体运行在 Web 容器内（虚拟域 `https://cocos.local/`），
ArkTS 侧负责窗口、资源、存档与文件能力。

| 模块 | 职责 |
|:---|:---|
| `entryability/EntryAbility.ets` | 主 Ability。沉浸式全屏与横屏；`2in1` 上改用 `maximize()` 进入全屏；初始化 Web 多进程渲染、响应内存压力回收 |
| `entrybackupability/EntryBackupAbility.ets` | 备份扩展（配合 `backup_config.json`） |
| `pages/Index.ets` | 页面主体。Web 组件（`ASYNC_RENDER` 异步渲染，不阻塞主线程）、`cocos.local` 请求拦截、外链转系统浏览器、下载委托与文件保存、`NativeStorage` 存档代理 |
| `utils/ResourceManager.ets` | rawfile 资源 LRU 缓存：80 MB / 300 项上限、10 秒超时、连续失败 3 次跳过、音频不入缓存 |
| `utils/PerformanceMonitor.ets` | 性能埋点：帧率采样，以及渲染 / 资源加载 / 缓存命中 / 错误 / 内存告警事件 |
| `pages/FilePickerHelper.ets` | 文件选择与公共目录保存 |

关键实现要点：

- **资源链路**：`onInterceptRequest` 拦截 `https://cocos.local/*` 请求 → 命中 `ResourceManager` 缓存则直接返回 →
  未命中则读取 `$rawfile` 并回填缓存；网络请求与 `data:` / `blob:` 等协议放行。
- **存档持久化**：通过 `registerJavaScriptProxy` 向页面暴露 `NativeStorage.saveToNative` / `loadFromNative`，
  底层使用 `preferences`（`game_save`）落盘。
- **多设备适配**：`setWindowSystemBarEnable`、`setPreferredOrientation`、`overviewModeAccess` 在 `2in1`
  上按官方文档属「不生效也不报错」，已在调用点用 `// @SuppressWarnings syscap` 抑制相应多设备告警。

---

## 目录结构

```
Gardendless-lite/
├── AppScope/                       # 应用级配置与图标
│   ├── app.json5                   # 包名、版本、应用名
│   └── resources/base/             # 分层图标、字符串资源
├── entry/                          # 主模块（entry HAP）
│   ├── src/main/
│   │   ├── ets/
│   │   │   ├── entryability/       # EntryAbility：全屏 / 横屏 / Web 引擎
│   │   │   ├── entrybackupability/ # EntryBackupAbility：备份扩展
│   │   │   ├── pages/              # Index 页面、文件选择助手
│   │   │   └── utils/              # 资源缓存、性能监控
│   │   ├── module.json5            # 设备类型、Ability、页面配置
│   │   └── resources/
│   │       ├── base/               # 图标、颜色、字符串、profile
│   │       ├── dark/               # 深色模式资源
│   │       └── rawfile/            # 游戏负载（仅 index.html / touchPatch.js 纳入 Git）
│   ├── src/ohosTest/               # 仪器化测试
│   ├── src/test/                   # 本地单元测试
│   └── build-profile.json5         # 模块构建配置（含发布混淆开关）
├── docs/                           # 项目文档
├── hvigor/                         # hvigor 构建配置
├── build-profile.json5             # 工程配置：签名、SDK 版本、产物
├── code-linter.json5               # 代码检查规则
├── hvigorfile.ts                   # 构建脚本入口
└── oh-package.json5                # 依赖声明
```

---

## 环境要求

| 项 | 要求 |
|:---|:---|
| DevEco Studio | 需安装 HarmonyOS SDK。工程 `compatibleSdkVersion` 为 `6.0.0(20)`、`targetSdkVersion` 为 `6.0.2(22)`；实测 API 26 SDK 亦可正常构建 |
| 运行时 | `runtimeOS: HarmonyOS`，Stage 模型 |
| 依赖 | 无第三方运行时依赖；测试依赖 `@ohos/hypium`、`@ohos/hamock`（devDependencies） |

---

## 快速开始

1. 克隆本仓库
2. **放入游戏资源**（见上文「游戏资源不在本仓库中」）
3. 使用 DevEco Studio 打开工程
4. 在 `File → Project Structure → Signing Configs` **重新生成签名**——包名为 `com.gardendless.lite`，
   需与 AppGallery Connect 中的应用条目一致，直接沿用旧签名会因包名不匹配而失败
5. 连接设备或启动模拟器，点击运行

### 命令行构建

```bash
export DEVECO_SDK_HOME="<DevEco 安装目录>/sdk"

"<DevEco 安装目录>/tools/hvigor/bin/hvigorw" \
  --mode module -p product=default -p module=entry@default assembleHap --no-daemon
```

产物位于 `entry/build/default/outputs/default/entry-default-signed.hap`。

> `DEVECO_SDK_HOME` 必须指向 **sdk 根目录**；若指向 `sdk/default/openharmony` 子目录，
> 会报错 `00303312 Cannot find the corresponding SDK version`。

---

## 文档

| 文档 | 内容 |
|:---|:---|
| [docs/REPOS.md](docs/REPOS.md) | **三仓库关系**：定位、共享/身份文件划分、同步方式 |
| [docs/BUILD.md](docs/BUILD.md) | 构建配置、签名、部署、游戏资源说明、常见问题 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 架构说明 |
| [docs/MODULES.md](docs/MODULES.md) | 模块划分与职责 |
| [docs/ASPECT_RATIO.md](docs/ASPECT_RATIO.md) | 画面比例方案记录 |
| [docs/WEBVIEW_PERF.md](docs/WEBVIEW_PERF.md) | **ArkWeb 性能**：内核版本对应、负载实测、壳层问题清单与优化优先级 |
| [docs/RELEASE_v0.14.0.md](docs/RELEASE_v0.14.0.md) | v0.14.0 更新说明 |
| [docs/PERFORMANCE_OPTIMIZATION.md](docs/PERFORMANCE_OPTIMIZATION.md) | 性能优化方案 |
| [docs/PERFORMANCE_OPTIMIZATION_SUMMARY.md](docs/PERFORMANCE_OPTIMIZATION_SUMMARY.md) | 性能优化总结 |
| [docs/PERFORMANCE_COMPARISON_REPORT.md](docs/PERFORMANCE_COMPARISON_REPORT.md) | 性能优化对比报告 |

---

## 已知限制

- **游戏资源需自行放置**：克隆后直接构建运行会白屏。
- **`2in1` 形态的能力差异**：系统栏隐藏与窗口方向锁定在该形态下不适用（已改用最大化 + 全屏）；
  `overviewModeAccess` 无效果。

---

## 许可与致谢

- **原作**：[PvZ2 Gardendless](https://pvzge.com/)（植物大战僵尸 2 无花园重制版），
  原版 Gardendless 仓库 [Gzh0821/pvzge_web](https://github.com/Gzh0821/pvzge_web)，
  遵循 pvzge.com 社群授权协议。**非 EA / PopCap 官方产品**。
- **原仓库**：本工程与 [WingedFin1251/Pvz-Gardendless-harmony](https://github.com/WingedFin1251/Pvz-Gardendless-harmony)
  同源（同一作者维护）。
- **许可证**：本仓库以 **GPL-3.0** 授权，完整许可文本见 [`LICENSE`](LICENSE)。
  作为 GPL-3.0 的衍生作品对外分发时，须同时提供完整对应源码；本仓库已包含全部壳层源码，
  游戏负载为第三方内容、不随仓库分发（见上文说明）。
- **游戏素材**：版权归原作者所有，仅用于学习与技术交流。
- **贡献**：欢迎 Issue / PR。Fork 后新建分支（`feature/xxx`、`fix/xxx`），
  遵循 ArkTS 与鸿蒙工程规范，提交 PR 时附清晰说明。
- **免责声明**：本项目为非官方开源移植作品，仅供学习与技术交流，**严禁用于商业用途**；
  使用需遵守当地法律法规与原版社群协议，因使用产生的风险由使用者自行承担。
