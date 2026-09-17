# Gardendless Lite

基于 [PvZ2 Gardendless](https://pvzge.com/)（植物大战僵尸 2 无花园重制版）的 **HarmonyOS / OpenHarmony 移植工程**，
与主仓库 [WingedFin1251/Pvz-Gardendless-harmony](https://github.com/WingedFin1251/Pvz-Gardendless-harmony)
同源（同一作者维护），共用同一套壳层代码。

| | |
|:---|:---|
| 应用名 | **Gardendless Lite** |
| 包名 | `com.gardendless.lite` |
| 版本 | `0.14.0`（versionCode `1000007`） |
| 设备类型 | `phone`、`tablet`、`2in1` |
| SDK | `compatibleSdkVersion` 6.0.0(20) ／ `targetSdkVersion` 6.0.2(22) |
| 本分支 | `lite` |

> **非 EA / PopCap 官方产品**，为爱好者社群的开源移植项目。
>
> 三个产物以**同一仓库的三个分支**发布，包名各不相同、**可共存安装**：
>
> | 分支 | 产物 | 包名 | 游戏负载 |
> |:---|:---|:---|:---|
> | `main` | Gardendless（基础版，无 GP-Next） | `com.Pvz2.gardendless` | 约 1.27 GB |
> | `lite` | **Gardendless Lite（本分支）** | `com.gardendless.lite` | 约 576 MB |
> | `gpnext` | Gardendless GP-Next | `com.gardendless.gpnext` | 约 1.39 GB |
>
> **「Lite」指游戏负载较另两个产物更小**；壳层源码（含 GP-Next 兼容层与原生桥）与 `gpnext` 分支一致，
> 逐文件比对只有 5 个文件属于应用身份或说明（`AppScope/app.json5`、
> `AppScope/resources/base/element/string.json`、`entry/src/main/resources/base/element/string.json`、
> `README.md`、`docs/BUILD.md`）。划分与同步方式见 **[docs/REPOS.md](docs/REPOS.md)**。

---

## 安装（面向使用者）

| 方式 | 说明 |
|:---|:---|
| 本仓库 Release | 从 [Release](https://github.com/WingedFin1251/Pvz-Gardendless-harmony/releases) 下载对应 HAP；三个产物同处一个 Release，附校验值与安装指引 |
| 小白调试助手 Auto-installer | 使用 [likuai2010/auto-installer](https://github.com/likuai2010/auto-installer) 侧载 HAP，无需 DevEco Studio |

> [!NOTE]
> 三个产物均为**未签名包**，安装前需自行签名。HarmonyOS NEXT 中通过自签名侧载的应用默认有效期为
> **14 天**，完成[开发者实名认证](https://developer.huawei.com/consumer/cn/verified/enrollment)
> 后可延长至 **180 天**。三者包名不同，可共存安装、无法互相覆盖。

---

## ⚠️ 重要：游戏资源不在仓库中

`entry/src/main/resources/rawfile/` 下的**游戏负载不纳入版本管理**，仓库只保留两个手写壳层文件：

| 纳入 Git | 说明 |
|:---|:---|
| `index.html` | 壳层入口页 |
| `touchPatch.js` | 触摸 / GP-Next 面板补丁 |

缺少下列内容时，工程**可以编译通过，但运行会白屏**：

| 缺失内容 | 说明 |
|:---|:---|
| `rawfile/assets/` | Cocos 资源包（本分支约 576 MB） |
| `rawfile/cocos-js/` | Cocos 引擎运行时 |
| `rawfile/src/` | `settings.json` 等构建配置 |
| `rawfile/application.js`、`index.js`、`style.css` | Cocos 构建产物 |

**获取方式**：从本仓库 [Release](https://github.com/WingedFin1251/Pvz-Gardendless-harmony/releases)
下载对应 HAP（解压后取其中的 `rawfile/`），或从 [pvzge.com](https://pvzge.com/) 获取游戏资源，放入
`entry/src/main/resources/rawfile/` 即可。

---

## 架构

采用 **ArkTS 原生壳层 + ArkWeb 承载 Cocos 构建产物**：游戏本体运行在 Web 容器内（虚拟域 `https://cocos.local/`），
ArkTS 侧负责窗口、资源、存档与文件能力。

| 模块 | 职责 |
|:---|:---|
| `entryability/EntryAbility.ets` | 主 Ability。沉浸式全屏与横屏；`2in1` 上改用 `maximize()` 进入全屏；初始化 Web 多进程渲染、响应内存压力回收 |
| `entrybackupability/EntryBackupAbility.ets` | 备份扩展（配合 `backup_config.json`） |
| `pages/Index.ets` | 页面主体。Web 组件（`ASYNC_RENDER` 异步渲染）、`cocos.local` 请求拦截、外链转系统浏览器、下载委托与文件保存、`NativeStorage` 存档代理；GP-Next 相关：`javaScriptOnDocumentStart` 注入兼容层、`registerJavaScriptProxy` 注册原生桥、自绘 JS 对话框（`onAlert/onConfirm/onPrompt`）、`multiWindowAccess` + `onWindowNew` |
| `pages/FilePickerHelper.ets` | 文件选择与公共目录保存；数据包导入（`fileSuffixFilters` 限定 `.zip` / `.json` / `.json5`，最多 20 个） |
| `utils/GpNextShim.ets` | **GP-Next 兼容层**（注入到页面 document-start）：抢先定义 `window.__TAURI_INTERNALS__`，使 payload 自带的 localStorage 假文件系统在 `if (!window.__TAURI_INTERNALS__)` 处自动让位；负责 `read_file` / `read_text_file` 的字节还原（base64 → `Uint8Array`）、`write_text_file` 的三参 `headers.path` 语义、以及 `plugin:window\|*` 的页面真值（视口 / DPR / 焦点 / 可见性） |
| `utils/GpNextBridge.ets` | **GP-Next 原生桥**：把 `plugin:fs\|*`、`plugin:dialog\|save`、`plugin:opener\|*` 落到 `filesDir/gp-next/{packs,patches,__gpn_edits}`；含数据包 zip 导入（解压 → 校验 `pack.json` → 改名入库）、另存为、性能页原生快照；路径限定在应用私有目录，未兼容命令**刻意抛错**而非静默成功 |
| `utils/ResourceManager.ets` | rawfile 资源 LRU 缓存：80 MB / 300 项上限、10 秒超时、连续失败 3 次跳过、音频不入缓存 |
| `utils/PerformanceMonitor.ets` | 性能埋点：帧率采样，以及渲染 / 资源加载 / 缓存命中 / 错误 / 内存告警事件 |

关键实现要点：

- **资源链路**：`onInterceptRequest` 拦截 `https://cocos.local/*` 请求 → 命中 `ResourceManager` 缓存则直接返回 →
  未命中则读取 `$rawfile` 并回填缓存；网络请求与 `data:` / `blob:` 等协议放行。
- **存档持久化**：通过 `registerJavaScriptProxy` 向页面暴露 `NativeStorage.saveToNative` / `loadFromNative`，
  底层使用 `preferences`（`game_save`）落盘。
- **多设备适配**：`setWindowSystemBarEnable`、`setPreferredOrientation`、`overviewModeAccess` 在 `2in1`
  上按官方文档属「不生效也不报错」，已在调用点用 `// @SuppressWarnings syscap` 抑制相应多设备告警。

---

## GP-Next 面板

面板前端来自官方客户端版内置的 **GP-Next v1.4.6**（原本是跑在 Tauri 桌面容器里的 Web 应用，
所有文件 / 对话框 / 外链能力都经 `window.__TAURI_INTERNALS__.invoke()` 打到 Rust 后端）。
本分支把它整体搬到 ArkWeb：注入兼容层 + ArkTS 原生桥，使面板**全部功能**可用，而不只是修改器。

面板入口是壳层右上角的浮动 GP 按钮（设置页也支持热键，需外接键盘）。数据根目录为
`<filesDir>/gp-next/`（`packs/` 数据包、`patches/` 单文件补丁、`__gpn_edits/` 手动编辑、`settings.json`）。

**已在真机（HUAWEI DMG-W00 / OpenHarmony 6.1.1）验证：**

| 能力 | 状态 |
|:---|:---|
| 面板初始化（phase 1–4 全通）与 10 个页签 | ✅ |
| 数据包：系统选择器导入 `.zip` / 单文件 `.json` → 扫描 → 应用 | ✅ 含应用后回读游戏内存资产的数值核对（`aliases` 匹配、默认 merge） |
| 面板内"重新加载所有补丁"重扫 | ✅ |
| 设置项与游戏存档跨重启持久化 | ✅ |
| 写 / 读 / 列目录 / 递归删除 / 存在性判断（fs 全能力） | ✅ |
| 修改器、内置语言包、植物注册表、商店扩展、滚动接管 | ✅（GP-Next 自身 JS，壳层无需介入） |
| 更新检查、外链跳转 | ✅ |
| 性能页「原生指标」 | ✅ 原生桥提供 OS / 架构 / 应用版本 / PID；进程 CPU 与系统内存 HarmonyOS 未向三方应用开放 → 显示「预热中 / 不可用」 |

**尚未验证 / 已知缺口：**

| 项 | 说明 |
|:---|:---|
| 手动编辑（数据页逐项编辑） | ⚠️ 落盘链路（写 `__gpn_edits/`）已验，面板内逐项编辑未逐步点过 |
| 另存为导出 | ⚠️ 原生侧就绪（系统保存对话框 + 写完后复制到用户位置），未实测 |
| 数据包封面 `thumbnail.png` | ⚠️ 桥按字节读取（≤128×128 才会显示），未实测 |
| JS 模组（实验性 → jsModding） | ⚠️ 读源码与落盘链路已通；加载用 `URL.createObjectURL` + 动态 `import(blob:)`，ArkWeb 是否放行待确认 |
| 云存档 | ⚠️ `crypto.subtle` 与 `window.open`（OAuth 弹窗）链路已具备，未实测 |
| 剪贴板 | ❌ 指南页「复制 UUID」、日志页「复制日志」、性能页「复制报告」使用 `navigator.clipboard`，ArkWeb 下需原生兜底（待做） |
| 每日挑战 | ⚠️ 走 `daily-level-api.pvzge.com`，未实测 |
| 桌面独占能力 | ➖ Discord RPC、macOS 菜单、窗口最大化 / 置顶 / 光标等 50+ 命令在移动端为安全默认值或静默桩 |

> **改代码前必读的一个坑**：ArkWeb 的 `registerJavaScriptProxy` 返回的是**原生 JSPromise**，
> 它的 `.then()` **不是标准 Promise 链**——回调返回值会被丢弃并恒定解析成 `null`。
> 必须先 `Promise.resolve(...)` 归一后挂 `.then()`；否则 `read_dir` 会变成 `null`，
> GP-Next 的 `discoverPacks` 立刻抛 `TypeError: n is not iterable`，初始化卡在 phase-3
> （补丁 / 数据 / 模组页全部不可用）。

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
│   │   │   └── utils/              # 资源缓存、性能监控、GP-Next 兼容层与原生桥
│   │   ├── module.json5            # 设备类型、Ability、页面配置（含 INTERNET 权限）
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

1. 克隆本分支：`git clone -b lite https://github.com/WingedFin1251/Pvz-Gardendless-harmony.git`
2. **放入游戏资源**（见上文「游戏资源不在仓库中」）
3. 使用 DevEco Studio 打开工程
4. 在 `File → Project Structure → Signing Configs` **重新生成签名**——包名为 `com.gardendless.lite`，
   需与 AppGallery Connect 中的应用条目一致，直接沿用其它分支的签名会因包名不匹配而失败
5. 连接设备或启动模拟器，点击运行

### 命令行构建

```bash
export DEVECO_SDK_HOME="<DevEco 安装目录>/sdk"

"<DevEco 安装目录>/tools/hvigor/bin/hvigorw" \
  --mode module -p product=default -p module=entry@default assembleHap --no-daemon
```

未配置签名时产物为 `dist/pvzge-lite-<版本>.hap`（unsigned）；配置后会额外输出 `…-signed.hap`。

> `DEVECO_SDK_HOME` 必须指向 **sdk 根目录**；若指向 `sdk/default/openharmony` 子目录，
> 会报错 `00303312 Cannot find the corresponding SDK version`。

---

## 文档

| 文档 | 内容 |
|:---|:---|
| [docs/REPOS.md](docs/REPOS.md) | 产物关系：定位、共享 / 身份文件划分、同步方式 |
| [docs/BUILD.md](docs/BUILD.md) | 构建配置、签名、部署、游戏资源说明、常见问题 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 架构说明 |
| [docs/MODULES.md](docs/MODULES.md) | 模块划分与职责 |
| [docs/ASPECT_RATIO.md](docs/ASPECT_RATIO.md) | 画面比例方案记录 |
| [docs/WEBVIEW_PERF.md](docs/WEBVIEW_PERF.md) | **ArkWeb 性能**：内核版本对应、负载实测、壳层问题清单与优化优先级 |
| [docs/RELEASE_v0.14.0.md](docs/RELEASE_v0.14.0.md) | v0.14.0 更新说明 |
| [docs/PERFORMANCE_OPTIMIZATION.md](docs/PERFORMANCE_OPTIMIZATION.md) | 性能优化方案 |
| [docs/PERFORMANCE_OPTIMIZATION_SUMMARY.md](docs/PERFORMANCE_OPTIMIZATION_SUMMARY.md) | 性能优化总结 |

---

## 已知限制

- **游戏资源需自行放置**：克隆后直接构建运行会白屏。
- **`2in1` 形态的能力差异**：系统栏隐藏与窗口方向锁定在该形态下不适用（已改用最大化 + 全屏）；
  `overviewModeAccess` 无效果。
- **GP-Next 面板为桌面版 UI**：触屏可用，但布局按桌面窗口设计；无物理键盘时热键不可用，
  请用壳层浮动按钮打开面板。
- **移动端拿不到的系统指标**：进程 CPU 与系统内存没有面向三方应用的公开接口，
  性能页这两项恒为「预热中 / 不可用」；进程内存尝试读 `/proc/self/statm`，沙箱通常禁止。

---

## 许可与致谢

- **原作**：[PvZ2 Gardendless](https://pvzge.com/)（植物大战僵尸 2 无花园重制版），
  原版 Gardendless 仓库 [Gzh0821/pvzge_web](https://github.com/Gzh0821/pvzge_web)，
  遵循 pvzge.com 社群授权协议。**非 EA / PopCap 官方产品**。
- **GP-Next**：面板前端由 GP-Next 项目提供（v1.4.6），版权归其作者所有；本分支只做运行环境适配，未修改其前端逻辑。
- **主仓库**：本分支与 [WingedFin1251/Pvz-Gardendless-harmony](https://github.com/WingedFin1251/Pvz-Gardendless-harmony)
  同源（同一作者维护）。
- **许可证**：本仓库以 **GPL-3.0** 授权，完整许可文本见 [`LICENSE`](LICENSE)。
  作为 GPL-3.0 的衍生作品对外分发时，须同时提供完整对应源码；本仓库已包含全部壳层源码，
  游戏负载为第三方内容、不随仓库分发（见上文说明）。
- **游戏素材**：版权归原作者所有，仅用于学习与技术交流。
- **贡献**：欢迎 Issue / PR。Fork 后新建分支（`feature/xxx`、`fix/xxx`），
  遵循 ArkTS 与鸿蒙工程规范，提交 PR 时附清晰说明。
- **免责声明**：本项目为非官方开源移植作品，仅供学习与技术交流，**严禁用于商业用途**；
  使用需遵守当地法律法规与原版社群协议，因使用产生的风险由使用者自行承担。
