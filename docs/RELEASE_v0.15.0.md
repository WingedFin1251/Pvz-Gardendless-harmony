# Gardendless 鸿蒙版 v0.15.0 更新说明

> 同步原版游戏 **PvZ2 Gardendless v0.15.0**
> 更新日期：2026-09-29
>
> **变体状态**：`main` 与 `gpnext` 已升到 0.15.0；**`lite` 暂缓**——0.15.0 的 lite 构建改用
> **AVIF** 纹理，而鸿蒙 ArkWeb 无法解码 AVIF（详见下文第三节），故 lite 保持 0.14.0 负载 + 本版壳层修复。
>
> 本文只列**本仓库可验证的差异**；原版游戏内容（新关卡 / 新植物 / 平衡性等）请见官方发布渠道。

---

## ⚠️ 从上一版开始：游戏负载放在 `rawfile/game/`

- 游戏负载（**含它自带的 `index.html`**）整体放在 `entry/src/main/resources/rawfile/game/`，
  `rawfile/` 根目录只留壳层自己提供的 `touchPatch.js`。
- **更新负载 = 替换 `rawfile/game/` 目录**：不再需要改 `index.html`，也不再需要重新注入触摸补丁。
- 详见 [BUILD.md](BUILD.md) 的「负载目录约定与更新流程」。

---

## 🚫 lite 为什么暂缓：鸿蒙 ArkWeb 不支持 AVIF

0.15.0 的 lite 构建把纹理从 `astc` 换成了 **`avif`**（602 个）、音频从 `ogg` 换成 `m4a` + `mp3`。
在真机上表现是：**引擎能起来（`cc=true`、帧数在涨）但资源加载永远卡住**，GP-Next 面板一直显示
「Waiting for engine…」，日志里是

```
WARN engine: Engine still loading after 30000ms; continuing to wait
(cc=true, assets=32, data=missing=PlantFeatures,ZombieFeatures,ProjectileFeatures,
 PlantProps,ZombieProps,ProjectileProps, scene=unavailable, language=false)
```

逐层排查结论（均为真机实测）：

| 检查 | 结果 |
| :--- | :--- |
| AVIF 文件本身 | **合法**：容器头 `ftyp` + 品牌 `avif`，兼容品牌 `avifmif1miafMA1A` |
| HTTP 传输 | 正常：`fetch` 得到 1866 B / `image/avif`（补齐 MIME 映射后） |
| **`createImageBitmap(blob)`** | **`InvalidStateError: The source image could not be decoded`** |
| **`<img>.src = <该 avif>`** | **onerror**（两张不同文件都失败） |
| Cocos 报错 | **Error 4930**（图片解码失败），同一贴图重试 10 次 |
| ArkWeb 能否解码 WebP / PNG | **可以**（`.webp` 603 KB → 950×600 ✓、`.png` ✓） |

即 **ArkWeb（实测 ArkWeb/7.0.0.107，Chrome 144 内核）没有 AVIF 解码器**，
这不是壳层能绕过的问题（`<img>` 与 `createImageBitmap` 两条解码路径都失败）。
lite 的负载因此**回退到 0.14.0（ASTC + OGG）**，本版只带壳层修复。

> 可能的后续路线（未实施）：① 请上游提供 WebP/ASTC 编码的 lite 构建（最干净）；
> ② 本地把 602 张 AVIF 转成 WebP 再重打包（Pillow 12.3 支持 AVIF 读取，WebP 已被 ArkWeb 验证可解码；
> 代价是负载变成"自制衍生品"，且需同步资源索引）。

---

## 📦 负载变化（与 0.14.0 逐文件比对）

| 变体 | 负载大小 | 文件数 | 新增 | 删除 | 变更 | 主要变化 |
| :--- | ---: | ---: | ---: | ---: | ---: | :--- |
| `main`（网页版，PNG + MP3） | 1.25 GB | 8438 | 61 | 16 | 130 | `.json` 168、`.png` 19、`.mp3` 2、`index.html` |
| `gpnext`（全量，PNG + MP3） | 1.25 GB | 8512 | 128 | 55 | 130 | `.json` 168、`.js` 68、`.png` 19、`.mp3` 2 |
| `lite` | 0.56 GB | 8438 | — | — | — | **保持 0.14.0**（ASTC + OGG），见上节 |

