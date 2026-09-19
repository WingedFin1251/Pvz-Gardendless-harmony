# 壳层性能真机复测报告（2026-09-19）

> **适用**：三仓库共用（基础版 / Lite / GP-Next）。本文只记录**可复核的事实**，
> 每条结论都标注证据等级：
>
> - 🅐 **已归档原始数据**：原始输出就在 [`docs/perf/shell-ab-2026-09-19/`](perf/shell-ab-2026-09-19/) 里，可逐项复核；
> - 🅑 **会话内测得**：脚本已记录在 §6，但当时的原始输出未归档，只能按 §6 复现。
>
> 与 [WEBVIEW_PERF.md](WEBVIEW_PERF.md) 的关系：那份是**长期维护**的性能现状与优化清单；
> 本文是**一次性复测报告**，提供它所需的真机依据。两者冲突时以本文的实测数据为准，并回头修正前者。

---

## 0. 结论速览

| # | 结论 | 证据等级 | 依据 |
|:--|:---|:---|:---|
| 1 | **瓶颈是每帧的页内计算（JS/引擎 + WebGL 提交），不是 GPU** | 🅐 | 官方导出：GPU 最高频占比 **0.00%**、平均频率 334.64/750 MHz；每帧页内 tick **32–35 ms**（预算 16.7 ms） |
| 2 | **降低渲染分辨率与关闭 MSAA 基本无效** | 🅐 | canvas 降到 2240×1472 → 1400×920（线性 62.5%、像素 39%）并关 antialias，每 draw 成本 0.0603 → 0.0606 ms（无变化） |
| 3 | **`lite` 与 `gpnext` 帧率无差异，但省约 620 MB 内存** | 🅐 | 同刻取样：整组 PSS 1552.8 MB vs 927.0 MB；每 draw 0.0894 vs 0.0895 ms |
| 4 | **本次壳层改动对帧率是"中性"的** | 🅐 | 改动前/后逐轮对比（全轮口径）0.1008 → 0.0894 ms/draw，但旧版在设备更热的后半段运行，差异无法与热漂移分离（§4.4 给出第 2–5 轮口径 0.1074 → 0.0989） |
| 5 | **~~帧率上限 60 更快~~ 已推翻：限帧 60 反而慢 13.8%** | 🅐 | 交替 A/B（每档 n=3，逐轮交替）：999 → 16.44/16.10/17.04 fps，60 → 12.77/14.82/15.14 fps，**三对全部 999 胜**；每帧 JS 45.6 → 51.1 ms。早先那个「+21%」是探针把限帧后的 rAF 空帧也计成帧造成的假象（§4.3） |
| 6 | **官方「App CPU 使用率」只统计应用主进程，漏掉渲染进程** | 🅐 | 同刻实测主进程 9.37%（官方均值 8.97% 与之相符），而渲染进程另有 14.84% |
| 7 | 设备已到**热/功耗墙**：196 s 内高温占比 100%、CPU 73.4 ℃ | 🅐 | 官方导出温度段 |
| 8 | WebGL 显存挂在**应用主进程**（`GL` 行），`:render` 子进程 GL 恒为 0 | 🅐 | hidumper 内存表 |
| 9 | 卡顿不只来自"慢"，还有 **50–1680 ms 的长任务**阻塞主线程 | 🅐 | `raf-baseline.json`：30 s 内 28 个长任务，最长 1680 ms；官方"单帧超 100 ms 占比 2.95%、抖动率 25.18%"与之吻合 |
| 10 | **逐帧时间的 82–85% 是页内 JS 在真的执行**，不是等 GPU | 🅐 | `Performance.getMetrics`：12 s 窗口内 `ScriptDuration` = 10.0–10.3 s；`TaskDuration` ≥ 墙钟（主线程饱和）；DOM 布局/样式 < 50 ms | 
| 11 | **组件 `update` 只占约 11%；Cocos System（含 Tween）≈ 0%** | 🅐 | 阶段钩子 `updatePhase` 5.32 ms/帧 与组件钩子合计 5.10 ms/帧 互相吻合；9 个 `director._systems[*].update` 全为 0 |
| 12 | 大头在**引擎内部**：渲染数据更新约 24%、DragonBones 骨骼推进约 16%、**GC 约 9–10%** | 🅐 | V8 CPU Profile self time + 调用祖链（§3.3） |
| 13 | `spine` / `bullet` 的 wasm（约 2.3 MB）**被加载但从不执行** | 🅐 | 资源列表有请求记录，但 4637 个 profile 节点里 **wasm 帧数 = 0** |
| 14 | 逐帧热点里的**可改项只有 GP-Next 层**：血条覆盖层 3.1%、桥写文本 1.3% | 🅐 | self time 按文件聚合：`hp-overlay-*.js` 5.1%、GP-Next 桥 0.9% |

**一句话**：这块平板（Kirin T91C / 8 GB）跑 GP-Next 负载时，每帧需要约 32–48 ms 而 60 fps 的预算是
16.7 ms；其中 **82–85% 是页内 JS 真的在跑**（组件 `update` 只占 11%，其余在引擎内部的渲染数据更新、
骨骼动画与 **GC**），GPU 从未触顶；壳层侧已无余量（§5），可下手的只剩 GP-Next 层那几处（§3.3 ④）。

---

## 1. 环境、构建与口径

### 1.1 设备与内核

