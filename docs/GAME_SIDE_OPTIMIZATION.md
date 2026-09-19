# 游戏侧（负载侧）优化方案分析（2026-09-19）

> **配套**：[SHELL_PERF_2026-09-19.md](SHELL_PERF_2026-09-19.md)（壳层侧复测）与
> [WEBVIEW_PERF.md](WEBVIEW_PERF.md)。本文回答一个问题：**在"游戏侧"还能优化什么、怎么做、能拿回多少。**
>
> 证据等级沿用配套报告：🅐 **已归档原始数据**（`docs/perf/game-side-2026-09-19/`）／🅑 会话内测得。
> 设备：HUAWEI MatePad 11.5"S 灵动款（`DMG-W00`），OpenHarmony 6.1.1.120，
> ArkWeb 6.1.0.120 / Chromium 132，8 GB RAM；应用 `com.gardendless.gpnext` 0.14.0，
> 场景 `inGameScene`（含 Zomboss 与恐龙的重载关卡）。

---

## 0. 结论速览

| # | 结论 | 量级 | 证据 |
|:--|:---|---:|:---|
| 1 | **游戏 TypeScript 源码未公开** → 无法改源码重建 | — | 🅐 见 §1 |
| 2 | 但负载自带**行为钩子引擎**（patcher：`prototype`×150 / `wrap`×34 / `replace`×25 / `applyPatch`×4）+ 壳层可 document-start 注入 → **运行时改行为可行** | — | 🅐 见 §1 |
| 3 | **逐帧时间的 82–85% 是页内 JS 执行**；组件 `update` 仅占 11%，Cocos System ≈0 | — | 🅐 配套报告 §3.3 |
| 4 | **稳态长任务是主问题**：44 s 游戏内出现 **42 个 ≥50 ms 长任务、合计 7.75 s（占墙钟 17.6%）**，均值 185 ms、最长 993 ms | **17.6%** | 🅐 §2.3 |
| 5 | **`hp-overlay`（GP-Next 血条覆盖层）是最大的可识别第三方成本**：每 200 ms 一次、每次约 16 ms，占主线程 **81.4 ms/s（约 8% 墙钟）** | **8.1%** | 🅐 §2.1 |
| 6 | 它的成本**几乎不是 JS**：其中仅约 1.7 ms/次 是 JS 执行，其余是 **Label 文本重绘 + 纹理上传（原生侧）**；根因是它对 `Label.string` 无条件赋值 | — | 🅐 §2.2 · §3.1 |
| 7 | 降到 1/3 频率即把 81.4 → **26.4 ms/s**，主线程「非脚本」占比 16.6% → 10.9% | 省 5.5 点 | 🅐 §2.2 |
| 8 | **GC 不是"减少分配"能解决的**：实测总分配仅 **150–210 KB/s**，且 hp-overlay 不在分配榜（榜首是引擎内部的材质 uniform 块与 DragonBones 骨骼/槽时间线） | — | 🅐 §2.4 |
| 9 | 已安装的 mod 包有 7 个周期定时器；最大的两个（500 ms）合计 **11 ms/s**；那个 50 ms（20 Hz）的 reaper **每次只 0.04 ms，可忽略** | 1.1% | 🅐 §2.1 |
| 10 | **场景状态波动 2×**（相邻 20 s 窗口 38.10 / 20.25 / 19.90 fps）→ 任何 <10% 的端到端收益都**无法用 fps 验收**，必须改用「主线程占用 ms/s」 | — | 🅐 §2.2 |
| 11 | 主线程时间**几乎全在 rAF 帧内**（`_handleRAF` = 61.2% 采样窗口）；稳态下**没有**量级 >0.3% 的 rAF 之外 JS 入口 | 61.2% | 🅐 §2.5 |
| 12 | **一帧可以跑 0.4–2 秒**（最长的单帧 1960 ms，关卡加载发生在 rAF 内） | 1960 ms | 🅐 §2.5 |
| 13 | GC 实为 **3.8%（tracing）/ 4.8%（profile）**，且 **JS 解析已在后台线程**（`v8.parseOnBackground` 458 ms） | — | 🅐 §2.5（并更正配套报告 §3.3 的 8.8–10.2%） |

**一句话**：游戏侧能动的部分加起来约 **10% 的主线程占用**（其中 8 点是 hp-overlay），
而**真正的大头**（引擎内部约 40% + GC 约 9%）在闭源构建产物里，只能提给上游。

