# WebView（ArkWeb）性能现状与优化清单

> 适用范围：三仓库共用（基础版 / GP-Next 版）。
> 本文只记录**可复核的事实**与明确结论；凡标注「**待实测**」的条目都表示需要真机数据才能定性，
> 不要当成已证实的收益。

---

## 1. 内核版本与外部基准

### 1.1 ArkWeb 内核版本对应关系（官方口径）

| 系统版本 | ArkWeb 内核 | 说明 |
|:---|:---|:---|
| OpenHarmony 4.0 及之前 | **M99** | |
| OpenHarmony 4.1 – 5.1（含 HarmonyOS NEXT 5.x） | **M114** | 长期主力版本 |
| OpenHarmony / HarmonyOS 6.0 | **M132**（默认「常青内核」）+ M114（遗留内核，可选） | 双内核方案；M114 仅作兼容性回滚，计划 **2026-Q2 禁用** |
| 6.1 及之后（API 23+） | `ARKWEB_EVERGREEN` 可取系统最新内核 | `@since 23` |

**实测方法**（不要靠印象写版本号）：

- 页面内 `navigator.userAgent`，形如
  `Mozilla/5.0 (Phone; OpenHarmony 6.0) ... Chrome/132.0.0.0 Safari/537.36 ArkWeb/6.0.0.44 Mobile`
- 应用内 `webview.WebviewController.getActiveWebEngineVersion()`（切换后用
  `setActiveWebEngineVersion()` 生效值可查）

### 1.2 本工程的内核策略

- 工程当前 `targetSdkVersion 6.0.2(22)`、`compatibleSdkVersion 6.0.0(20)`，**未调用**
  `setActiveWebEngineVersion()` → 走系统默认内核，在 6.0 上即 M132。**这是当前最优默认。**
- **不要 pin `M114`**：它是兼容性回滚用的遗留内核，功能冻结、有禁用期限，且降级前后需清理
  `.../cache/web` 缓存数据。
- `ARKWEB_EVERGREEN` 需要 API 23+，当前 target 22 不可用；将来提升 targetSdk 后可考虑，
  但仍应确认目标系统上存在对应内核（`isActiveWebEngineEvergreen()`）。

### 1.3 外部 Speedometer 观测（需注意口径）

| 测试环境 | 设备 / 系统 | 内核 | Speedometer | 备注 |
|:---|:---|:---|:---|:---|
| Edge（卓易通） | Mate60 / 鸿蒙 | Chromium 144 | 11.57 | 安卓兼容容器内的 Android 版 Edge |
| 系统 WebView | 小米10 / Android | Chromium 149（满血） | 9.51 | 作者已确认这行是「系统 WebView 149」；**下一行不是同一个浏览器**，见 §1.6 |
| ArkWeb | Mate60 / 鸿蒙6 | 应为 **M132**（原文写 ~120+，有误） | 6.84 | 鸿蒙当前水平 |
| Edge（小米10） | 小米10 / Android | Chromium 149 | 5.27 | **作者更正**：这是小米 10 用自带 Edge（内核 149）的分数，不是系统 WebView 的受限态；见 §1.6 |
| 系统 WebView | 小米10 / Android | Chromium 116 | 4.87 | Android 上 Maglev 当时仍在 `--future` 之后 |
| ArkWeb | 鸿蒙5 | 应为 **M114**（原文写 ~106，有误） | ~4.0 | |

使用这张表时必须带上四条限定：

1. **内核版本那两行是错的**，已按官方口径更正（见 1.1）。若鸿蒙6 实为 M132，则它与 Chromium 149
   的差距就不能归因于「内核老」，而更可能是 ArkWeb 自身的 V8 构建裁剪与系统调度/温控策略。
2. **噪声大于结论**：同为 Chromium 149 的两行差 45%，但作者已更正这两行并非同一个浏览器
   （9.51 = 系统 WebView，5.27 = 小米 10 的 Edge，见 §1.6），所以这个差值里混着浏览器栈差异与热状态，
   不能当作纯噪声估计；只有「Mate60 11.57 vs ArkWeb 6.84」这种量级才稳健。
3. **卓易通不是同一条软件栈**：它是在鸿蒙上运行 Android 应用的兼容容器，Edge 多带一层转译/容器开销。
   它能拿 11.57 恰好证明**硬件不是瓶颈**，但不能当作鸿蒙原生浏览器的对照。
