# Gardendless for HarmonyOS v0.14.0 (fix2)

> 基于原版游戏 **PvZ2 Gardendless v0.14.0**（原版构建名 `PvZ2_Prerelease_AF_P5`）
> 发布日期：2026-09-17 ｜ 对应标签：`v0.14.0(fix2)`

本次是 **v0.14.0 的第二次修订（fix2）**：游戏内容与 v0.14.0 一致，改动集中在
**GP-Next 面板的完整适配** —— 此前内置的 GP-Next 面板只有「修改器」可用，其余页签全部失效。
另外三个产物自本版起改为**同一仓库的三个分支**发布。

---

## 📦 下载与三个发行版

| 产物 | 应用名 | 包名 | 大小 | SHA256 |
|:---|:---|:---|:---|:---|
| `pvzge-0.14.0.hap` | Gardendless | `com.Pvz2.gardendless` | 1282.57 MB | `726420fe51dfcabd7732dcd11f02a94be5cedabba3fc6ff640af70d8dd6d371f` |
| `pvzge-lite-0.14.0.hap` | Gardendless Lite | `com.gardendless.lite` | 580.22 MB | `e7e138e1a389b990a50ae8620d51ce2d2639900eeeda0ec8c3f232c82962440c` |
| `pvzge-gpnext-0.14.0.hap` | Gardendless GP-Next | `com.gardendless.gpnext` | 1394.51 MB | `d5dd913fd9077b21c0ed248af3da2f2b3b4fb1e5930edd586ac48ddf9f6592ba` |

- 基础版 `pvzge-0.14.0.hap` 的源码自 fix1 起未变动，**未重新构建**，校验值与 fix1 相同。
- 三者**包名不同，可共存安装**，按需下载即可。
- 三个产物均为**未签名包**，安装前需自行签名（见下文）。
- 元数据：`versionName` `0.14.0` ／ `versionCode` `1000007`。
- 校验方式：`sha256sum pvzge-0.14.0.hap`（Windows：`Get-FileHash <文件> -Algorithm SHA256`）。

### 各产物对应的源码分支

| 产物 | 分支 | 提交 |
|:---|:---|:---|
| `pvzge-0.14.0.hap` | `main` | 本标签所在提交 |
| `pvzge-lite-0.14.0.hap` | `lite` | `4439547` |
| `pvzge-gpnext-0.14.0.hap` | `gpnext` | `fb2803b` |

---

## 🔧 本次（fix2）改动

### GP-Next 面板完整适配（`lite` / `gpnext` 分支）

GP-Next 面板前端来自官方客户端版（v1.4.6，原本运行在 Tauri 桌面容器中，所有文件 / 对话框 / 外链能力
都经 `window.__TAURI_INTERNALS__.invoke()` 打到 Rust 后端）。本次补齐了它依赖的全部能力：

- **注入式兼容层**（`utils/GpNextShim.ets`）：在页面 document-start 抢先定义 `window.__TAURI_INTERNALS__`
  （payload 自带的 localStorage 假文件系统会自动让位），负责 `read_file` / `read_text_file` 的字节还原、
  `write_text_file` 的三参 `headers.path` 语义，以及 `plugin:window|*` 的真值（视口 / DPR / 焦点 / 可见性）；
  并直接开启「实验性 → JS Modding」。
- **原生桥**（`utils/GpNextBridge.ets`）：把 `plugin:fs|*`、`plugin:dialog|save`、`plugin:opener|*`
  落到应用私有目录 `<filesDir>/gp-next/{packs,patches,__gpn_edits}`，含数据包 ZIP 导入、另存为、
  性能页原生指标；未兼容命令**刻意抛错**而非静默成功。
- **数据包 / 补丁**：补丁页 →「打开目录」→ 系统文件选择器导入 `.zip` / `.json` / `.json5`（可多选，最多 20 个），
  ZIP 自动解压入库，导入后自动触发重扫；对象补丁按 `aliases` 匹配、默认 merge。
- **JS 模组可用**：第三方 `scripts/main.js` 真机执行成功，模组页显示 `Active API v2`。
  要求 `pack.json` 含 `"apiVersion": 2`，且模组导出 `setup(ctx)`（ctx 提供 40+ 命名空间）。