---

## 1. 可行边界：能改什么、不能改什么

| 层面 | 能否改 | 依据 |
|:---|:---|:---|
| 游戏 `.ts` 源码 | ❌ **不能** | 官网所谓"开源仓库" `Gzh0821/pvzge_web`（Apache-2.0，204★）根目录只有 `Dockerfile`/`LICENSE`/`README`/`docs`；README 让装 Git LFS 后 **serve `docs/`**，即仓库里是**构建好的 web 版 + 资源**，没有源码 |
| 构建产物的**可读性** | ✅ 意外地好 | 负载保留 `System.register("chunks:///_virtual/<原文件名>.ts")`：**654 个模块、原始文件名与类名全在**（`levelController.ts` 218 KB、`Zombie.ts` 90 KB、`LnC.ts` 61 KB、`ZombossMechZombie.ts` 40.6 KB…），只有局部变量被压缩 |
| 负载自带的**补丁引擎** | ✅ 有 | `assets/patcher-ChdOorMb.js`（848 KB）：`prototype`×150、`wrap`×34、`replace`×25、`hook`×23、`applyPatch`×4，并直接引用 `Plant`(364)/`Zombie`(26) —— 它就是为**运行时替换游戏行为**而生的；页面上还标注了 `patcher.capability.combat.behavior-hook` 这类能力名 |
| **壳层注入** | ✅ 有 | `touchPatch.js` / `GpNextShim.ets` 已在 document-start 注入，本报告的全部补丁都走这条路 |
| 手改压缩后的 bundle | ⚠️ 可行但脆弱 | `assets/main/index.js` 3.75 MB 单行压缩；改完每次游戏更新都要重做，且难以逐行复核 |
| Cocos 引擎内部 | ❌ 不能（除非重建负载） | 引擎逻辑在 `cocos-js/_virtual_cc-9deb4621.js`（3.32 MB）里 |
| 资源打包 / draw call 数 | ❌ 不能 | 需要 Cocos 工程与图集设置 |

---

## 2. 本轮实测数据

### 2.1 周期定时器成本排行榜

方法：在 document-start 钩 `window.setInterval`，用**注册调用栈**识别注册者（栈里含
`hp-overlay-…js` / `main.js` 等），给每个回调包一层 `performance.now()` 计时。窗口 20 s。

| 主线程占用 | 每次 | 次数 | 周期 | 归属 |
|---:|---:|---:|---:|:---|
| **81.4 ms/s** | **16.27 ms** | 100 | 200 ms | `hp-overlay-DQh_C7B9.js`（GP-Next 血条覆盖层） |
| 11.0 ms/s | 2.76 ms | 80 | 500 ms | `main.js`（mod 包，2 个定时器） |
| 0.7 ms/s | 0.04 ms | 353 | 50 ms | `main.js`（mod 包的 `startCardBadgeReaper`） |
| ≈0 | 0.15 ms | 4 | 5000 ms | `main.js`（`watchPlayerPropsResidue`） |

外加引擎自身的两个 50 ms 定时器（`_ensureDirectorDefined`，开销可忽略）。

> ⚠️ 这三个 `main.js` 定时器来自**已安装的 mod 包**（`gp-next://<uuid>/js/main.js`），
> 不是出厂负载的一部分。本报告的所有数字都**包含**这些 mod 的影响。

### 2.2 主线程构成，以及 hp-overlay 降频的效果

`Performance.getMetrics` 增量，三个连续 20 s 窗口（同一场景、同一关卡）：

| 窗口 | 引擎 fps | `ScriptDuration` | `TaskDuration` | **其中非脚本** | 新增长任务 | hp-overlay |
|:---|---:|---:|---:|---:|---:|---:|
| 基线（不限频） | 38.10 | 76.9% | 93.8% | **16.6%** | 16 个 / 1014 ms（5.1%） | 81.4 ms/s |
| hp 降频 ×3 | 20.25 | 80.5% | 91.7% | **10.9%** | 70 个 / 4783 ms | 26.4 ms/s |
| hp 降频 ×3 + mod 500 ms 降频 ×3 | 19.90 | 78.3% | 91.8% | **13.2%** | 61 个 / 4395 ms | 28.1 ms/s |