4. **缺同机对照**：要拆开「引擎差」与「设备差」，需在同一台 Mate60 上跑三组——卓易通 Edge、
   系统自带浏览器（ArkWeb 内核）、本应用 WebView。**§1.6 已补上其中两组**（同一台鸿蒙设备上的
   ArkWeb M132 与卓易通 Edge 逐项对照），缺的只剩本应用 WebView 那一组。另外需确认各行使用同一
   Speedometer 版本（5~12 分这个量级对应 Speedometer 3.x）。**本工程自采的 ArkWeb 144 逐项时序基线
   见 §1.5** —— 那是毫秒时序而非 3.x 分数，两者不可换算。

### 1.4 为什么 Speedometer 不是本工程的验收指标

Speedometer 压的是 JS/DOM/现代框架的吞吐，而 Cocos 游戏几乎不使用 DOM 与现代前端框架。
真正映射到游戏体感的是三件事：**启动期的 JS 解析与编译、纹理解码与上传、GC 停顿**。
因此本工程的验收指标应为（见 §5），而不是 Speedometer 分数。

### 1.5 ArkWeb 144 / 鸿蒙 7 逐项时序基线（Speedometer，10 次重复）

§1.3 那些分数来自公开分享的**单次**观测，口径混杂、噪声大到无法排序。下表是本工程在一台真机上按
**10 次重复 + 95% 置信区间**采集的逐项时序，可作为**同口径基线**使用
（只有同设备、同 Speedometer 版本下的重测才具备可比性）。

- 设备：`HUAWEI BRA-AL00`（手机）
- 系统 / 内核：OpenHarmony **7.0** ／ ArkWeb **7.0.0.107**（Chromium **144.0.0.0**）
- UA：`Mozilla/5.0 (Phone; OpenHarmony 7.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36  ArkWeb/7.0.0.107 Mobile`
- 采样：每组 **10 次**；`delta` 为 95% 置信区间，`percentDelta` 为相对 CI（原始 metrics 见
  [`perf/speedometer-arkweb144-bra-al00.json`](perf/speedometer-arkweb144-bra-al00.json)）
- 单位 ms，**越小越好**

| 套件 | 总 mean | 相对 CI | Adding100Items | CompletingAllItems | DeletingAllItems |
|:---|---:|---:|:---|:---|:---|
| TodoMVC-JavaScript-ES5 | **154.72** | 8.1% | 101.81（Sync 79.66 / Async 22.16） | 34.20（21.41 / 12.79） | 18.71（16.74 / 1.98） |
| TodoMVC-JavaScript-ES6-Webpack-Complex-DOM | **117.03** | 4.3% | 62.31（49.64 / 12.67） | 35.81（22.36 / 13.45） | 18.91（16.10 / 2.81） |
| TodoMVC-WebComponents | **81.84** | 4.1% | 49.97（28.59 / 21.38） | 19.33（7.85 / 11.47） | 未采集（本轮输出末尾被截断） |

可以读出的三点：

1. **Async 占比随技术栈显著上升**：ES5 22%、ES6-Webpack 20%，而 WebComponents 达 **43%**
   （`Adding100Items` 异步 21.38 ms 已逼近同步 28.59 ms）。自定义元素与异步渲染路径在 ArkWeb 上相对更贵，
   这是与 Cocos 无关、但在 Web 侧值得留意的一条差异。
2. **数据质量明显优于 §1.3**：三套主结果的相对 CI 为 4.1%–8.1%；小项（如 ES5 `CompletingAllItems`
   绝对时间仅 34 ms）CI 才显大到 19.4%。这正是 §1.3 第 2 条所要求的"重复测量"做法。
3. **不可与 §1.3 互相换算**：§1.3 是 Speedometer 3.x 的**分数**（5~12 分），本表是逐项**毫秒时序**，
   测试集与计分口径都不同，只能各自纵向比较；把两者混用会得出错误结论。

---

### 1.6 多环境逐项时序对照（Speedometer 3，10 次重复）