| 项 | 值 |
|:---|:---|
| 设备 | HUAWEI MatePad 11.5"S 灵动款（`DMG-W00`） |
| SoC | Kirin T91C，9 核（簇1 核0–2 ≤1.4 GHz／簇2 核3–6 ≤2.18 GHz／簇3 核7–8 ≤2.189 GHz） |
| 内存 | 7,997,056 kB（7.63 GB）+ 6,291,456 kB（6 GB）swap |
| 系统 | OpenHarmony 6.1.1.120 |
| WebView 内核 | **ArkWeb 6.1.0.120 / Chromium 132** |
| 屏幕 | 物理 1840×2800；测试期间刷新率 **120 Hz**（官方导出 `屏幕刷新率=120`） |
| 页面 | CSS 视口 1120×736，`devicePixelRatio` 报告 2.5；引擎把 canvas 后备缓冲设为 **2240×1472**（= CSS 的 2.0 倍 = 物理像素的 80%） |
| 引擎 | Cocos Creator 3.8.4，WebGL2，renderer `Maleoon 910`，`antialias: true`，`stencil: true` |
| 应用版本 | 0.14.0（versionCode 1000007），包名 `com.gardendless.gpnext` / `com.gardendless.lite` |

### 1.2 四种测量手段

| 手段 | 覆盖内容 | 归档形式 |
|:---|:---|:---|
| **华为「性能分析」导出**（196 s，约 1 Hz） | fps / 卡顿 / 逐核 CPU / GPU / 内存分类 / 温度 / 功耗 | 官方汇总转录 + 逐秒内存序列 → [`official-fps-summary.md`](perf/shell-ab-2026-09-19/official-fps-summary.md)、[`official-memory-detail.tsv`](perf/shell-ab-2026-09-19/official-memory-detail.tsv)；源文件校验值见 [`SOURCE-PROVENANCE.md`](perf/shell-ab-2026-09-19/SOURCE-PROVENANCE.md) |
| **页内探针**（ArkWeb DevTools 协议注入） | 逐帧 `requestAnimationFrame` 间隔、长任务、draw call 数、heapUsed；`cc.director.getTotalFrames()` 真实引擎帧数 | [`degrade-*.json`](perf/shell-ab-2026-09-19/)、[`raf-*.json`](perf/shell-ab-2026-09-19/)、[`reload-ab-*.json`](perf/shell-ab-2026-09-19/)、[`rate-ab-engine.json`](perf/shell-ab-2026-09-19/rate-ab-engine.json) |
| **JS 归因**（CDP `Profiler` + `Performance.getMetrics` + 引擎阶段/组件钩子） | V8 采样调用树（self/inclusive）、JS 执行时间、任务时间、组件级逐帧耗时、引擎阶段拆分 | [`attrib-999-heavy.json`](perf/shell-ab-2026-09-19/attrib-999-heavy.json)、[`analyze-attrib.txt`](perf/shell-ab-2026-09-19/analyze-attrib.txt) |
| **`hidumper`**（设备侧） | 每进程 PSS 分类（GL/Graph/native heap/…）、每进程 CPU 占用 | [`hidumper-*.txt`](perf/shell-ab-2026-09-19/)、[`hidumper2-*.txt`](perf/shell-ab-2026-09-19/) |

### 1.3 口径陷阱（引用本文数字前必读）

1. **采样时刻敏感**：应用启动后第一分钟内内存在快速上涨。同一应用在同一台设备上，
   启动后 ~28 s 取样主进程 PSS = 849.6 MB，~35 s 取样 = 1202.4 MB（GL 530.5 → 876.2 MB）。
   **只有同次运行、同一取样时刻的数字才可互相比较**；跨运行比较必须固定时刻。
2. **热漂移**：连续多轮测量会让设备越跑越热（官方导出显示 196 s 内高温占比 100%）。
   任何"改动前 vs 改动后"的对比，只要两者不是严格交替执行，就无法把热漂移从结果里分离出去。
3. **场景状态不完全可比**：draw call 数随场景状态在 249–451 之间波动，
   所以"每帧耗时"必须除以同一次的 draw call 数折算成**每 draw 成本**才有可比性。
4. **官方「App CPU 使用率」只覆盖应用主进程**（§3.2 有交叉验证），
   渲染子进程的 CPU 不计入；引用该指标时必须说明这一点。
5. **GPU 使用率计数是 0/100 二值的粗计数**（`data.csv` 中 `gpuLoad` 中位数 = 0、p95 = 100），
   不要用它的均值当"GPU 负载 30%"来论证；判断 GPU 是否饱和请用**最高频占比**与**平均频率**。
6. **采集工具自身有开销**：官方导出里 `/bin/hidumper` + `hidumper_service` 合计 80.25 mA，
   占整机电流 8.5%——绝对功耗数字偏高，相对结论不受影响。
7. **单轮 fps 不能用于比较**：同一配置连续三次测得 **27.38 / 21.05 / 18.20 fps**（相差 1.5 倍）。
   原因是每墙钟秒要执行的 JS 量随场景状态变化，而 JS 才是约束（§3.3 ①）。
   任何「改前 vs 改后」「A 档 vs B 档」都必须**逐轮交替**（§4.3 的帧率 A/B 就是这么做的）；
   更稳的对照量是**每帧 JS 执行时间**（`ScriptDuration ÷ 帧数`），三次运行分别是 40.4 / 39.5 / 45.7 ms。
8. **不要用 `requestAnimationFrame` 回调间隔当"帧数"**：一旦引擎限帧，部分 rAF 回调会立即返回
   （空帧），于是"帧数"变多、fps 虚高——这正是 §4.3 那个「+21%」假象的来源。
   要引擎真实帧数，请读 `cc.director.getTotalFrames()` 的增量。

---

## 2. B：Lite 与 GP-Next 的对照

两个产物是**同一套壳层源码 + 同一份游戏内容的两种导出格式**（纹理 PNG ↔ ASTC、音频 MP3 ↔ OGG），
详见 [WEBVIEW_PERF.md §2](WEBVIEW_PERF.md)。本节只回答"它们的运行时差异是什么"。

### 2.1 内存（同刻取样，主进程 + 全部子进程）

取样条件：各自 `aa force-stop` 后冷启动，`aa start` 后 **28 s** 取样，同一台设备、同一时段。
原始输出：[`hidumper2-gpnext.txt`](perf/shell-ab-2026-09-19/hidumper2-gpnext.txt)、[`hidumper2-lite.txt`](perf/shell-ab-2026-09-19/hidumper2-lite.txt)。