**能确认的因果部分**：hp-overlay 自身计时从 81.4 → 26.4 ms/s（−68%），
主线程「非脚本」占比从 16.6% → 10.9%（−5.7 点），**与 hp 的 −5.5 点几乎完全对上**——
这反过来证明 hp-overlay 的开销落在**非脚本桶**里（Label 重绘/纹理上传），而不是 JS。

**不能确认的部分**：fps 从 38.10 掉到 20.25，但同一关卡相邻窗口本就会在 20–38 fps 间跳动
（Δ 2 倍），长任务数也从 16 变成 70——**场景状态的变化远大于被测效果的 5%**。
所以本轮**无法**用 fps 验收这项优化，只能给出主线程占用（ms/s）这一因果量。

### 2.3 长任务的分布：稳态比启动更糟

`PerformanceObserver({type:'longtask'})`，按页面 uptime 分桶（累计 74.5 s）：

| 时段 | 长任务数 | 合计 | 最长 | 均值 |
|:---|---:|---:|---:|---:|
| 0–5 s（启动） | 7 | 970 ms | 260 ms | 139 ms |
| 5–15 s（进关/加载） | 9 | 3514 ms | **1900 ms** | 390 ms |
| 15–30 s | 4 | 1599 ms | 577 ms | 400 ms |
| **>30 s（稳态游戏内）** | **42** | **7751 ms** | 993 ms | 185 ms |

**稳态 42 个长任务 / 约 44 s = 17.6% 的墙钟时间花在 ≥50 ms 的阻塞任务上**——
这比"平均帧率低"更能解释手感上的卡顿（官方导出同口径的「抖动率 25.18%、单帧超 100 ms 占比 2.95%」）。
⚠️ 可惜 ArkWeb 下 `longtask` 的 `attribution.containerSrc` **为空**，拿不到脚本级归属（Chromium 桌面版能给）。

### 2.4 分配采样：不是"减少分配"能解决的问题

`HeapProfiler.startSampling`（16 KB 间隔）各 12 s：

| 配置 | 采样总分配 | 分配率 | 新增长任务 |
|:---|---:|---:|---:|
| hp 全速 | 2.45 MB | 209 KB/s | 43 |
| hp 降频 ×3 | 1.84 MB | 157 KB/s | 19 |

主要分配方（hp 全速窗口，占比为分配字节）：

| 占比 | 分配方 | 性质 |
|---:|---|---|
| 12.1% | `e._buildMaterialUniformBlocks` | 引擎：材质 uniform 块 |
| 11.1% | `r._updateBoneAndSlotTimelines` | 引擎：DragonBones 骨骼/槽时间线 |
| 10.9% | `e @ _virtual_cc:1` | 引擎内部 |
| 8.4% | `e @ _virtual_cc:2` | 引擎内部 |
| 7.0% | `i.initialize` | 引擎：DragonBones 构造 |
| 4.5% | `i.copy` | 引擎 |
| 3.2% | `e.fillPasses` / `e._doInit` | 引擎：渲染管线 |
| 2.4% | `hookZombieInstance @ 772e35e0-…` | **mod 包** |

结论：**JS 堆分配率只有 150–210 KB/s**，对一个每秒执行 780 ms JS 的应用来说非常低；
且 **hp-overlay 完全不在分配榜上**。所以：
- "给 hp-overlay 做对象缓存以降低 GC"这个想法 **不成立**；
- 配套报告里 GC 占墙钟 8.8–10.2% 的部分，**不太可能**由 JS 小对象垃圾驱动
  （更可能是引擎侧大对象/纹理与 V8 增量标记，采样器对它们覆盖不全）。

---

### 2.5 顶层入口实测：主线程时间到底分给了谁（并更正 GC 量级）

方法：CDP `Profiler` 采 12 s（保存完整调用树），按「`(root)` 的**直接子节点**」聚合 inclusive ——
这比 self time 更能回答"时间分给了哪些**顶层入口**"。

| 顶层入口 | inclusive | 占**采样窗口**（13.53 s） |
|:---|---:|---:|
| **`_handleRAF`**（每一帧：引擎 tick + 渲染） | 8288 ms | **61.2%** |
| `(program)`（无 JS 帧的 V8 内置/原生） | 2609 ms | 19.3% |
| `(idle)` | 1638 ms | 12.1% |
| `(garbage collector)` | 654.9 ms | **4.8%** |
| mod 包的 HUD 刷新（`…:13512` → `refreshHUD` / `updateHUD`） | 132.2 ms | 1.0% |
| `bundle.js:18`（`u`） | 41.1 ms | 0.3% |
| `touchPatch.js:72` / `:131`（我们的合成鼠标事件） | 21.7 / 21.2 ms | 各 0.2% |

