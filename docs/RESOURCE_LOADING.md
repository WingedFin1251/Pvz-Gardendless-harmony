# 本地资源读取机制（负载资源 / 存档 / Mod 目录）

> 本文回答一个问题：**这个游戏的"本地资源"到底是怎么被读出来的？**
> 结论来自 2026-10-04 的代码走读 + 真机实测（`hilog -T JSAPP` 实时日志 + `hidumper --mem`）。
> 相关文档：[架构概览](ARCHITECTURE.md)、[模块清单](MODULES.md)、[比例留边](ASPECT_RATIO.md)

---

## 0. 先分清"三套体系"，不要混在一起

| 体系 | 读/写什么 | 走什么通道 | 代码位置 |
| :--- | :--- | :--- | :--- |
| **① 只读包资源**（游戏本体） | `rawfile/game/**`（HAP 约 1.35GB） | **URL 拦截**（壳层扮演 HTTP 服务器） | `services/PayloadServer.ets` + `services/ResourceManager.ets` |
| **② 可写沙箱**（GP-Next 的 mod / 配置） | `files/gp-next/**` | **JS 桥** `__gpNextNative.invoke` | `common/GpNextShim.ets` + `services/GpNextBridge.ets` |
| **③ 持久化**（存档 / 面板设置） | Preferences 库 `game_save` | 注入脚本 → `NativeStorage` 代理 | `resources/rawfile/touchPatch.js` + `services/PreferenceStore.ets` |

- ② **完全不经过**拦截器：它是 `fs` 读写真实目录。
- ③ 与资源读取无关，只负责"存档不丢"。
- **本文讲的都是 ①。**

---

## 1. 一句话总览

负载是 **Cocos 网页构建产物**：它的代码以为在访问 `https://cocos.local/...` 这样的**网址**，而**根本没有服务器**。
壳层因此**冒充这台服务器**——在 URL 层拦下每个请求，当场用包内文件作答。

```
Cocos 引擎/JS                      ArkWeb 内核                     我们的 ArkTS 壳层
  fetch / Image / <script>  ──▶   onInterceptRequest  ──▶        PayloadServer.serve()
        (URL 请求)                 (索要响应，必须同步)               │
                                                                    ├─ 路径翻译（前缀规则）
                                                                    ├─ ResourceManager.getCachedSync()   ← 内存命中？
                                                                    ├─ getRawFileContentSync()           ← 同步读包 + 回填缓存
                                                                    └─ $rawfile()                        ← 兜底（Resource 句柄）
                                 ◀── WebResourceResponse（数据 + MIME + 编码 + 200）──
   解码 / 编译 / WASM 实例化 ◀──
```

---

## 2. 第 1 层：拦截入口 —— 唯一强制约束是「必须同步」

`Web({ src: "https://cocos.local/game/index.html" })`，之后**每个子资源**（JS / WASM / JSON / PNG-AVIF / 音频 / 字体）
都会走 `Index.ets` 的 `.onInterceptRequest(...)`：

```ts
return PayloadServer.serve(
  event.request.getRequestUrl(),
  (path: string) => $rawfile(path),                 // 兜底：Resource 句柄
  (path: string) => this.readRawfileBytes(path));   // 同步字节读（用于回填 LRU）
```

**`onInterceptRequest` 要求当场返回响应，不能 `await`（官方文档的示例就是**直接 `return` 响应对象**；其回调类型为 `Callback<OnInterceptRequestEvent, WebResourceResponse>`，有返回值即意味着同步）。** 这一条决定了后面所有设计：

- 想"快" → 只能靠**内存里已经有字节**（LRU 缓存）
- 想"填缓存" → 只能用**同步**读（`getRawFileContentSync`），异步的 `getRawFileContent` 来不及

---

## 3. 第 2 层：URL → 包内路径（前缀规则）

