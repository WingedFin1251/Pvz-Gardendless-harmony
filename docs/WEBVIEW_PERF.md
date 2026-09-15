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
| 系统 WebView | 小米10 / Android | Chromium 149（满血） | 9.51 | 与下一行同配置，差 45% |
| ArkWeb | Mate60 / 鸿蒙6 | 应为 **M132**（原文写 ~120+，有误） | 6.84 | 鸿蒙当前水平 |
| 系统 WebView | 小米10 / Android | Chromium 149（受限） | 5.27 | 受温控/负载影响的中间态 |
| 系统 WebView | 小米10 / Android | Chromium 116 | 4.87 | Android 上 Maglev 当时仍在 `--future` 之后 |
| ArkWeb | 鸿蒙5 | 应为 **M114**（原文写 ~106，有误） | ~4.0 | |

使用这张表时必须带上四条限定：

1. **内核版本那两行是错的**，已按官方口径更正（见 1.1）。若鸿蒙6 实为 M132，则它与 Chromium 149
   的差距就不能归因于「内核老」，而更可能是 ArkWeb 自身的 V8 构建裁剪与系统调度/温控策略。
2. **噪声大于结论**：同为 Chromium 149 的两行差 45%，说明不控温、不重复测量的单次数据，
   第 4–6 名的排序不可用；只有「Mate60 11.57 vs ArkWeb 6.84」这种量级才稳健。
3. **卓易通不是同一条软件栈**：它是在鸿蒙上运行 Android 应用的兼容容器，Edge 多带一层转译/容器开销。
   它能拿 11.57 恰好证明**硬件不是瓶颈**，但不能当作鸿蒙原生浏览器的对照。
4. **缺同机对照**：要拆开「引擎差」与「设备差」，需在同一台 Mate60 上跑三组——卓易通 Edge、
   系统自带浏览器（ArkWeb 内核）、本应用 WebView。另外需确认各行使用同一 Speedometer 版本
   （5~12 分这个量级对应 Speedometer 3.x）。

### 1.4 为什么 Speedometer 不是本工程的验收指标

Speedometer 压的是 JS/DOM/现代框架的吞吐，而 Cocos 游戏几乎不使用 DOM 与现代前端框架。
真正映射到游戏体感的是三件事：**启动期的 JS 解析与编译、纹理解码与上传、GC 停顿**。
因此本工程的验收指标应为（见 §5），而不是 Speedometer 分数。

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