**结论一：稳态下几乎没有「rAF 之外」的 JS 入口。** 除上表几项外，顶层再无量级 >0.3% 的异步入口。
这否掉了一条看起来很诱人的假设：tracing 里 `RunMicrotasks` 曾达 14.2 s / 45 s（≈31% 墙钟），
一度让人以为"异步资源加载的 promise 续体吃掉了一半主线程"。按顶层入口看，
**这些微任务嵌套在 rAF 帧内部**，不是独立的消耗源。

**结论二：GC 的量级要更正。** 本窗口 profile 里 GC 占 **4.8%**；tracing 实测主线程
`MinorGC`（240 次）+ `MajorGC`（8 次）合计 1709 ms / 45 s = **3.8%**。
配套报告 §3.3 里写的 8.8–10.2% 偏高，原因见下面的归一化说明（且该值本身随场景波动）。

> ⚠️ **归一化更正**：profile 的采样窗口比探针窗口长（探针 12.04 s，采样合计 13.53 s ——
> 因为 `Profiler.start` 早于探针求值、`stop` 晚于其结束）。因此配套报告 §3.3 里所有
> "占墙钟"的百分比都**偏大约 12%**，应按 13.53 s 归一。**排序与结论不变**，
> 归一化后的关键值：`_handleRAF` 61.2%、`(program)` 19.3%、`(idle)` 12.1%、GC 4.8%。

**顺带确认（tracing，45 s，含一次 reload）**

| 观察 | 数据 | 含义 |
|:---|:---|:---|
| 最长的顶层任务是**单帧** `FireAnimationFrame → FunctionCall _handleRAF` | **1960 / 885 / 694 / 617 / 613 / 607 / 604 / 604 / 518 / 455 / 400 / 385 ms** | 一帧可以跑 0.4–2 秒；与 `raf-baseline.json` 的 max 1674.8 ms 互相印证。帧内除 GC/微任务外没有其它事件 → 时间在**引擎 JS 内部**（关卡加载 / 场景构建） |
| `v8.parseOnBackground` / `BackgroundProcessor::RunScriptStreamingTask` | 458 / 461 ms | **JS 解析已在后台线程** → 用 `precompileJavaScript` 削"解析开销"的收益有限（§3.1 A4 的价值因此下调） |
| mod 包的 `TimerFire` | 1020 ms / 264 次，其中 `FunctionCall main.js:13513` 377 ms | 与 §2.1 排行榜的 11 ms/s 一致 |
| `XHRLoad` | 949 次 / 722 ms | 我们的资源拦截路径总量不大（1.6%） |
| `Layout` | 单帧内 18.8 ms | DOM 布局可忽略 |
| `V8.ExternalMemoryPressure` | 15.4 ms | 外部内存压力事件（纹理等） |

> tracing 的**时长**可信，但**线程归属不稳定**：三次运行只有第一次（在 reload 前启动 trace）
> 抓到了渲染主线程的 `FireAnimationFrame` / `FunctionCall` / GC 事件，另两次只抓到别的线程集
> （`complete=false`、事件数少一半）。因此本节只用 tracing 的**时长与 GC 计数**，
> 占比与线程归属一律以 CPU Profile 的**顶层入口**为准。

---

## 3. 方案清单

### 3.1 立即可做（不改负载、不需要源码）

| # | 方案 | 预期 | 代价/风险 | 状态 |
|:--|:---|---:|:---|:---|
| **A1** | **hp-overlay 定时器降频**（壳层在 document-start 钩 `setInterval`，按注册栈匹配 `hp-overlay-`，每 3 个周期执行一次） | 主线程 −5.5 点（8.1% → 2.7%） | 血条刷新从 5 Hz 降到 1.7 Hz（视觉无感）；识别依赖模块名，负载改名则自动失效（行为不变） | **已实现，默认关闭**：`touchPatch.js` 的 `HP_OVERLAY_INTERVAL_MULTIPLIER`（0=关，3=降频） |
| **A2** | **直接在 GP-Next 设置里关掉血条显示**（植物/僵尸/墓碑三项） | 主线程 **−8 点左右**（比 A1 更彻底） | 失去血条功能 | 零代码，用户自行决定 |
| **A3** | 精简已安装的 mod 包（3 个包、7 个定时器） | −1.1 点（两个 500 ms 定时器） | 失去对应 mod 功能 | 零代码 |
| **A4** | `WebviewController.precompileJavaScript` 注入字节码缓存 | 削**启动期**编译/求值（**解析已在后台线程**，见 §2.5，故收益低于原先估计） | 壳层 API，需实测命中率 | 待做（配套报告 §4 已列） |