```
https://cocos.local/assets/abc.js?ver=1
   │ ① 只处理 cocos.local；其它一律返回 null（交系统处理）
   │ ② 去掉 ?ver=1
   │ ③ decodeURIComponent
   ▼
/assets/abc.js ──「不以 game/ 开头、且不是壳层自留文件」──▶ game/assets/abc.js
```

- 需要补 `game/` 的原因：**负载自带的 `index.html` 用根绝对路径引用自己的模块**（`/assets/…`），
  而文件实际在 `rawfile/game/` 下。
- 壳层自留文件（`touchPatch.js`，在 rawfile 根）**不补**。常量：`PAYLOAD_DIR` / `SHELL_ROOT_FILES`。

---

## 4. 第 3 层：三条取数路径（核心）

| 顺序 | 路径 | 代价 | 何时走到 | 实测证据 |
| :-- | :--- | :--- | :--- | :--- |
| **1** | **LRU 命中** `getCachedSync()` | **零 I/O** | 该资源读过且未被淘汰 | 命中率约 **1%** |
| **2** | **同步字节读** `getRawFileContentSync()` → 建响应 **+ 回填缓存** | 一次包内读 | 首次请求（绝大多数） | 首屏 18 项 / 0.14MB → 稳态 300 项 / 59.59MB（淘汰修复前的稳态；修复后可涨到占满字节预算，实测 97%~99%）|
| **3** | **兜底** `$rawfile()`（返回 `Resource` 句柄交内核解析） | 一次包内读 | 同步字节读抛错时 | `game/favicon.ico → Invalid relative path`，自动降级，游戏照常 |

⇒ 稳态即"**边读边运行**"：多数走 2、热门走 1、个别异常路径走 3。

**两道闸（设计如此，不要随手放开）**

- 单品 **> 8MB 不入缓存**（= `maxSize * 0.1`（判定在 `ResourceManager.addToCache` 里，不在 PayloadServer））。实测跳过 8.24 / 10.31 / 17.38 / 13.21 MB 的纹理。
- **音频不入缓存**（浏览器音频引擎流式播放、不重复请求，缓存无收益且挤占空间）。

---

## 5. 第 4 层：构造响应（官方签名，已逐条核对 SDK `component/web.d.ts`）

`WebResourceResponse`（`@since 8`，方法均 `@since 9`）：

```ts
setResponseData(data: string | number | Resource | ArrayBuffer): void
setResponseEncoding(encoding: string): void
setResponseMimeType(mimeType: string): void
setResponseIsReady(IsReady: boolean): void
```

**官方就接受 `Resource` 与 `ArrayBuffer` 两种**，正好对应上面两条路径。

### ⚠️ 两条"用血换来的"规则

1. **MIME 必须对。** `mimeOf()` 按后缀映射，未知一律 `application/octet-stream`。
   > 事故：0.15.0 lite 用 `.avif` 纹理，当时默认给 `text/plain` ⇒ 图片解码失败
   > ⇒ 引擎卡在 "Waiting for engine…"。
2. **只有文本类才设 `utf-8`，二进制一律不设。**
   > 事故：给二进制也设了 `setResponseEncoding('utf-8')` ⇒ 内核**按文本解码字节** ⇒ 资源全坏
   > ⇒ **整包卡在 Cocos 引擎启动页**（引擎 JS 是文本所以能过，极具迷惑性）。

---

## 6. 第 5 层：内核侧（ArkWeb / Chromium）

- **网络栈被绕过**：没有 socket、没有 DNS。
- 按类型分流：JS → 编译；WASM → 实例化；图片 → 解码；音频 → 媒体管线；Cocos `import/*.json` → 资源系统。
- **解码后的资源占的是显存（GL）**，这是内存大头：