| 进程 | `gpnext` | `lite` | 差值 |
|:---|---:|---:|---:|
| 主进程 PSS | **869,954 kB = 849.6 MB** | 388,346 kB = 379.2 MB | **+470.4 MB** |
| ├ 其中 `GL`（显存） | 543,220 kB = **530.5 MB** | 159,756 kB = 156.0 MB | **+374.5 MB** |
| ├ 其中 `Graph` | 81,904 kB = 80.0 MB | 81,904 kB = 80.0 MB | 0 |
| └ 其中 `native heap` | 41,766 kB = 40.8 MB | 38,243 kB = 37.3 MB | +3.5 MB |
| `:render` 子进程（忙） | **674,567 kB = 658.8 MB** | 515,588 kB = 503.5 MB | **+155.3 MB** |
| `:render` 子进程（闲） | 45,532 kB = 44.5 MB | 45,287 kB = 44.2 MB | +0.3 MB |
| **整组合计** | **1,590,053 kB = 1552.8 MB** | **949,221 kB = 927.0 MB** | **+625.8 MB** |

交叉验证（同设备、同方法、取样时刻 ~35 s、当时只采了主进程）：
主进程 PSS `gpnext` 1202.4 MB vs `lite` 603.1 MB，差 **+599.3 MB**，结论一致。
→ **`lite` 相比 `gpnext` 省下约 600–630 MB**，其中显存占大头（+375 MB），
渲染进程另占 +155 MB（其 PSS 以 Clean 页为主：613.3 MB vs 465.4 MB）。

> 官方 196 s 游戏内采集（`gpnext`）显示主进程显存会继续上涨：`GL` 903.3 MB（00:00）
> → 峰值 **1209.1 MB**（00:30–01:00）→ 1093.2 MB（结束），主进程平均/峰值 PSS 1419.90 / **1470.92 MB**。
> 即**游戏内 `gpnext` 的实际占用比上表的启动期取样更高**，上表只用于两产物横向对比。

### 2.2 CPU

| | 主进程 | `:render`（忙） | 整组合计（÷9 核） |
|:---|---:|---:|---:|
| `gpnext` | 9.37% | 14.84% | 24.21% ≈ **2.18 核** |
| `lite` | 7.98% | 12.13% | 20.11% ≈ **1.81 核** |

（28 s 时刻瞬时值；`:render`（闲）两者均为 0.00%。累计 CPU 时间：`gpnext` 主进程 24 s / 忙渲染 47 s；
`lite` 主进程 25 s / 忙渲染 38 s。）

> ⚠️ **不要把上表的 CPU 差异当成结论**：两个产物的 **JS 侧逐字节相同**——68 个 `.js` 文件合计
> 10,562,228 B，`assets/main/index.js`、`cocos-js/_virtual_cc`、`bundle.js`、`index.html`、
> `application.js`、`src/settings.json` 以及那个 115.8 MB 内容包 `.zip` 全部哈希一致，
> 差异**只在纹理/音频格式**（PNG/MP3 ↔ ASTC/OGG）。所以 24.21% vs 20.11% 只可能来自
> "两次单点采样落在不同的资源解码阶段"，样本量各 1，**不足以支撑任何结论**。

### 2.3 逐帧成本

折算方法：`每 draw 成本 = tickMean ÷ drawCalls`（页内探针，`inGameScene`）。
原始数据：[`degrade-lite-clean.json`](perf/shell-ab-2026-09-19/degrade-lite-clean.json) 等。

| 运行 | 轮数 | tick 均值 | draw 均值 | **每 draw** | stalls |
|:---|---:|---:|---:|---:|---:|
| `lite`（干净，另一个应用已杀） | 4 | 31.00 ms | 346.5 | **0.0895 ms** | 24 |
| `gpnext`（改动后构建） | 5 | 32.09 ms | 358.8 | **0.0894 ms** | 48 |
| `gpnext`（改动前构建） | 5 | 34.83 ms | 345.6 | 0.1008 ms | 92 |
| 同日更早的 7 轮基线 | 7 | 34.79 ms | 399.6 | 0.0871 ms | 134 |
| `lite`（**污染样本**：`gpnext` 同时在后台） | 5 | 38.49 ms | 364.4 | 0.1056 ms | 93 |

**`lite` 与 `gpnext` 的每 draw 成本是同一个值（0.0895 vs 0.0894 ms）**——
`lite` 省内存，但**不更快**。

> 污染样本单独保留（[`degrade-lite-contaminated.json`](perf/shell-ab-2026-09-19/degrade-lite-contaminated.json)）：
> 它比干净样本差 18%，说明**测量时必须先 `aa force-stop` 另一个应用**，否则后台应用会污染结论。

### 2.4 B 节结论

`lite` 与 `gpnext` 的帧率与每 draw 成本**没有可测差异**；差异全部在内存侧（约 600–630 MB）。
因此选型建议应基于内存而非性能，这正是 README 中"8 GB 及以下设备建议用 `lite`"的依据。

---

## 3. C：根因定位

### 3.1 GPU 不是瓶颈

官方 196 s 采集（[`official-fps-summary.md`](perf/shell-ab-2026-09-19/official-fps-summary.md)）：

| 指标 | 值 | 含义 |
|:---|:---|:---|
| GPU 频率范围 / 平均 | 279.00~750.00 MHz / **334.64 MHz**（44.6%） | 长期在低频 |
| GPU **最高频占比** | **0.00%** | 全程从未跑到最高频 |
| GPU 平均使用率 | 29.53%（但 `data.csv` 中位数 = 0，是 0/100 粗计数） | 仅作参考 |
| 平均 DDR 频率 | 2695.12 MHz（上限约 2746 MHz） | DDR 接近满频 |

