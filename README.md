# Gardendless for HarmonyOS

本项目把 [PvZ2 Gardendless](https://pvzge.com/)（植物大战僵尸 2 无花园重制版，原版仓库
[Gzh0821/pvzge_web](https://github.com/Gzh0821/pvzge_web)）迁移适配到 **HarmonyOS / OpenHarmony**：
ArkTS 原生壳层 + ArkWeb 承载 Cocos 构建产物。仓库地址
[WingedFin1251/Pvz-Gardendless-harmony](https://github.com/WingedFin1251/Pvz-Gardendless-harmony)。

| | |
|:---|:---|
| 应用名 | **Gardendless**（Ability 标签 `Pvz2 Gardendless`） |
| 包名 | `com.Pvz2.gardendless` |
| 版本 | `0.14.0`（versionCode `1000007`） |
| 设备类型 | `phone`、`tablet`、`2in1` |
| SDK | `compatibleSdkVersion` 6.0.0(20) ／ `targetSdkVersion` 6.0.2(22) |

> **非 EA / PopCap 官方产品**，为爱好者社群的开源移植项目。
>
> 本仓库是**基础版**：游戏内**不含 GP-Next**（没有 GP-Next 面板与入口按钮）。
> 带 GP-Next 的变体是另外两个独立仓库，各自使用不同包名，可与本应用共存安装。

---

## 壳层能力

| 文件 | 内容 |
|:---|:---|
| `entry/src/main/ets/pages/Index.ets` | **画面比例约束 3:2 ~ 17:9**（超出区间由壳层补黑边，逻辑对齐安卓版 `AspectRatioFrameLayout`）：`onAreaChange` 实测容器尺寸、`parseVp` 兜底带单位字符串、Web 用 `width/height/position` 居中；根容器 `Stack`，状态提示叠加在画面顶部并放行触摸；不含早期版本遗留的 30×30 透明 GP-Next 调试按钮（负载中无 `gpNext` 挂载点，恒为死代码，且会吞掉画面左上角的游戏点击） |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 先 `loadContent` 再配置窗口（官方要求 `setWindowBackgroundColor()` 在 `loadContent()` 生效后调用，原实现并发存在竞态）；`IS_2IN1` 分流：`2in1` 改用 `maximize()` 进入沉浸式全屏并跳过方向设置 |
| `entry/src/main/ets/utils/ResourceManager.ets` | `getRawFile`（API 9 起废弃）→ `getRawFileContent` |

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

> 负载构成（v0.14.0 实测：PNG 纹理 619 个 796.9 MB、MP3 音频 4185 个 330.7 MB、JSON 3549 个 78 MB，
> 合计 1278.9 MB / 8394 个文件）与 ArkWeb 侧的优化清单，见 [docs/WEBVIEW_PERF.md](docs/WEBVIEW_PERF.md)。

---

## 构建

**先配置签名**：仓库中的 `build-profile.json5` 不含 `signingConfigs`（避免提交本机路径与签名材料）。
请在 DevEco Studio 的 `File → Project Structure → Signing Configs` 中为本机生成签名配置，
否则 `SignHap` 步骤会失败。

1. 克隆本仓库
2. 放入游戏负载（见上文）
3. 用 DevEco Studio 打开工程，配置签名
4. 连接设备或启动模拟器，点击运行

命令行构建（未配置签名时产物为 unsigned HAP）：

```bash
export DEVECO_SDK_HOME="<DevEco 安装目录>/sdk"

"<DevEco 安装目录>/tools/hvigor/bin/hvigorw" \
  --mode module -p product=default -p module=entry@default assembleHap --no-daemon
```

> `DEVECO_SDK_HOME` 必须指向 **sdk 根目录**；若指向 `sdk/default/openharmony` 子目录，
> 会报错 `00303312 Cannot find the corresponding SDK version`。
>
> 签名 profile 按包名绑定；若修改了 `bundleName`，需重新生成签名配置。

---

## 文档

见 [docs/README.md](docs/README.md)：架构、模块划分、构建与签名、画面比例方案、ArkWeb 性能清单。

---

## 许可与致谢

- **原作**：[PvZ2 Gardendless](https://pvzge.com/)（植物大战僵尸 2 无花园重制版），
  原版仓库 [Gzh0821/pvzge_web](https://github.com/Gzh0821/pvzge_web)，
  遵循 pvzge.com 社群授权协议。**非 EA / PopCap 官方产品**。
- **许可证**：本项目以 **GPL-3.0** 授权，完整许可文本见 [`LICENSE`](LICENSE)。
  对外分发时须同时提供完整对应源码（本仓库包含全部壳层源码；游戏负载为第三方内容、不随仓库分发）。
- **游戏素材**：版权归原作者所有，仅用于学习与技术交流。
- **免责声明**：本项目为非官方开源移植作品，仅供学习与技术交流，**严禁用于商业用途**；
  使用需遵守当地法律法规与原版社群协议，因使用产生的风险由使用者自行承担。