同一批测试在五种环境下各跑一次（每组 10 次，`delta` 为 95% CI）。原始材料是作者提供的连续文本
（一份 270 KB 的粘贴 + 后来单独粘贴的一次），其中夹着环境标签，已按完整条目边界切分，并逐条做自洽
校验（用 `values` 重算 `mean / sum / min / max`，**五段全部一致**）。

> **2026-09-18 更正（重要）**：本节初版把标签认成「标注它后面那一段」，实际相反——原始粘贴里每个标签
> 都紧贴在**前一段被截断的数据尾部**（例如 `…27.63499` 后面直接跟 `卓易通edge149`）。按「标签描述其前
> 一段」重排后，五段才与 §1.3 的总分表、以及作者随后单独粘贴的第二轮数据三者同时对上：
> `arkweb132` 段反算 6.82 ≈ 表中 ArkWeb 6.84；`mi10-webview149` 段反算 9.47 ≈ 表中 9.51，且与第二轮
> 逐套件相差 ≤4%。文件已按新标签重命名，旧名记在各自的 `_meta.renamedFrom` 里。

| 标签 | 环境 | 原始文件 |
|:---|:---|:---|
| `arkweb132` | ArkWeb 内核 M132（按 §1.1，鸿蒙 6 的默认内核就是 M132） | [`perf/speedometer3-arkweb132.json`](perf/speedometer3-arkweb132.json) |
| `zhuoyitong-edge149` | 卓易通（Android 兼容容器）内的 Edge，Chromium 149 | [`perf/speedometer3-zhuoyitong-edge149.json`](perf/speedometer3-zhuoyitong-edge149.json) |
| `mi10-webview149`（第 1 轮） | 小米 10 + 系统 WebView 149 | [`perf/speedometer3-mi10-webview149.json`](perf/speedometer3-mi10-webview149.json) |
| `mi10-webview149`（第 2 轮） | 同上，作者另一次粘贴并原样给出总分 **9.51 ± 0.14** | [`perf/speedometer3-mi10-webview149-r2.json`](perf/speedometer3-mi10-webview149-r2.json) |
| `mi10-edge149` | 小米 10 + Edge（内核 149）——即作者所说「那个五点几跑分」的那次 | [`perf/speedometer3-mi10-edge149.json`](perf/speedometer3-mi10-edge149.json) |

单位 ms、**越小越快**；下表为各顶层套件的 10 次均值：

| 套件 | arkweb132 | 卓易通 edge149 | 小米10 WebView149① | 小米10 WebView149② | 小米10 Edge149 |
|:---|---:|---:|---:|---:|---:|
| TodoMVC-JavaScript-ES5 | 160.26 | 102.90 | 100.26 | 102.21 | 149.77 |
| TodoMVC-JavaScript-ES6-Webpack-Complex-DOM | 157.24 | 77.05 | 87.05 | 85.73 | **333.56** |
| TodoMVC-WebComponents | 99.25 | 48.82 | 64.31 | 64.55 | 141.70 |
| TodoMVC-React-Complex-DOM | 126.03 | 81.51 | 105.49 | 103.91 | 146.69 |
| TodoMVC-React-Redux | 136.04 | 97.27 | 112.00 | 109.47 | 172.10 |
| TodoMVC-Backbone | 121.49 | 80.92 | 97.53 | 94.74 | 127.44 |
| TodoMVC-Angular-Complex-DOM | 121.77 | 72.13 | 99.63 | 97.47 | 150.97 |
| TodoMVC-Vue | 102.00 | 63.04 | 68.66 | 65.99 | 110.47 |
| TodoMVC-jQuery | 410.10 | 279.50 | 289.15 | 283.99 | 430.05 |
| TodoMVC-Preact-Complex-DOM | —（截断） | —（截断） | 32.08 | 31.89 | —（截断） |
| **反算总分**（见下） | 6.82 | 10.69 | 9.47 | **9.62**（报告值 **9.51 ± 0.14**） | 5.57 |

**关于「反算总分」**：`docs/perf/` 存的是逐项毫秒，不是总分。若用
`1000 /（各顶层套件 mean 的算术平均）` 做粗换算，第 2 轮小米10 WebView149 得 **9.62**，与作者报告的
**9.51** 差 1.1%；同一把尺子去量其余各列，`arkweb132` 段得 6.82（§1.3 表 6.84）、小米10 Edge149 段得
5.57（表中 5.27）、卓易通段得 10.69（表中 11.57）。**这只是量级校验用的代理，不是 Speedometer 的官方
计分公式**，不要拿它去和其他机器的分数比大小。