GPU 从未触顶、且下面 §3.2 的"降分辨率无效"实验独立地支持同一结论：
**把像素量砍到 39% 并关闭 MSAA，每 draw 成本没有变化**。

### 3.2 每帧成本来自页内计算

证据 A（🅐 官方导出）：App CPU 8.97%（**主进程**，§1.3 陷阱 4）→
`0.0897 × 9 核 × 196 s = 158.2 核·秒`，除以 `25.8 fps × 196 s = 5056.8 帧`
→ **≈ 31.3 ms CPU / 帧**，而 16.7 ms 是 60 fps 的预算。

证据 B（🅐 页内探针）：`inGameScene` 下每帧 tick 均值 **32.09–35.29 ms**（同一次运行的 5 轮），
与证据 A 的 31.3 ms 同量级、互相印证。

证据 C（🅑 GL 消融）：把页面内**所有 GL 调用打桩**（`drawElements` / `bindVertexArray` / `bufferData` …
全部替换为空函数）后，每帧 tick 仍有 **28–29 ms**（对照 37–43 ms）。
即：**每帧约 28 ms 是与 GL 提交无关的页内计算**，GL 提交只占约 10 ms（≈25%）。

证据 D（🅐 分辨率/抗锯齿 A/B）：
[`reload-ab-control.json`](perf/shell-ab-2026-09-19/reload-ab-control.json)（canvas 2240×1472、antialias **true**、dpr 2.5）
vs [`reload-ab-injected.json`](perf/shell-ab-2026-09-19/reload-ab-injected.json)（canvas **1400×920**、antialias **false**、dpr 1.25）：

| | canvas | antialias | draw≈203/259 时的 tick | 每 draw |
|:---|:---|:---|---:|---:|
| 对照 | 2240×1472 | true | 12.25 ms @ 203 | **0.0603 ms** |
| 降级 | 1400×920 | false | 15.69 ms @ 259 | **0.0606 ms** |

像素量降到 39%、关掉 MSAA，**每 draw 成本不变** → 每帧成本与**填充/光栅化无关**，
是**每个 draw call 的固定开销**（JS 侧场景遍历 + 引擎提交逻辑 + 内核侧调用成本）。

> 独立旁证（🅐 官方内存明细）：`Graph` 全程恒为 80 MB，`GL` 随场景增长 903 → 1209 MB，
> 说明显存压力来自**纹理常驻**，而非逐帧的 render target 抖动。

### 3.3 逐帧 JS 的归因（谁在吃这些毫秒）

方法：在 `inGameScene`（含 Zomboss 与恐龙的重载场景）注入探针，三件仪器同时跑：

1. **引擎阶段钩子**：`director.tick`、`root.frameMove`、`_compScheduler.startPhase|updatePhase|lateUpdatePhase`、
   `director.emit`，以及 `director._systems[*].update`（Cocos 的 System 列表，Tween 等在这里，**不在组件遍历里**）；
2. **组件级钩子**：对「定义 `update`/`lateUpdate` 的那一层原型」各包装一次，按 `cc.js.getClassName`
   归属真实类名（否则拿到的是压缩后的 `o`/`t`/`n`）；
3. **CDP**：`Profiler`（200 µs 采样，保存完整调用树）+ `Performance.getMetrics`（JS 执行/任务时间）。

窗口 12 s。原始数据：[`attrib-999-heavy.json`](perf/shell-ab-2026-09-19/attrib-999-heavy.json)（裁剪掉 2.4 MB 原始调用树）、
完整分析文本 [`analyze-attrib.txt`](perf/shell-ab-2026-09-19/analyze-attrib.txt)。

> 方法学提醒：探针自己的包装函数在 profile 里显示为 `target.<computed> @ (inline):40`
> （CDP `Runtime.evaluate` 注入的代码没有 URL）。因此**本文只采用 self time 与调用祖链**，
> 不采用经过这些包装帧的 inclusive 数。

#### ① JS 线程是硬约束，不是等 GPU

| 指标 | 三次运行 |
|:---|---:|
| 墙钟窗口 | 12.06 / 12.19 / 12.15 s |
| `ScriptDuration`（JS 执行） | 10272 / 10078 / 10005 ms |
| **占墙钟** | **85.2% / 82.7% / 82.4%** |
| `TaskDuration`（主线程任务） | 12800 / 12697 / 13164 ms（≥ 墙钟 → 主线程饱和） |
| `LayoutDuration` / `RecalcStyleDuration` | 26–38 / 7–10 ms（DOM 可忽略） |
| 每帧 JS 执行 | 40.4 / 39.5 / 45.7 ms |

这独立地证实了 §3.2 证据 C 的结论：**每帧那几十毫秒是 CPU 上真的在执行 JS，而不是在等 GPU**。
注意三次运行的 fps 是 27.38 / 21.05 / 18.20，而每帧 JS 却稳定在 39–46 ms ——
**fps 是"场景要求多少 JS 工作"的结果**（见 §1.3 陷阱 7）。

#### ② 阶段拆分：组件更新很少，大头在引擎内部

| 阶段 | ms/帧 | 占墙钟 |
|:---|---:|---:|
| `director.tick`（整帧） | 33.99 | 71.5% |
| ├ `root.frameMove` | 6.96 | 14.6% |
| ├ `compScheduler.updatePhase`（全部组件 `update`） | 5.32 | 11.2% |
| ├ `compScheduler.startPhase` | 0.01 | 0% |
| ├ `compScheduler.lateUpdatePhase` | 0.11 | 0.2% |
| └ `director.emit`（13 次/帧） | 0.94 | 2.0% |
| `director._systems[*].update`（9 个 System，含 Tween） | ≈0 | 0% |

组件级钩子独立复核：top-40 组件合计 **5.095 ms/帧**，与 `updatePhase` 的 5.322 ms/帧吻合
（场景内 100 个组件类；尾部条目已降到 0.002 ms/帧，截断不影响合计）。
耗时最高的几个单件是 `DinoZombossMechZombie` 0.99、`CardSelectAlmanac` 0.58、`RaptorDinosaur` 0.56、
`DinoBasicZombie` 0.55、`ParticleSelfdestroy` 0.40 ms/帧。