- **引擎与配置未变**：`cocos-js/`、`src/`（含 `settings.json`）、`application.js`、`index.js`、
  `style.css` 均与 0.14.0 **逐字节相同**。
- **GP-Next 升级到 v1.5.0-pre.1**：面板分组变为 模组 / 工具 / 数据 / 性能 / 日志 / 设置 / 实验性，
  新增 FPS 叠加、动态植物注册、商店扩展等设置项。

---

## 🔧 壳层修复（三个变体都带）

### 1. 补齐 0.15.0 需要的文件命令（**重要**）

0.15.0 的 Tauri 包**去掉了 `index.html` 里内联的 `__TAURI_INTERNALS__` polyfill**，改由宿主提供。
其中一条命令原先由那个 polyfill 用 localStorage 桩糊过去，polyfill 一撤就露出来了 ——
实测模组页直接报「未兼容的 GP-Next 命令：plugin:fs|lstat」。

本次在原生桥（`utils/GpNextBridge.ets`）里补齐
**`plugin:fs|lstat`、`plugin:fs|stat`、`plugin:fs|rename`、`plugin:fs|write_file`**，
并让 `lstat`/`stat` 按 Tauri 语义返回 `FileInfo`（`isFile` / `isDirectory` / `isSymlink` / `size` /
`mtime`…，时间戳由秒换算为毫秒）—— 0.15.0 的数据包加载器靠它逐级校验路径祖先。

### 2. 补齐 MIME 映射（**这条是定位 AVIF 问题时顺带修好的**）

拦截器原先的 MIME 表只有 `html/js/wasm/json/css/png/jpg/webp/svg`，**`default` 是 `text/plain`**。
0.15.0 引入 `.avif` / `.m4a` 后，这些二进制被当成 `text/plain` 返回。现补齐
`avif/gif/mp3/m4a/aac/ogg/wav/mp4/webm/ttf/otf/woff/woff2/txt/xml/csv`，
并把 `default` 改为 `application/octet-stream`。

> 注意：这条修复并不会让 AVIF **能解码**（ArkWeb 缺解码器），只是让响应头正确；
> lite 之所以仍暂缓，是因为解码器不存在，而不是 MIME。

---

## 📌 注意事项

- **存档自动继承**：直接覆盖安装即可。实测 `PvZ2_PlayerProperties`（约 100 KB）、`PvZ2_Settings`
  与已导入的 mod 包都还在；数据目录仍是 `/data/storage/el2/base/haps/entry/files/gp-next`。
- **必须重新构建**：`rawfile` 在构建时打进 HAP，只替换本地目录不会影响已安装的应用。
- 环境要求与已知问题同 v0.14.0：ArkWeb 内核需 Chromium 114+；音频偶发不稳定为原版已知问题。

---

## 🔢 版本

| 变体 | versionName | versionCode | 负载 |
| :--- | :--- | :--- | :--- |
| `main` | `0.15.0` | `1000008` | 0.15.0 |
| `gpnext` | `0.15.0` | `1000008` | 0.15.0 |
| `lite` | `0.14.0` | `1000008` | 0.14.0（暂缓，见上） |

---

## ✅ 本次实机验证（DMG-W00 / ArkWeb 7.0.0.107）

| 项目 | 结果 |
| :--- | :--- |
| 启动路径 | `https://cocos.local/game/index.html` 正常进入游戏场景 |
| GP-Next 面板 | 挂载成功，模组页列出已导入的包，**无加载错误**（补齐 `lstat` 后） |
| 原生文件桥 | `lstat`/`stat` 返回正确 `FileInfo`；`write_file` + `rename` 往返成功；不存在的路径报 `No such file or directory` |
| 触摸补丁 | 合成触摸产生 `mousedown`/`mouseup`/`mousemove` |
| 资源路径 | `/assets/index-<hash>.js`（根绝对）与 `/game/assets/...` 两种写法都取到同一文件且非空 |
| 存档 | 覆盖安装后存档与设置保留 |
| `lite` | 回退 0.14.0 负载后正常进游戏（ASTC + OGG） |