### 3.2 需要上游（Gardendless 作者 / GP-Next 维护者）

| # | 方案 | 预期 | 说明 |
|:--|:---|---:|:---|
| **B1** | **hp-overlay 的 `Label.string` 赋值加守卫** | **约 8 点**（等于 A1 的全部收益，且不牺牲刷新率） | 现在每次都对 `primaryLabel.string` / `secondaryLabel.string` **无条件赋值**，触发 Cocos 重新栅格化文本 + 上传纹理。改成"值变了才赋值"（`active` 同理）即可。**这是本轮性价比最高的一条** |
| **B2** | 减少**同时活跃的骨骼动画数**（DragonBones） | 最多 ~16 点 | `advanceTime` 占墙钟 16%；可行手段是远处/屏外单位降频或改用帧动画，属设计层面 |
| **B3** | 降 **draw call 数**（实测 250–400/帧） | `updateAllDirtyRenderers` 占 23.7%，随 draw 数近似线性 | 需图集合并/合批优化，属资源与渲染管线层面 |
| **B4** | 引擎侧分配与 GC（材质 uniform 块、骨骼时间线） | GC 8.8–10.2% | 属 Cocos 引擎，可考虑升级引擎版本或提 issue 给 Cocos |

### 3.3 不可行 / 不建议

| 方案 | 否决理由 |
|:---|:---|
| 改 `.ts` 源码重建负载 | 源码未公开（§1） |
| 手改 3.75 MB 压缩 bundle | 每次游戏更新都要重做、无法复核；收益只有几个百分点 |
| 删 `spine`/`bullet` 的 wasm（约 2.3 MB） | 实测**从不执行**（profile 里 wasm 帧数 = 0），删了省不到一帧（配套报告 §3.3 ⑤） |
| 为 hp-overlay 做"分配优化/对象池" | 它根本不在分配榜上（§2.4） |
| 用 fps 验收这类优化 | 场景波动 2×，fps 无分辨力（§0-10） |

---

## 4. 建议的验收指标（重要）

本轮最大的方法学教训：**在这款游戏上，fps 不是可用的验收指标**。

- 同一关卡、同一配置、相邻 20 s 窗口：**38.10 / 20.25 / 19.90 fps**；
- 连"重载场景"本身的 draw call 也会在 249–451 间波动。

因此，游戏侧优化应当用**因果量**验收：

| 指标 | 来源 | 适用 |
|:---|:---|:---|
| **目标模块的主线程占用（ms/s）** | 注入钩子给该模块的回调计时（本报告 §2.1 的做法） | 单个模块的优化，**首选** |
| `TaskDuration` / `ScriptDuration` 增量占墙钟比 | `Performance.getMetrics` | 整体占用变化（本报告 §2.2） |
| 长任务数量与总时长（≥50 ms） | `PerformanceObserver({type:'longtask'})` | 抖动类优化 |
| `director.getTotalFrames()` 增量 | 引擎真实帧数 | 只有在效果 >10% 时才作为旁证 |

---

## 5. 复现方式

