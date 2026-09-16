# Gardendless for HarmonyOS v0.14.0 (fix1)

> 基于原版游戏 **PvZ2 Gardendless v0.14.0**（原版构建名 `PvZ2_Prerelease_AF_P5`）
> 发布日期：2026-09-16 ｜ 对应提交：`f44a084`

本次是 **v0.14.0 的修订版（fix1）**：游戏内容与 v0.14.0 一致，改动集中在**壳层稳定性、窗口适配与工程整理**，
并首次同时提供三个发行版的产物。

---

## 📦 下载与三个发行版

| 产物 | 应用名 | 包名 | 大小 | SHA256 |
|:---|:---|:---|:---|:---|
| `pvzge-0.14.0.hap` | Gardendless | `com.Pvz2.gardendless` | 1282.57 MB | `726420fe51dfcabd7732dcd11f02a94be5cedabba3fc6ff640af70d8dd6d371f` |
| `pvzge-lite-0.14.0.hap` | Gardendless Lite | `com.gardendless.lite` | 580.13 MB | `d56ca212c0b932f98944a574a8f6ed342f2dc81ad3bb99a511b96bc284a049de` |
| `pvzge-gpnext-0.14.0.hap` | Gardendless GP-Next | `com.gardendless.gpnext` | 1394.42 MB | `a95489e3c4718c373fb36359dfec86af6390d5ac01134f1dcc789dd0884256ce` |

- 三者**包名不同，可共存安装**，按需下载即可。
- 三个产物均为**未签名包**，安装前需自行签名（见下文）。
- 元数据：`versionName` `0.14.0` ／ `versionCode` `1000007`。
- 校验方式：`sha256sum pvzge-0.14.0.hap`（Windows：`Get-FileHash <文件> -Algorithm SHA256`）。

---

## 🔧 本次（fix1）改动

### 壳层

- **新增画面比例约束 3:2 ~ 17:9**：Web 视口按区间居中，超出部分由壳层补黑边；
  用 `onAreaChange` 实测容器尺寸（小窗 / 分屏 / 2in1 场景下同样正确），`parseVp` 兜底带单位字符串。
- **2in1（PC）形态适配**：`setWindowSystemBarEnable` 与 `setPreferredOrientation` 在 2in1 上不生效，
  改用 `maximize()` 进入沉浸式全屏，并跳过窗口方向设置。
- **修复启动竞态**：改为先 `loadContent` 再配置窗口（官方要求 `setWindowBackgroundColor()`
  在 `loadContent()` 生效后调用）。
- **移除失效的隐形入口**：早期在 `(0, 0)` 放置的 30×30 透明按钮恒为死代码，
  且会吞掉画面左上角 30×30 区域的游戏点击，已删除。
- `getRawFile`（API 9 起废弃）改用 `getRawFileContent`。

### 工程与构建

- 游戏负载（`rawfile/`）不纳入版本管理，仓库只保留 `index.html`、`touchPatch.js` 两个手写壳层文件。
- 构建产物自动命名：`dist/pvzge[-变体]-<版本>.hap`；未签名包为主产物，
  若工程配置了签名则额外输出 `…-signed.hap`。
- 仓库中的 `build-profile.json5` 不含签名配置，因此**默认构建产出 unsigned HAP**。

### 文档

- 新增 `LICENSE`（GPL-3.0）、`README`、`docs/ASPECT_RATIO.md`（比例方案）、
  `docs/WEBVIEW_PERF.md`（ArkWeb 内核版本、负载实测与优化清单）。

---

## 📲 安装说明

三个产物均为**未签名包**，需先用你自己的签名材料签名，例如：

1. 用 DevEco Studio 打开工程 → `File → Project Structure → Signing Configs` 配置本机签名
   → `Build → Build Hap(s)/APP(s)`；或
2. 使用 SDK 自带工具 `hap-sign-tool.jar` 直接对 HAP 签名。

安装相关：

- HarmonyOS NEXT 中通过自签名方式侧载的应用**默认有效期为 14 天**，完成
  [开发者实名认证](https://developer.huawei.com/consumer/cn/verified/enrollment) 后可延长至 **180 天**。
- 也可使用 [小白调试助手 Auto-installer](https://github.com/likuai2010/auto-installer) 进行安装。
- **存档**：覆盖安装即可继承历史存档。

---

## ⚠️ 注意事项

- 游戏设计分辨率为 1024×640（16:10）。当容器取到下限 3:2 时，游戏画面在 Canvas 内部加**上下**黑边，
  实际占用约为 **93.75%**；取到上限 17:9 时内部加**左右**黑边。
  区间下限越低，视口越高但游戏画面越小，这是本版本的取舍方向。
- **已知问题**：音频偶发不稳定为**原版游戏本身的已知问题**，并非本壳层引入。
- 环境要求：ArkWeb 内核需为 Chromium 114 或更高版本（HarmonyOS 5.0 及以上均满足）。

---

## 📄 许可

- 本移植项目以 **GPL-3.0** 授权，完整文本见仓库根目录 [`LICENSE`](https://github.com/WingedFin1251/Pvz-Gardendless-harmony/blob/main/LICENSE)。
- 原版 **PvZ2 Gardendless**：[pvzge.com](https://pvzge.com/) ／
  [Gzh0821/pvzge_web](https://github.com/Gzh0821/pvzge_web)，遵循其社群授权协议。
- 游戏素材版权归原作者所有。本项目为非官方爱好者移植作品，仅供学习与技术交流，**严禁用于商业用途**。