| 项 | 实测 PSS | 说明 |
| :--- | ---: | :--- |
| **GL** | **847 MB** | 解码后纹理 + 帧缓冲（绝对大头） |
| native heap | 205 MB | 原生堆（引擎资源、解码缓冲） |
| ark ts heap | 84 MB | ArkTS 堆 |
| Graph | 80 MB | 图形缓冲 |
| **`.hap`** | **0.5 MB** | **整个 1.35GB 的包只映射了 0.5MB ⇒ 包本体不会被读进内存** |

> **解码膨胀**：`4096×4096` 的图按 RGBA 解码 = `4096×4096×4` = **64MB**，而它的 PNG 可能只有 **8MB**（约 8 倍）。
> 这就是"1GB 级内存"的正常来源，**不是泄漏**。

---

## 7. 第 6 层：引擎侧（Cocos）

- 目录语义：`cocos-js/*.js` = 引擎；`assets/resources/import/*.json` = **资源元数据**；`native/*.png` = **实际纹理**。
- **按场景 / 按需加载（bundle + 懒加载）**，实测时间线（同一进程）：
  - `onPageEnd`（页面加载完成）时只有 **18 项 / 0.14MB**
  - 之后 4 秒才取 **8.24MB** 纹理，再往后 10.31 / 17.38MB
  - 运行中拉骨骼数据（`No armature data: backFire_blue`）
  - 运行中**反复重取**同一批（`resources/import/c9/…json` 三分钟后又来；`cloudSavePatcher-*.js`、`drpc-*.js`）
  - 占用从 0.17MB 一路长到 **59.59MB**

### 启动读取时序（刚启动时到底读了什么）

启动阶段读的**几乎全是「代码 + 配置」**，美术资源是启动**之后**才按需来的。证据来自负载自己的入口文件。

**阶段 0 —— 壳层先读（页面还未加载）**

| 读什么 | 怎么读 | 日志证据 |
| :--- | :--- | :--- |
| `touchPatch.js`（注入脚本） | `getRawFileContentSync('touchPatch.js')` | `注入脚本就绪: shim 6588 B + touchPatch 11563 B` |
| `game/index.html`、`game/src/settings.json` | 同上（**只做存在性自检**） | `负载自检通过: game/` |
| Preferences（面板设置 + 存档） | `shellPrefs` / `PreferenceStore` | `ResourceManager 已初始化` 前后 |

**阶段 1 —— `index.html` 解析：按 HTML 书写顺序逐个请求**

```
style.css                              1.3 KB
/assets/index-pjb0ePXN.js              启动入口（Vite 产物 type=module）
/assets/preload-helper-*.js            ┐
/assets/startup-recovery-session-*.js  │ modulepreload
/assets/cocos-startup-*.js             │（引擎启动前的准备模块）
/assets/startup-platform-*.js          ┘
src/polyfills.bundle.js                14.4 KB
src/system.bundle.js                   12.0 KB   SystemJS 加载器
src/import-map.json                    ~0 KB     告诉 SystemJS "cc 在哪"
```

**阶段 2 —— 引擎装配（配置 + 引擎本体 + 游戏逻辑）**

```
src/settings.json      2.8 KB   引擎总配置
cc 引擎                        经 import-map 加载 cocos-js/*（Cocos Creator 3.8.4 / web-mobile）
src/chunks/bundle.js           游戏逻辑（settings.json 的 scriptPackages 指定）
src/effect.bin         4 KB    渲染效果配置
```

`src/settings.json` 里几条关键值：

| 字段 | 值 | 含义 |
| :--- | :--- | :--- |
| `launch.launchScene` | `preSplashScene` | **第一个场景就是闪屏**（就是先看到的那张 Cocos 启动页） |
| `assets.preloadBundles` | `[resources, main]` | **启动只预加载这两个 bundle**，不是全部 |
| `projectBundles` | `internal, resources, main` | 全部 bundle 仅三个 |
| `downloadMaxConcurrency` | `15` | 并发 15 路（所以请求是一阵一阵爆发的） |
| `splashScreen.totalTime` | `2000` | 闪屏 2 秒 |
| `scripting.scriptPackages` | `../src/chunks/bundle.js` | 游戏逻辑包 |
| `designResolution` | `1024 × 640` | 设计分辨率（比例 1.6，落在留边区间内，不会被拉伸） |