```bash
# 1) 构建时打开 Web 调试（Index.ets 的 ENABLE_WEB_DEBUG = true）并安装
# 2) 建立 DevTools 通道（实测：服务端注册在【应用主进程 pid】，且只经 127.0.0.1 可达）
hdc fport tcp:9421 localabstract:webview_devtools_remote_<应用主进程 pid>
curl.exe -s http://127.0.0.1:9421/json/version

# 3) 注入钩子（含长任务观察器、setInterval 注册者识别、逐回调计时）+ reload + 等到 inGameScene
node .tools/gp-gameprobe.mjs 127.0.0.1:9421 install 12

# 4) 周期定时器成本排行榜（20 s）
node .tools/gp-gameprobe.mjs 127.0.0.1:9421 timers 20 out.json

# 5) 应用限频（键为排行榜里的 label；'*hp*' 是 hp-overlay 的通配）
node .tools/gp-gameprobe.mjs 127.0.0.1:9421 timers 20 out-hp3.json '{"*hp*":3}'

# 6) 分配采样
node .tools/gp-gameprobe.mjs 127.0.0.1:9421 alloc 12 alloc.json

# 7) CPU Profile 的「顶层入口分布」（判断主线程时间分给了哪些入口）
node .tools/cdp-attrib.mjs 127.0.0.1:9421 12 attrib.json
node .tools/analyze-profile.mjs attrib.json        # 末尾会打印「顶层入口分布」

# 8) Chromium Tracing（按事件类型/GC 拆解；注意：时长可信，线程归属不稳定）
node .tools/cdp-trace.mjs 127.0.0.1:9421 45 trace.json reload
```

探针的关键实现（`.tools/gp-gameprobe.mjs`）：

1. 用 CDP `Page.addScriptToEvaluateOnNewDocument` 在 **document-start** 注入 —— 只有这样
   才能拦到 mod 包与 hp-overlay 注册定时器的那一瞬；
2. `window.setInterval` 包装里用 `new Error().stack` **按注册者识别**（栈里含 `hp-overlay-…js`、
   `gp-next://<uuid>/js/main.js` 等），再对回调计时 / 限频；
3. 识别不出归属时**行为完全不变**（直接走原始 `setInterval`），因此失效是安全的。

原始数据归档在 [`docs/perf/game-side-2026-09-19/`](perf/game-side-2026-09-19/)。

---

## 6. 局限

1. **测量包含已安装的 mod 包**（3 个包、7 个定时器），出厂长按时表现可能更好。
2. **单一设备、单一关卡**（含 Zomboss 与恐龙的重载关）；轻载场景各占比会不同。
3. **长任务已定位到"单帧"层面，但帧内那 1–2 秒的构成仍未拆开**：
   §2.5 证明最长任务就是一次 `_handleRAF`（关卡加载/场景构建），且帧内除 GC/微任务外没有其它
   trace 事件 —— 也就是说它的时间在**引擎 JS 内部**，要再细拆需要引擎源码。ArkWeb 的
   `longtask.attribution.containerSrc` 为空，也无法从 longtask 侧归因。
4. 分配采样对引擎侧大对象/纹理可能低估，故 §2.4 的"GC 不由 JS 小对象驱动"结论**限于 JS 堆**。
5. hp-overlay 的降频效果**只验证了主线程占用**，端到端 fps 无法验收（§4）。
6. 未验证 `precompileJavaScript` 的实际命中率与收益（A4 待做）；且 §2.5 显示 JS 解析已在后台线程，
   该手段的价值需要重新评估。
7. **tracing 的线程归属不稳定**（三次运行只有一次抓到渲染主线程），因此本报告对 tracing 只采用
   时长与 GC 计数；跨线程占比一律用 CPU Profile 的顶层入口。
8. profile 的"占墙钟"百分比需要按**采样窗口**（≈13.5 s）而非探针窗口（12 s）归一，
   否则偏大约 12%（§2.5 已说明；配套报告 §3.3 的 8.8–10.2% 即受此影响）。

---

## 7. 变更记录

| 日期 | 变更 |
|:---|:---|
| 2026-09-19 | 首版：可行边界（源码未公开 + patcher 行为钩子）、周期定时器成本排行榜、主线程构成、长任务分布、分配采样；方案清单（立即可做 / 需上游 / 不可行）与验收指标；`touchPatch.js` 加入默认关闭的 hp-overlay 降频开关 |
| 2026-09-19 | 新增 §2.5「顶层入口实测」：用 CPU Profile 的 `(root)` 直接子节点给出主线程分布（`_handleRAF` **61.2%** / `(program)` 19.3% / `(idle)` 12.1% / **GC 4.8%** / mod HUD 1.0%）；**否掉**"异步 promise 续体吃掉一半主线程"的假设（rAF 之外无量级 >0.3% 的入口）；用 tracing 确认**最长任务是单帧**（1960 ms 等，与 `raf-baseline.json` 的 1674.8 ms 互印）且**JS 解析已在后台线程**（下调 A4 的价值）；补充 profile 需按**采样窗口**归一的更正（§2.5 与配套报告 §3.3 的 8.8–10.2% 偏高） |
