# 仓库关系说明

本工程是一个**三仓库体系**：共用同一套壳层代码，区别在**游戏负载**与**应用身份**。

---

## 1. 三个仓库

| 仓库 | 定位 | 负载（`rawfile/`） | 壳层 | 包名 / 应用名 | 仓库状态 |
|:---|:---|:---|:---|:---|:---|
| `Gardendless` | **上游镜像 / 基础版** | 原版游戏，**无** GP-Next 前端 | 通用壳层改进（比例约束 3:2 ~ 17:9、2in1 适配、告警修复），**无** GP 按钮 | `com.Pvz2.gardendless` / Gardendless | 保留上游历史与 remote，可 `git pull` 上游；`.git` 约 1.6 GB |
| `Gardendless-lite` | **精简版 = 仓库精简的 GP-Next 版** | 含 GP-Next（wrapper + 50 个 Vite 分包） | 通用能力 + GP 按钮 | `com.gardendless.lite` / Gardendless Lite | 重建的精简历史；负载不入库；52 个跟踪文件；`.git` 约 0.7 MB |
| `Gardendless-gpnext` | **GP-Next 版**（独立应用身份，可与 lite 共存） | 同 lite | 同 lite | `com.gardendless.gpnext` / Gardendless GP-Next | 同 lite |

> **「精简」指仓库层面，不是功能层面。** 精简体现在：游戏负载（约 570 MB）不纳入版本管理、
> 丢弃上游 30+ 提交与 13 个 tag、跟踪文件从 8492 降到 52、`.git` 从 1.6 GB 降到 0.7 MB。
> **lite 与 gpnext 的功能完全一致**，区别只在应用身份。

---

## 2. 共享内容 vs 身份文件

lite 与 gpnext 逐文件比对后，**只有 6 个文件不同**，全部属于应用身份或签名：

| 文件 | 差异 |
|:---|:---|
| `AppScope/app.json5` | `bundleName` |
| `AppScope/resources/base/element/string.json` | `app_name`（桌面名称） |
| `entry/src/main/resources/base/element/string.json` | `EntryAbility_label`（桌面图标实际取此值） |
| `README.md` | 标题与事实表中的包名、应用名 |
| `docs/BUILD.md` | 包名引用 |
| `build-profile.json5` | 各自的签名 profile（按包名绑定） |

**除此之外的一切都应保持一致**：壳层源码（`entry/src/main/ets/**`）、其余文档、
`.gitignore`、以及 `rawfile/index.html` 与 `rawfile/touchPatch.js` 这两个被跟踪的负载文件。

---

## 3. 如何同步

以 lite 为源、同步到 gpnext（**按路径**同步，刻意排除身份文件）：

```bash
# 只需配置一次本地 remote（指向本地路径，比指向公开仓库安全）
git -C <gpnext> remote add lite <lite 仓库路径>
git -C <gpnext> fetch lite

# 每次同步
git -C <gpnext> checkout lite/main -- \
  entry/src/main/ets .gitignore \
  docs/MODULES.md docs/ASPECT_RATIO.md docs/ARCHITECTURE.md docs/REPOS.md \
  entry/src/main/resources/rawfile/index.html \
  entry/src/main/resources/rawfile/touchPatch.js
```

> ⚠️ **不要**整体 `checkout` 仓库根目录或整个 `docs/`——那会覆盖 `README.md` 与
> `docs/BUILD.md` 中的身份信息，导致两个应用变成同一个包名（互相覆盖安装，且签名不匹配）。

---

## 4. 注意事项

1. **`index.html` 是 GP-Next 专用资产，必须重点保护。**
   上游每次发版都会用**标准 Cocos 版**覆盖它，从而抹掉 wrapper 入口与内联 Tauri 垫片
   （`touchPatch.js` 的引用曾被同样抹掉，见 `RELEASE_v0.14.0.md`）。
   同步游戏资源后若 GP-Next 面板呼不出（按钮与键盘都不行），**第一件事就是对比这个文件**。
   GP-Next 原配版本的特征：`<script type="module" ... src="./assets/index-<hash>.js">`、
   内联的 `window.__TAURI_INTERNALS__` 垫片、**没有** `System.import('./index.js')`、**没有** `tmpPatch.js`。

2. **改包名必须重新签名。** 签名 profile 按包名绑定，需在 DevEco 的
   `Project Structure → Signing Configs` 重新生成，否则 `SignHap` 会因包名不匹配失败。

3. **三个仓库不要互相强推。** `Gardendless` 的 remote 指向公开上游仓库；
   lite / gpnext 目前**没有 remote**，发布前应各自新建，不要复用上游地址。

4. **基础版（`Gardendless`）已合并壳层的通用改进**（提交 `97c84fd`）：画面比例约束 3:2 ~ 17:9、
   `onAreaChange` 实测容器尺寸、2in1 窗口分流、`loadContent` 竞态修复、`getRawFileContent` 替换废弃接口。
   与 GP-Next 有关的部分（GP 按钮、铺满开关、`preferences` 键 `webview_fullscreen`）**不进入基础版**。
   此外基础版删除了一处上游遗留的 30×30 透明 GP-Next 调试按钮（基础版 payload 中没有任何 `gpNext`
   挂载点，该按钮恒为死代码，且会吞掉画面左上角的游戏点击）；
   若上游后续版本恢复该钩子，`git pull` 时需自行取舍。

5. **基础版与 lite / gpnext 的 `Index.ets` 不再逐行一致。** 基础版没有 GP 按钮及其状态
   （`GP_BUTTON_*`、`gpButtonHidden`、`isFillScreen`、`scheduleGpHide` 等）。
   从基础版往 lite / gpnext 同步壳层改动时，注意不要把这些符号一起带过去（反向同理）。