→ **「优化组件的 `update()`」上限只有这 11%。** `tick` 33.99 ms 减去已钩住的 13.3 ms，
还有约 **20.7 ms/帧在引擎内部**，不属于任何组件或 System。

#### ③ 引擎内部热点（self time + 调用祖链）

| self 占比 | 函数 | 调用路径 | 性质 |
|---:|---|---|---|
| 13–15% | `(program)` | 根 | V8 内部/无 JS 帧的代码 |
| **8.8–10.2%** | `(garbage collector)` | 根 | **GC** |
| 4.8–5.6% | `r.advanceTime` | `tick → 组件 update → ArmatureDisplay.update` | **DragonBones 骨骼推进** |
| 4.8–4.9% | `mut` | `updateAllDirtyRenderers → updateRenderer → updateRenderData` | 渲染数据/矩阵 |
| 3.1% | `F @ hp-overlay-*.js` | `Z → F` | **GP-Next 血条覆盖层**（独立于 tick 的根分支） |
| 2.4–2.8% | `i.update` | 组件 update | 引擎内组件 |
| 2.3–2.6% | `e.walk` | 场景/节点遍历 | 遍历 |
| 2.2–2.3% | `e.multiply` | `updateRenderData` | 矩阵乘法 |
| 2.2% | `texSubImage2D` | `updateRenderData` | **逐帧纹理上传** |
| 1.5% | `_buildMaterialUniformBlocks` | `updateRenderData` | **逐帧重建材质 uniform 块** |
| 1.5% | `t.getPassHash` | 渲染管线 | **逐帧算 pass hash** |
| 1.3% | `tauriWriteText` → `invoke` | GP-Next 桥 | **逐帧走文件写入路径** |
| 0.7% + 0.7% | `_findChildComponents` / `_findComponents` | 组件 update | **逐帧查找组件** |
| 0.7% | `e.tryCompile` | 着色器 | 着色器编译尝试 |

按文件聚合（self）：引擎 `_virtual_cc` **57.6%**、`(inline)` 37.4%、游戏包 `index.js` **5.8%**、
`hp-overlay-*.js` **5.1%**、GP-Next 桥 `5228928c-…` 0.9%、`patcher-*.js` 0.4%、`touchPatch.js` 0.1%。

`updateAllDirtyRenderers` 这一支的 inclusive 为 **23.7%**、DragonBones `advanceTime` 为 **16%**。

#### ④ 由此得到的可动项（按"能不能改"分三类）

| 类别 | 项 | 量级 | 谁能改 |
|:---|:---|---:|:---|
| ✅ **GP-Next 层** | `hp-overlay` 血条覆盖层逐帧刷新 | 3.1%（≈1.5 ms/帧） | GP-Next 侧 |
| ✅ **GP-Next 层** | 桥的文本写入路径被逐帧触达 | 1.3% | GP-Next 侧 |
| ⚠️ 游戏代码 | 逐帧 `_findComponents` / `_findChildComponents`（应缓存引用） | 1.4% | 游戏源码 |
| ⚠️ 游戏代码 | GC 压力（每帧分配堆对象） | **8.8–10.2%** | 游戏/引擎源码 |
| ❌ 引擎内部 | 逐帧 `texSubImage2D`、`_buildMaterialUniformBlocks`、`getPassHash`、矩阵运算 | 合计 >10% | 需改引擎源码 |
| ❌ 引擎内部 | DragonBones 骨骼推进 | 约 16% | 需改引擎源码 |
| — **不必动** | `spine` / `bullet` 的 wasm（约 2.3 MB） | **0%** | 被加载但从不执行，见下 |

#### ⑤ 明确的负面结论（省得再花时间）

- **`spine.wasm`（352 KB）与 `bullet.release.wasm`（469 KB）被加载但从不执行**：
  资源列表能看到请求（`spine.wasm-a121967b.js`、`bullet.release.wasm-10f8cbd4.wasm` 等），
  但 4637 个 profile 节点里 **wasm 帧数 = 0**。它们只有启动期成本，**没有逐帧成本**。
- 游戏代码里 `PhysicsSystem`/`RigidBody`/`Collider` 引用数为 **0**，`Skeleton` 也为 **0**，
  骨骼动画走的是 **DragonBones（112 处引用）**——与 wasm 的执行情况一致。
- **Cocos 的 System（Tween 等）不是成本**：9 个 `_systems[*].update` 合计约 0 ms。
- **DOM 不是成本**：layout + style 合计 < 50 ms / 12 s。
- 剩下的大头（引擎内部 + GC）**不改引擎/游戏源码就动不了**，而本仓库没有这两者的源码。

### 3.4 抖动来源：长任务阻塞，而非"均匀地慢"

[`raf-baseline.json`](perf/shell-ab-2026-09-19/raf-baseline.json)（30 s，1408 帧）：

| 指标 | 值 |
|:---|---:|
| rafFps / 平均帧间隔 | 45.08 fps / 22.18 ms |
| p50 / p95 / p99 | 16.7 / 41.7 / **183.3 ms** |
| 最大帧间隔 | **1674.8 ms** |
| 帧间隔标准差 | 56.18 ms |
| 超 33 ms / 超 50 ms 的帧 | 92 / 40 |
| 30 s 内的**长任务**（>50 ms） | **28 个**：53, 280, 174, 102, 163, 340, 240, 177, 229, 180, 165, 50, 142, 167, 56, 157, 238, 281, 292, 536, 174, 56, 50, 419, 289, 330, 52, **1680** ms |