**阶段 3 —— 进入启动场景，此时才开始读美术资源**

```
preSplashScene（闪屏）
   ↓
resources / main 两个 bundle 的资源
   ↓
game/assets/resources/import/*.json     资源【元数据】
game/assets/resources/native/*.png      资源【本体】
```

实测：`onPageEnd`（页面加载完成）时缓存里**只有 18 项 / 0.14MB** —— 因为此刻只读完阶段 1~2 的代码与配置；
之后 +4 秒才取 8.24MB 纹理，再往后 10.31MB / 17.38MB。

**阶段 4 —— 运行期（边读边跑）**

- 切场景 / 进关卡 → 取该场景图集与骨骼（`No armature data: backFire_blue` 即运行中拉骨骼数据）
- 界面与存档相关的 JS 被**反复重取**（`cloudSavePatcher-*.js`、`drpc-*.js`、`resources/import/*.json`）

> **一句话结论**：刚启动读的是「入口代码 + 引擎配置 + 引擎本体 + 游戏逻辑」这一小撮（外加浏览器自动请求的 `favicon.ico`），
> 美术资源是启动之后按场景/按需拉的 —— 最硬的证据就是页面加载完成时缓存只有 **18 项 / 0.14MB**，而运行一段时间后长到 **59.59MB**。

**同一时刻还有一套读取在跑（别混淆）**：负载里的 `startup-recovery-session` 模块会在启动时扫描 GP-Next 的 mod 目录，
但那条**不走资源拦截器**，而是走 **JS 桥**：

```
[gp-next-bridge] plugin:fs|read_dir 未命中: …/files/gp-next/packs/<mod>/assets
[gp-next-bridge] plugin:fs|read_file 未命中: …/files/gp-next/packs/<mod>/thumbnail.png
```

即：**同一次启动里两套体系同时在读** —— 包内只读资源（URL 拦截）与沙箱目录（JS 桥）。
---

## 8. 为什么**不可能**"启动时把所有内容读进内存"

| 原因 | 事实 |
| :--- | :--- |
| 包太大 | HAP **1.35GB**，全读等于爆内存 |
| 拦截器必须同步 | 预加载只能"提前读"，不能"替这次请求作答" |
| 解码会再膨胀约 8 倍 | 8~17MB 的纹理进 GL 就是几十~上百 MB（实测 GL 847MB） |
| 引擎本来就是懒加载 | 首屏只需 18 项 / 0.14MB |
| 内存里**没有**包本体 | `.hap` 只映射 0.5MB |

⇒ 正确策略是「**小而热的集合 + 淘汰**」（预算封顶 80MB，约占 1.3GB 的 4%）。

---

## 9. LRU 缓存（`services/ResourceManager.ets`）的设计与约束

- **预算**：总量 80MB、单品 ≤8MB、条数 ≤300、音频不入。
- **淘汰**：按 `lastAccessTime` 最早逐条淘汰（`evictLeastRecentlyUsed()`），并在 `CacheStats.evictedCount` 里计数。
- **为什么必须真淘汰**：这个负载是「**大量小文件反复要 + 少量巨型纹理只用一次**」，
  必须让反复要的那批**进得来**、巨型的那批**别进来**。
- ⚠️ **曾经的坑（已修）**：`addToCache` 在条数达上限后只调一次 `smartCleanup()` 然后**仍然拒绝**；
  而 `smartCleanup()` 第一句**只按字节占用率**判断（`cacheSize / maxSize < 0.8` 即 return），
  条数被卡住时字节占用只有约 74% ⇒ 它每次都**空转** ⇒ 条数上限一旦触到就**永久拒收**。
  修复后实测：`缓存项数已达上限` 警告消失，缓存占用率可涨到 97~99%，`smartCleanup` 按设计介入裁回约 60%。

