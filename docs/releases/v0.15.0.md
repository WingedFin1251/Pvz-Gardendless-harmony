# Gardendless 鸿蒙版 v0.15.0

游戏内容同步上游 **PvZ2 Gardendless v0.15.0**：新增**超级机枪射手**（Merged 体系）、调整史诗关卡卡组；
本仓库侧补齐 0.15.0 负载所需的文件命令与 MIME 映射，并修正鸿蒙电脑上的窗口行为。

## 游戏内容更新（来自上游 v0.15.0）

### 1. 新增植物：超级机枪射手（Mega Gatling Pea）

- **史诗关卡植物**（`OBTAINWORLD: epic`），阳光 **200**，家族 Peashooter。
- 属于 **Merged（合并）体系**：数据里带 `SubPlantList`（`repeater_mgp` / `threepeater_mgp` /
  `splitpea_mgp` 等）与 `mgp_evolution` 进化配方，把多种机枪 / 双重射手形态合并到一起。
- 自带全新骨骼动画（`MegaGatlingPea`）与卡面。

### 2. 史诗关卡：推荐卡组与挑战卡组调整（社区制作）

修改了史诗关卡的推荐卡组与挑战卡组配置。

> 上游 0.15.0 的官方变更说明只有以上两条；其余均为壳层与打包侧适配（见下）。
> 引擎与脚本（`cocos-js/`、`src/`、`application.js`）与 0.14.0 逐字节一致，
> 本版负载改动集中在**数据与资源**（`.json` 168 个、`.png` 19 个、`.mp3` 2 个）。

## 下载与三个发行版

| 产物 | 应用名 | 包名 | 大小 | SHA256 |
| :--- | :--- | :--- | :--- | :--- |
| `pvzge-0.15.0.hap` | Pvz2 Gardendless | `com.Pvz2.gardendless` | 1285.83 MB | `d4a18bc20e3e4af98bc2327dcdcd75f4b3734f434fd68b44d4369808ec8163ee` |
| `pvzge-lite-0.14.0.hap` | Gardendless Lite | `com.gardendless.lite` | 580.32 MB | `f172112fa0abd9aa7a62dd015c21656018b97d48ae95927a7ae658f82bd381c6` |
| `pvzge-gpnext-0.15.0.hap` | Gardendless GP-Next | `com.gardendless.gpnext` | 1287.56 MB | `8cf0729ecf8e5a67c92671ea2b466de71b9801c53c97f69b978911053b41d297` |

- 三者包名不同，**可共存安装**，按需下载即可。
- 三个产物均为**未签名包**，安装前需自行签名（DevEco Studio 勾选自动签名后重新 Build，或用 `hap-sign-tool.jar` 重签）。
- **更新前建议备份存档**。
- `lite` 本次仍是 **0.14.0 负载**：0.15.0 的 lite 使用 AVIF 纹理，鸿蒙 ArkWeb 没有 AVIF 解码器，会卡在引擎初始化。

## 本仓库（壳层与打包）改动

- 补齐 0.15.0 负载需要的文件命令：`lstat` / `stat` / `rename` / `write_file`（缺 `lstat` 时模组页会报 1 项错误）。
- 补齐 MIME 映射（`avif` / `gif` / 音频 / 字体 / 文本等），未知类型回落到 `application/octet-stream`。
- 隐藏 GP-Next 面板左上角的热键提示徽标（F9）；面板开关与热键不受影响。
- 鸿蒙电脑（2in1）不再默认进入沉浸式全屏，改为**普通最大化**（保留任务栏与标题栏）。

## 版本与验证

| 变体 | versionName | versionCode | 负载 |
| :--- | :--- | :--- | :--- |
| `main` | `0.15.0` | `1000008` | 0.15.0 |
| `gpnext` | `0.15.0` | `1000008` | 0.15.0 |
| `lite` | `0.14.0` | `1000008` | 0.14.0（见上） |

- 平板 DMG-W00：正常进游戏；模组页无加载错误；存档与设置跨重启保留。
- 鸿蒙电脑 VM：窗口 `[0 0 3120 1955]`（普通最大化、任务栏保留）；产物安装 / 启动 / 包内版本校验通过。
- 三个产物分别构建自 `main@3e82383`、`lite@de2dbfc`、`gpnext@6ac1d9f`；技术细节见仓库 `docs/`。