读这份表必须带上四条限定：

1. **设备分成两组，但只有一组算得上同机对照**：Async 占比指纹把五列聚成两组——`arkweb132` 与
   `zhuoyitong-edge149`（WebComponents 38.5% / 43.7%，ES5 20.7% / 16.2%）据指纹推断同属一台鸿蒙设备，
   小米 10 的三列（28.1% / 29.5% / 65.6%）是另一组。因此「ArkWeb vs 卓易通 Edge」可以当同一台设备上的
   浏览器栈对比，而「鸿蒙 vs 小米 10」仍是设备 + 环境的合成差异，**不能当作内核对内核的结论**。
2. **每段尾部都被截断**：原始粘贴在下一个标签处断开（形如 `…47.25500005483627, 52. arkweb132`），被截断
   的那一条未收录，缺失清单见各文件的 `_meta.missingEntries`；`Preact` 套件有三列完全缺失（表中标
   「—（截断）」），反算总分时按同族数据补 32 ms，故那几列的分数另有 ±0.1~0.3 的不确定度。
3. **小米 10 的两次 WebView149 互为重复实验**：两轮 10 次均值逐套件相差 ≤4%（最大 Vue +3.9%），说明
   这个口径下同机同环境的重复性够用；反过来也说明表内 ≤4% 的列间差异不能当结论用。
4. **小米10 Edge149 一整列是「慢态」**：各套件约为同机系统 WebView 的 1.3–3.9 倍，其中
   `ES6-Webpack` 333.56 ms 是其余四列（77–160 ms）的 2–4 倍，`ES6-Webpack` 与 `WebComponents` 的
   Async 占比也飙到 69.8% / 65.6%。引用时应把这一列整体视为受限/热降频样本，或至少单独说明测量条件。

> 本节与 §1.5 口径相同（都是逐项毫秒时序、各 10 次），但**设备不同**，不要跨节取数比较；
> 两份都只适合在各自环境内纵向复测。

---

## 2. 本工程负载构成（实测）

同一份游戏内容、同一份构建配置（两版 `src/settings.json` **逐字节相同**），但**导出设置不同**：

| | 基础版（原仓库负载） | GP-Next 版（loader/分包 + 优化负载） |
|:---|:---|:---|
| 纹理 | `.png` **619 个 / 796.9 MB** | `.astc` **619 个 / 161.1 MB** |
| 音频 | `.mp3` **4185 个 / 330.7 MB** | `.ogg` **4185 个 / 153.8 MB** |
| 内容包 | — | `.zip` **1 个 / 110.4 MB** |
| 其它压缩纹理 | `.pvr` 1 个 / 32.0 MB、`.pkm` 1 个 / 8.0 MB、`.astc` 1 个 / 1.5 MB | 同左 |
| 数据 | `.json` 3549 个 / 78.0 MB | 同左 |
| 字体 | `.ttf` 5 个 / 22.3 MB | 同左 |
| 脚本 | `.js` 19 个 / 8.7 MB | `.js` 68 个 / 10.1 MB（含 GP-Next loader 与 Vite 分包） |
| WebAssembly | 2 个 / 0.8 MB（`bullet`、`spine`） | 同左 |
| **合计** | **1278.9 MB / 8394 个文件** | **576.5 MB / 8439 个文件** |

可复核的事实：

- 619 个纹理资产的 **UUID 主干一一对应**（无新增、无缺失）；4185 个音频主干同样一一对应
  → 是**同一内容的两种导出格式**，不是不同版本的游戏。
- 基础版有 23 个 PNG 单文件 > 8 MB（合计 289.4 MB，最大 19.17 MB）。
  PNG 在运行时需解码为 RGBA 再上传 GPU，是最大的内存与首帧开销来源。
- GP-Next 版的 110.4 MB `.zip`（`assets/resources/native/8a/8a356ba7-….zip`）内含 378 个条目
  = **183 个 `.mp3` + 183 个 `.meta`**（按场景分目录，如 `beach/`），属内容包；
  由游戏在 JS 侧读取/解压，其**读取时机与耗时待实测**。

结论：