---

## 10. 观测手段（复现本文结论的方法）

```powershell
# 1) 抓应用自己的日志 —— 必须按 tag 过滤 + 实时流式收！
#    游戏负载的 CEF/Chromium 日志极其海量，hilog -z 4000 大约只等于 1 秒噪音，
#    用 -z 事后捞会把 JSAPP 行挤出环形缓冲（本文档作者曾被此坑两轮）。
hdc -t <target> shell "hilog -T JSAPP | grep --line-buffered gardendless"

# 2) 内存（看 PSS，别看 ps 的 RSS：RSS 会把共享库在每个进程里重复计算）
hdc -t <target> shell "hidumper --mem <pid>"

# 3) 进程构成（主进程 + 渲染进程是不同进程）
hdc -t <target> shell "ps -A -o PID,PPID,RSS,NAME | grep -i <bundle>"
```

关键日志锚点：

| 日志 | 含义 |
| :--- | :--- |
| `[payload-cache] N 项, X MB, 命中率 Y%，淘汰 Z 次` | 在 `onPageEnd` / `onPageHide` 各打一次（切后台即可读） |
| `资源过大，跳过缓存: <path> (X MB)` | 单品超过预算，按设计不入缓存 |
| `同步读取失败，退回 $rawfile: <path>` | 走了兜底路径（例如 `game/favicon.ico`） |
| `缓存项数已达上限，无法缓存` | **正常情况下不应该再出现**；若出现说明淘汰逻辑被改坏了 |
| `开始智能清理缓存 / 智能清理完成` | 字节预算触顶后 `smartCleanup` 介入 |

---

## 11. 已知问题与待办（截至 2026-10-04）

| 级别 | 问题 | 状态 |
| :--- | :--- | :--- |
| 负载侧 | 负载会调用 `write_text_file` 却**完全不传路径**（`argsKeys=[__gpNextBytes] optionsKeys=[none] headersKeys=[none]`） | 已加**形状诊断日志** + 容忍"路径当第二参传字符串"；**根因在负载，我方只能给明确报错** |
| 待核实 | `calculateCacheScore()` 的排序方向可能是反的（公式 `size×(1/priority)/(freq×decay)` 升序 + 删前几个 ⇒ 会先删"小且频繁使用"的）。取决于 `priority` 的数值约定，**尚未确认** | 待核实 |
| 清理 | `ResourceManager` 12 个 public 方法中 7 个**零调用**（`preloadResources` / `preloadResource` / `getResource` / `clearCache` / `smartCleanup` / `setResourcePriority` / `getResourceInfo`） | 待决定"接上"还是"精简" |
| 清理 | `PerformanceMonitor` 442 行**零调用** | 待决定"接上"还是"删掉" |
| 测试 | 纯函数单测（`AspectRatio`）已写好但**未运行**（CLI 无法构建 ohosTest 测试包） | 需在 DevEco 里点 Run |

---

## 12. 维护红线（改这块之前先看这里）

1. **不要给二进制响应设 `setResponseEncoding`** —— 会让内核按文本解码，整包卡在启动页。
2. **不要让 `mimeOf()` 的默认值退化成 `text/plain`** —— `.avif` 纹理解码失败会让引擎停在 "Waiting for engine…"。
3. **不要去掉 `$rawfile` 兜底** —— 同步字节读对个别路径（如 `game/favicon.ico`）会抛 `Invalid relative path`。
4. **不要试图"预加载全部资源"** —— 1.35GB 包 + 约 8 倍解码膨胀，必然爆内存；拦截器还必须同步返回。
5. **不要用"满了就拒绝"替代淘汰** —— 会让运行中反复请求的那批永远进不来（本文档第 9 节）。
6. **改动后必须真机验证**：至少确认「能过启动页进入标题/关卡」+「无崩溃」+「`缓存项数已达上限` 不再出现」。