- **设置与存档持久化**：面板设置、`gp-next/settings.json`、游戏存档均可跨重启保留。
- **性能页「原生指标」**：由原生桥提供 OS / 架构 / 应用版本 / PID（CPU 与系统内存无三方公开接口，显示「预热中」）。

### 关键修复

- **修复面板初始化崩溃（最重要）**：ArkWeb 的 `registerJavaScriptProxy` 返回的是**原生 JSPromise**，
  它的 `.then()` 不是标准 Promise 链 —— 回调返回值会被丢弃并恒定解析成 `null`。于是 `read_dir` 变成 `null`，
  GP-Next 的 `discoverPacks` 立刻抛 `TypeError: n is not iterable`，初始化卡在 phase-3，
  补丁 / 数据 / 模组页全部报错不可用。已改为先 `Promise.resolve(...)` 归一、再挂 `.then()`。
- **日志降噪**：GP-Next 大量使用「探测式读取」（例如逐类型检查 `__gpn_edits` 里有无手工编辑覆盖），
  文件不存在属其正常分支，原先每条都打 ERROR、启动刷出上百行；现降为 debug。
- **目录创建健壮性**：`gp-next` 目录树改为逐个 try/catch 兜底，单个目录创建失败不再让原生桥注册中断。

### 工程与文档

- 三个产物改为**同一仓库三个分支**发布（`main` / `lite` / `gpnext`），共享同一套壳层源码；
  逐文件比对仅有 5 个文件属于应用身份或说明（`AppScope/app.json5`、两个 `string.json`、`README.md`、`docs/BUILD.md`）。
- README 新增：GP-Next 适配现状与真机验证清单、未验证 / 已知缺口表、JS 模组最小示例与格式要求、
  移动端连接 WebView 开发者工具的方法、外部 Mod 导入的平台限制说明。

---

## 📲 安装说明

三个产物均为**未签名包**，需先用你自己的签名材料签名，例如：

1. 用 DevEco Studio 打开对应分支的工程 → `File → Project Structure → Signing Configs` 配置本机签名
   → `Build → Build Hap(s)/APP(s)`；或
2. 使用 SDK 自带工具 `hap-sign-tool.jar` 直接对 HAP 签名。

> 注意 `lite` 与 `gpnext` 的**包名不同**（`com.gardendless.lite` / `com.gardendless.gpnext`），
> 需按各自包名生成签名，直接沿用别的分支的签名会因包名不匹配而失败。

安装相关：

- HarmonyOS NEXT 中通过自签名方式侧载的应用**默认有效期为 14 天**，完成
  [开发者实名认证](https://developer.huawei.com/consumer/cn/verified/enrollment) 后可延长至 **180 天**。
- 也可使用 [小白调试助手 Auto-installer](https://github.com/likuai2010/auto-installer) 进行安装。
- **存档**：覆盖安装即可继承历史存档；三者包名不同，互相之间存档独立。

---

## ⚠️ 注意事项与已知限制

- **GP-Next 面板为桌面版 UI**：触屏可用，但布局按桌面窗口设计；无物理键盘时热键不可用，
  请用壳层右上角的浮动 GP 按钮打开面板。
- **手机 / 平板上没有用户可见的 mods 目录**：HarmonyOS 的
  `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY` 官方标注「仅对 2in1 设备应用开放」，
  因此无法「把文件丢进某个文件夹就自动加载」；请使用面板的导入入口（补丁页 →「打开目录」）。
  数据根目录为应用私有 `<filesDir>/gp-next/`，面板会显示实际路径。
- **性能页部分指标不可用**：进程 CPU 与系统内存没有面向三方应用的公开接口，恒为「预热中 / 不可用」。
- **云存档与每日挑战**：依赖网络服务，本版未做端到端实测。
- **桌面独占能力**：Discord RPC、macOS 菜单、窗口最大化 / 置顶 / 光标等 50+ 命令在移动端为安全默认值或静默桩。
- **已知问题**：音频偶发不稳定为**原版游戏本身的已知问题**，并非本壳层引入。
- 环境要求：ArkWeb 内核需为 Chromium 114 或更高版本（HarmonyOS 5.0 及以上均满足）。