- **GP-Next 版负载已做过纹理/音频压缩（ASTC + OGG），总体积约为基础版的 45%。**
- **基础版的负载是原版游戏的发布产物**，作为原仓库的负载**不应重新编码**
  （重新导出会与仓库中的负载不一致，也无法再逐字节比对版本差异）。

---

## 3. 壳层实测问题清单

三个仓库共用同一套壳层，以下问题在**三仓同时存在**（按符号名定位，避免行号漂移）：

| # | 位置 | 现象 | 影响 | 建议处置 |
|:--|:---|:---|:---|:---|
| 1 | `Index.ets` → `getMimeType()` | `default: return 'text/plain'`，未覆盖 `mp3 / ogg / ttf / bin / pvr / pkm / astc` | 330 MB 音频与压缩纹理以 `text/plain` 下发。Cocos 走 WebAudio `decodeAudioData`（arraybuffer）不看 MIME，故当前未暴露问题，但 `<audio>` 等路径存在风险，属定时炸弹 | 补齐扩展名映射；`default` 改为 `application/octet-stream` |
| 2 | `Index.ets` → `onInterceptRequest()` | 二进制响应同样调用 `setResponseEncoding('utf-8')` | 语义错误（对 PNG/MP3/WASM 等二进制设文本编码） | 仅对文本类响应设置编码 |
| 3 | `Index.ets` + `utils/ResourceManager.ets` | 拦截器只调用 `getCachedSync()`（纯读），**从未调用 `get()` / `preload()`**；唯一写入点位于 `ResourceManager` 私有加载流程内 → **缓存恒为空**，`getCacheStats()` 恒为 0 项 | 该 LRU 目前是纯装饰（含每请求一次 Map 查询与误导性的统计日志） | 二选一：**接入**（注意默认 80 MB 上限会被 2~3 个大纹理塞满，需先调上限/准入策略，否则会挤掉更多资源）或**移除** |
| 4 | `utils/PerformanceMonitor.ets` | 全工程从未实例化（原仓库文档也注明「未集成」） | 无影响，但属死代码 | 需要监控时再接入，否则一并清理 |
| 5 | `Index.ets` → `onInterceptRequest()` | 全部 8000+ 个资源请求都经 JS 侧拦截 + `$rawfile()` 逐次读取 | 启动期 I/O 路径长（每次请求一次 JS→原生往返） | **待实测**：接入 §4 的预取/预编译后再评估 |

---

## 4. 已在本地 SDK 确认存在、但当前未使用的加速 API

路径：`<sdk>/default/openharmony/ets/api/@ohos.web.webview.d.ts`

| API | 作用 | 使用要点 |
|:---|:---|:---|
| `WebviewController.prefetchResource(request, headers?, cacheKey?, cacheValidTime?)`（static） | 把资源提前灌入内核缓存 | 需实测：走 `https://cocos.local/` **自定义拦截**的资源是否也能被预取命中 |
| `WebviewController.prefetchPage(url, headers?, prefetchOptions?)` | 预取页面（不含 JS 执行/渲染） | 适合「启动页之后必然访问」的页面 |
| `WebviewController.prepareForPageLoad(url, preconnectable, numSockets)`（static） | 预解析 DNS / 预连接 | 本地 rawfile 场景收益有限，主要用于外部资源 |
| `WebviewController.setAutoPreconnect(enabled)`（static） | 自动预连接 | 同上 |
| `WebviewController.precompileJavaScript(url, script, cacheOptions)` | **注入 V8 字节码缓存** | 直接削减启动期 JS 解析/编译开销；对本工程的 `src/chunks/bundle.js`（数 MB）有意义，收益需实测 |
| `WebviewController.injectOfflineResources(resourceMaps)` | 注入离线资源映射 | 可替代部分拦截逻辑，减少 JS 侧往返 |

另外可考虑（未逐项核实可用性）：`setBackForwardCacheOptions()`、`getProgress()`（M132+）。
**注意**：以上均为「存在且可用」，不等于「一定有收益」；必须按 §5 的指标逐项实测后再保留。

---

## 5. 优化优先级与验收方法

优先级（收益/成本比排序）：