即：一半以上的帧接近 16.7 ms（p50 = 16.7 ms，说明**引擎本身能达标**），
但被周期性的长任务反复打断。这与官方导出的
**抖动率 25.18%、单帧耗时标准差 29.2 ms、单帧超 100 ms 占比 2.95%** 完全一致。
**所以"提升平均帧率"和"消除卡顿"是两个不同的问题**：前者受 §3.2 的计算成本限制，
后者受长任务（最可能是资源加载/解码、GC、或同步 I/O）限制。

### 3.5 综合根因

```
每帧 34~48 ms（60 fps 预算 16.7 ms）   ← §3.3 实测：其中 82~85% 是 JS 真的在执行
├─ 引擎内部约 20.7 ms/帧（不属于任何组件或 System）
│   ├─ 渲染数据更新 updateAllDirtyRenderers（inclusive 23.7%）
│   │    └─ 矩阵运算 mut/multiply、逐帧 texSubImage2D、逐帧重建材质 uniform、逐帧 pass hash
│   ├─ DragonBones 骨骼推进 advanceTime（inclusive 16%）
│   ├─ V8 (program) 13~15% 与 GC 8.8~10.2%
│   └─ 场景/节点遍历 e.walk 2.3~2.6%
├─ 组件 update 5.3 ms/帧（11.2%）  ← 唯一属于"游戏逻辑"的部分
├─ frameMove 6.96 ms/帧（14.6%）
└─ GPU 侧：未饱和（最高频占比 0%，§3.1）      ← 不是原因
```

**结论**：瓶颈是**页内 JS 执行**（不是 GPU、不是分辨率、不是内存带宽），
而其中能由本仓库/GP-Next 侧改动的部分不到 5%（§3.3 ④）。

### 3.6 被本次实测**排除**的假设

| 假设 | 实测结果 | 结论 |
|:---|:---|:---|
| "GPU 性能不足" | 最高频占比 0.00%、平均频率 44.6% | 排除 |
| "分辨率/抗锯齿太贵" | 像素降 61%、关 MSAA 后每 draw 不变 | 排除 |
| "渲染进程模式选错" | 移动端 SINGLE 为官方默认；改 MULTIPLE 反而增加内存 | 排除（见 §5） |
| "`lite` 负载更小所以更快" | 每 draw 成本与 `gpnext` 相同 | 排除 |
| "限帧能提升帧率" | 交替 A/B：999（不限帧）16.53 fps vs 60 上限 14.24 fps，**限帧反而慢 13.8%** | 排除（见 §4.3） |
| "物理/Spine 引擎模块在拖后腿" | 游戏代码对 `PhysicsSystem`/`Skeleton` 引用数为 0，且 profile 里 wasm 帧数为 0 | 排除（见 §3.3 ⑤） |
| "Tween 等 System 是开销" | 9 个 `_systems[*].update` 合计 ≈ 0 ms | 排除 |
| "GC 是主要成本" | GC 占墙钟 8.8–10.2%，是**单项最大可识别成本之一**，但不是主因 | 部分成立 |

---

## 4. D：已实施的壳层改动与验证

### 4.1 改动清单

| # | 位置 | 改动 | 对应结论 |
|:--|:---|:---|:---|
| 1 | `resources/rawfile/touchPatch.js` | 三个 document 级 touch 监听补 `{ capture: true, passive: false }` | 修复 `preventDefault()` 被忽略 + 每次触摸一条 Error（143 条/分钟 → 0） |
| 2 | `pages/Index.ets` | `onConsole` 只转发 Warn/Error，并 `return true` 抑制默认 hilog | 去掉逐帧 info 级日志对主线程的负担 |
| 3 | `entryability/EntryAbility.ets` | `setWindowKeepScreenOn(true)` | 挂机常亮；并降低熄屏转后台被系统回收的概率 |
| 4 | `entryability/EntryAbility.ets` | `setRenderProcessMode` 按设备分流（移动 SINGLE / 2in1 MULTIPLE）+ hilog 输出实际模式 | 依官方《ArkWeb 进程》移动端默认策略，避免在移动端白白多用内存 |
| 5 | `resources/rawfile/touchPatch.js` | 新增可调查性能档位 `FRAME_RATE_CAP`（默认 **0 = 不干预**）/ `RENDER_SCALE` / `DISABLE_MSAA` | 三档实测后均无正向收益，故默认全关；见 §4.3 |

### 4.2 逐项验证

| 改动 | 验证方式 | 结果 |
|:---|:---|:---|
| 1 | 注入 12 次触摸后统计被动监听相关 Error | 🅑 0 条（改前 143 条/分钟） |
| 2 | `onConsole` 计数 | 🅑 web-console 只剩 warn/error |
| 3 | 设备端观察 | 🅑 屏幕不再自动熄灭 |
| 4 | `hilog` 输出 | 🅑 `渲染进程模式: SINGLE(移动设备)` |
| 5 | 页内探针 3 档对照 → **已作废** | ❌ 早先的 29.46/35.65/32.28 fps 是探针统计 rAF 空帧造成的假象；改用**交替 A/B + `director.getTotalFrames()`** 后结论相反，见 §4.3 |

### 4.3 引擎帧率上限：**结论已推翻，默认改为不干预**

#### 早先的结论错在哪

早先版本曾把 `cc.game.frameRate` 从 payload 默认的 999 限到 60，依据是一次 30 s 顺序采样
（[`raf-framerate-ab.json`](perf/shell-ab-2026-09-19/raf-framerate-ab.json)：29.46 → 35.65 fps）声称「+21%」。
本次复测推翻它，并查明了**探针本身的方法学缺陷**：

1. **探针把空帧计成了帧**。早先的探针用 `requestAnimationFrame` **回调间隔**当"帧"。
   引擎一旦限帧，部分 rAF 回调会立即返回（不渲染），于是 rAF 回调变多变快、fps 虚高。
   本次改为直接读引擎真实帧计数 `cc.director.getTotalFrames()` 的增量，
   与 rAF 计数**逐轮完全一致**（说明改用后的方法没有空帧问题）。