| 级别 | 事项 | 依据 |
|:---|:---|:---|
| **P0** | 修 `getMimeType()` 覆盖范围与二进制响应的 `setResponseEncoding` | 确定性缺陷，改动极小 |
| **P0** | `ResourceManager` 死缓存：接入或移除 | 消除误导性统计与无用开销 |
| **P1** | 启动路径实测：`prefetchResource` / `precompileJavaScript` / `prepareForPageLoad` | 直击「JS 编译 + I/O 往返」，收益待实测 |
| **P2** | GP-Next 版 110 MB 内容包的读取时机优化 | 若在启动期读取即是大开销，先测 |
| **P3** | 内核策略：保持系统默认；targetSdk ≥ 23 后再评估 `ARKWEB_EVERGREEN` | 当前已是最优默认 |
| — | **不做**：基础版负载重编码、pin M114 | 与原仓库定位冲突 / 反优化 |

验收指标（建议固定场景、固定温度区间，每项 ≥3 次取中位数）：

1. **冷启动耗时**：进程启动 → `onPageEnd` → 游戏首场景可交互；
2. **帧率**：单局固定场景的平均 FPS 与 **1% low**（掉帧比均值更能反映 ArkWeb 的真实短板）；
3. **内存**：ArkWeb 渲染进程峰值内存（大纹理场景最容易爆）；
4. **启动期资源量**：拦截器统计的请求数与总字节（用于判断预取是否真的减少了 JS 侧往返）；
5. **对照**：同机跑「系统浏览器 vs 本应用」，用于区分「内核能力」与「壳层开销」。

> 测速环境要求：同一 Speedometer / 同一次充电状态、同温区、关闭后台，禁用「受限」状态的机型做跨设备结论。

---

## 6. 参考来源

- OpenHarmony TPC：《M114 内核在 OpenHarmony 6.0 上的适配指导》（含 UA 示例与
  `setActiveWebEngineVersion` 用法）—
  <https://gitcode.com/openharmony-tpc/chromium_src/blob/132_trunk/web/ReleaseNote/CompatibleWithLegacyWebEngine.md>
- ArkWeb 内核版本对应表 — <https://seaxiang.com/blog/01fcdec4492f498f8fdd43dac8b6895d>
- ArkWeb 子系统 Changelog（M114 → M132）— <https://seaxiang.com/blog/Hxw3FW>
- V8 Maglev 官方博客（Chrome 117 桌面先行，移动端随后）— <https://v8.dev/blog/maglev>
- V8 提交：Android 上 Maglev 长期只在 `--future` 之后 —
  <https://chromium.googlesource.com/v8/v8/+/6d68e8596fdec658d55b5db1ed857e9abca6c249>
- 本地 SDK 声明：`<sdk>/default/openharmony/ets/api/@ohos.web.webview.d.ts`

---

## 7. 变更记录

| 日期 | 变更 |
|:---|:---|
| 2026-09-15 | 首版：内核版本更正、Speedometer 口径限定、三版负载实测对比、壳层问题清单、可用 API 与优先级 |
| 2026-09-18 | 新增 §1.5：ArkWeb 144（Chromium 144 / 鸿蒙 7，BRA-AL00）Speedometer 逐项时序基线（10 次重复 + CI），原始 metrics 归档到 `docs/perf/`；§1.3 补「与 §1.5 口径不同、不可换算」的说明 |
| 2026-09-18 | 新增 §1.6：四环境（`arkweb132` / `卓易通edge149` / `小米10 WebView149` / 无标签）Speedometer 3 逐项时序对照（各 10 次重复），原始 metrics 归档；标注设备归属待确认、`mi10-webview149` 的 ES6-Webpack 离群值、以及各段尾部被标签截断的情况 |
| 2026-09-18 | **修正 §1.6 五段的环境归属**：原判「标签标注其后那一段」有误，实为「标签紧跟其前一段数据的尾部」。重排后五列 = `arkweb132` / `卓易通edge149` / 小米10 系统 WebView149（两轮）/ 小米10 Edge149，文件按新标签重命名（旧名见 `_meta.renamedFrom`）；新增第 2 轮小米10 WebView149 数据（作者报告总分 **9.51 ± 0.14**，与第 1 轮逐套件相差 ≤4%）；补充「反算总分」代理口径与其校准误差；§1.3 依作者更正把 5.27 那一行改为小米 10 的 Edge，并据此改写其限定 2 与限定 4 |