2. **单轮 fps 复现性差**。同一配置（都是 999）连续三次为 **27.38 / 21.05 / 18.20 fps**（1.5 倍），
   任何"先测 A 再测 B"的顺序比较都不成立（§1.3 陷阱 7）。
3. 而且机制上也不该期待收益：**场景本来就跑不到 60 fps，设 60 上限不可能提升帧率**，
   只可能为本就达不到的目标增加节拍管理开销。

#### 交替 A/B 结果（重载场景，逐轮交替，每档 n=3）

原始数据：[`rate-ab-engine.json`](perf/shell-ab-2026-09-19/rate-ab-engine.json)。

| `cc.game.frameRate` | 三轮实测（引擎 fps） | 均值 | 每帧 JS |
|:---|:---|---:|---:|
| **999（不限帧）** | 16.44 / 16.10 / 17.04 | **16.53** | 45.6 ms |
| 60（上限） | 12.77 / 14.82 / 15.14 | **14.24** | 51.1 ms |

**三对全部是 999 胜**，均值高 **13.8%**，而限帧后每帧 JS 反而多 12%（45.6 → 51.1 ms）。

#### 处置

- `FRAME_RATE_CAP` 默认 **改为 0（不干预）**，并在注释里写明"实测在重载场景更慢"；
- 开关保留（供按机型实验），但实现改为**启动后 30 秒内持续纠正**——因为实测发现
  **payload 在引擎就绪后会把 `frameRate` 设回 999**，一次性赋值立即失效
  （发布版运行时读到的就是 999，这也说明早先"已作为默认值生效"的说法是错的）；
- 验证：发布版重装后启动，`hilog` 中 `[perf]` 输出 0 条、无错误（符合 `FRAME_RATE_CAP = 0` 的预期）。

### 4.4 对帧率的影响：中性

改动前构建 [`degrade-old-build.json`](perf/shell-ab-2026-09-19/degrade-old-build.json)
vs 改动后 [`degrade-new-build.json`](perf/shell-ab-2026-09-19/degrade-new-build.json)：
第 2–5 轮每 draw 0.1074 → 0.0989 ms、stalls 92 → 45，看似改善 8%；
但**改动后的构建先跑、改动前的构建后跑**，后者在设备更热的状态下测量，
这个偏差方向对旧版本不利，**无法与热漂移分离**。
因此本报告按"**中性**"表述：这些改动的价值在**正确性、日志质量与后台存活**，不在帧率。

---

## 5. 未采纳的方案与否决理由

| 方案 | 否决理由 |
|:---|:---|
| `setRenderProcessMode(MULTIPLE)` 强制多渲染进程 | 官方语义是"多个 Web 组件共享渲染进程"的策略；本应用只有 1 个 Web 组件。移动端默认 SINGLE（省内存），改 MULTIPLE 只会增加内存，无帧率收益 |
| 改 `RenderMode.SYNC_RENDER` → `ASYNC_RENDER` | 已是全屏 Web 的推荐模式且当前行为正常；本工程瓶颈不在渲染模式 |
| Graphics Accelerate Kit 的 OpenGTX / 帧生成 | 要求应用侧自绘 GLES/Vulkan 并接管渲染管线；本工程的绘制全在 ArkWeb 内部，无法接入 |
| 游戏服务 Kit `gameperformance` 调温控/频率档 | 只是**读取**温度/频率档位并提示，不改变调度；且本机高温占比已 100%，读到了也无处可施 |
| `displaySync` 自绘时机对齐 | 需要 `uiContext` 与自绘内容；本工程没有 UI 自绘路径 |
| 壳层继续做"性能优化" | 壳层已无余量：§3 证明瓶颈是页内逐帧 JS，壳层能动的只有日志与生命周期（已做完） |
| **引擎帧率上限 60** | 交替 A/B 实测**更慢 13.8%**，见 §4.3；已改回默认不干预 |
| **删掉 spine/ammo 引擎模块（约 2.3 MB）** | 实测这两个 wasm **从不执行**（profile 中 wasm 帧数 = 0），删掉只省启动期，**省不到一帧**；且要改第三方导出产物 |
| 重新编码基础版游戏负载 | 与"保留原版发布产物、可逐字节比对"的仓库定位冲突（见 WEBVIEW_PERF.md §2 结论） |

**剩余优化方向与"能不能做"**：逐帧成本的 82–85% 是页内 JS，其中约 20.7 ms/帧在引擎内部
（渲染数据更新、DragonBones、GC），**不改引擎/游戏源码动不了**；真正能改的只有
GP-Next 层（血条覆盖层 3.1% + 桥写文本 1.3%）——详见 §3.3 ④。

---

## 6. 复现方式

### 6.1 页内探针（需要 DevTools 通道）

```bash
# 1) 构建时打开 Web 调试（Index.ets 中 ENABLE_WEB_DEBUG = true），安装并启动
# 2) 列出进程（注意：本应用会有两个 :render 子进程，累计 CPU 时间大的那个才在干活）
hdc shell "ps -ef | grep com.gardendless.gpnext"
# 3) 建立 DevTools 通道。实测（ArkWeb 6.1.0.120 / MatePad DMG-W00）：
#    服务端注册在【应用主进程 pid】上，且只经【127.0.0.1】可访问
#    （localabstract 用主进程 pid；用渲染 pid 会连上但没有页面 target）
hdc fport tcp:9367 localabstract:webview_devtools_remote_<应用主进程 pid>
curl.exe -s http://127.0.0.1:9367/json/version     # 有响应即通
# 4) 关掉调试后同样命令应无响应（发布版验证点）：
#    hdc install -r 发布版 → 启动 → curl 无响应
```

探针的核心逻辑（`Runtime.evaluate`，`awaitPromise: true`）：

```js
// 采样 20~30 s 的逐帧间隔，并同时记录 cc 引擎状态与 draw call 数
const frames = []; let last = performance.now();
const t0 = last;
await new Promise((res) => {
  const loop = () => { const n = performance.now(); frames.push(n - last); last = n;
    (n - t0 < 20000) ? requestAnimationFrame(loop) : res(); };
  requestAnimationFrame(loop);
});
frames.sort((a, b) => a - b);
const mean = frames.reduce((a, b) => a + b, 0) / frames.length;
({ tickFps: 1000 / mean, tickMean: mean, tickP50: frames[frames.length >> 1],
   tickP95: frames[Math.floor(frames.length * 0.95)],
   drawCalls: cc?.director?.getScene()?.getDrawCalls?.() ?? null,
   scene: cc?.director?.getScene()?.name, heapUsedMB: performance.memory?.usedJSHeapSize / 1048576 });
```

### 6.2 逐进程内存与 CPU（`hidumper`）

```bash
hdc shell "aa force-stop com.gardendless.gpnext"      # 必须先杀另一个应用，否则样本被污染
hdc shell "aa start -b com.gardendless.gpnext -a EntryAbility"
# 固定等待 28 s（或 35 s），然后对全部进程逐个取样：
hdc shell "ps -ef | grep com.gardendless.gpnext"       # 取主进程 + 两个 :render 的 pid
hdc shell "hidumper --mem <pid>"                        # 关注 GL / Graph / native heap / Total
hdc shell "hidumper --cpuusage <pid>"                   # 关注 xx.xx%（整机 9 核口径）
hdc shell "cat /proc/meminfo"                           # MemFree / MemAvailable / SwapFree
```

### 6.3 官方性能分析导出

1. DevEco Studio → **性能分析**（或设备上的「性能测试」）→ 选择 `com.gardendless.gpnext` → 录制 ≥180 s；
2. 导出目录含 `*.xlsx`（`数据` + `内存明细` 两个 sheet）、`data.csv`、`PowerSensor.csv`、`PowerApplication.csv`、`dubai.db`；
3. 解析方式见本文归档的 `official-*.md` / `*.tsv`，源文件校验值见 [`SOURCE-PROVENANCE.md`](perf/shell-ab-2026-09-19/SOURCE-PROVENANCE.md)。

> ⚠️ 官方导出目录体积可达数百 MB，且 `dubai.db` 含整机遥测（其它应用包名等），
> 已在 `.gitignore` 中以 `/testing data/` 排除，**不要入库**。

---

## 7. 局限与未决

1. ~~每帧 32 ms 的构成还不能分解~~ → **已解决（§3.3）**：`ScriptDuration` 占墙钟 **82–85%**，
   说明这些时间是**真的在执行 JS**，不是等 GPU。剩下无法归到组件/System 的约 20.7 ms/帧在引擎内部
   （渲染数据更新、DragonBones、材质/纹理、GC）。**要再往下拆需要引擎源码，本仓库没有。**
2. **`:render` 有两个进程**（一个累计 CPU 0 s 的"闲孪生"）这一现象未查明来源，
   本报告只如实记录；`setRenderProcessMode` 的取值是否影响它，尚未验证。
3. **降分辨率 A/B 的场景不同**（对照 292 draw vs 降级 371 draw），
   只能比较"低 draw 数区间"的两点（203 vs 259），n 偏小。
4. **热漂移**未做交替执行（A/B/A/B）设计，§4.4 的"中性"结论是保守表述。
   §4.3 的帧率 A/B 已经改为交替设计。
5. `dump-sheet2` 抽样的官方内存序列为**每 10 s 一点**，峰值时刻可能有遗漏（官方给出峰值 PSS 1470.92 MB 可作上界）。
6. **JS 归因只在"重载场景"（Zomboss + 恐龙，14–20 fps）做过**。轻载场景（菜单）里各部分的占比
   会不同——尤其 GC 与引擎内部开销的占比可能明显下降。若要在轻载场景下优化，需要重跑 §3.3 的仪器。
7. **归因探针会给场景加钩子开销**（每个组件的 `update`/`lateUpdate` 各包一层 `performance.now()`），
   约为每帧零点几毫秒量级；各阶段/组件的**相对占比**可信，绝对值略偏高。
8. §3.3 的组件名来自 `cc.js.getClassName`，但引擎内部函数名仍是压缩后的（如 `mut`、`zl`、`Sct`），
   只能靠调用祖链推断其所属子系统。

---

## 8. 变更记录

| 日期 | 变更 |
|:---|:---|
| 2026-09-19 | 首版：B（lite vs gpnext 内存/CPU/逐帧成本）、C（根因定位与假设排除）、D（改动清单与验证）、复现方式与局限；原始数据归档至 `docs/perf/shell-ab-2026-09-19/` |
| 2026-09-19 | **补充 §3.3「逐帧 JS 的归因」**（CDP Profiler + `Performance.getMetrics` + 引擎阶段/组件钩子）：确认 82–85% 的墙钟是页内 JS 执行；组件 `update` 仅 11%、Cocos System ≈0%；大头在引擎内部（渲染数据更新约 24%、DragonBones 约 16%、GC 约 9–10%）；spine/ammo 的 wasm 被加载但 **0 帧执行**。新增 §1.3 陷阱 7–8（单轮 fps 不可比、rAF 空帧陷阱）与相应的复现说明 |
| 2026-09-19 | **推翻 §4.3 早先的「帧率上限 60 提升 21%」**：交替 A/B（n=3/档）实测 999 → 16.53 fps vs 60 → 14.24 fps，**限帧反而慢 13.8%**；查明早先结论源于探针把限帧后的 rAF 空帧计为帧。`FRAME_RATE_CAP` 默认改为 **0（不干预）**，实现改为启动后持续纠正（payload 会把 `frameRate` 设回 999）；§2.2 补注两产物 JS 逐字节相同、CPU 差异不成立；§5/§3.6 补入新排除项 |
