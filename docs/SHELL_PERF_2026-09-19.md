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
| 5 | **引擎帧率上限设为 60 比不设上限快 21%** | 🅐 | `cc.game.frameRate` 999（不设）→ 29.46 fps；设 60 → **35.65 fps**；设 30 → 32.28 fps |
| 6 | **官方「App CPU 使用率」只统计应用主进程，漏掉渲染进程** | 🅐 | 同刻实测主进程 9.37%（官方均值 8.97% 与之相符），而渲染进程另有 14.84% |
| 7 | 设备已到**热/功耗墙**：196 s 内高温占比 100%、CPU 73.4 ℃ | 🅐 | 官方导出温度段 |
| 8 | WebGL 显存挂在**应用主进程**（`GL` 行），`:render` 子进程 GL 恒为 0 | 🅐 | hidumper 内存表 |
| 9 | 卡顿不只来自"慢"，还有 **50–1680 ms 的长任务**阻塞主线程 | 🅐 | `raf-baseline.json`：30 s 内 28 个长任务，最长 1680 ms；官方"单帧超 100 ms 占比 2.95%、抖动率 25.18%"与之吻合 |

**一句话**：这块平板（Kirin T91C / 8 GB）跑 GP-Next 负载时，每帧需要约 32 ms 而预算是 16.7 ms，
超出预算的部分来自页内逐帧计算；GPU 未被压满，壳层侧也已没有可再压榨的余量（见 §5）。

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

### 1.2 三种测量手段

| 手段 | 覆盖内容 | 归档形式 |
|:---|:---|:---|
| **华为「性能分析」导出**（196 s，约 1 Hz） | fps / 卡顿 / 逐核 CPU / GPU / 内存分类 / 温度 / 功耗 | 官方汇总转录 + 逐秒内存序列 → [`official-fps-summary.md`](perf/shell-ab-2026-09-19/official-fps-summary.md)、[`official-memory-detail.tsv`](perf/shell-ab-2026-09-19/official-memory-detail.tsv)；源文件校验值见 [`SOURCE-PROVENANCE.md`](perf/shell-ab-2026-09-19/SOURCE-PROVENANCE.md) |
| **页内探针**（ArkWeb DevTools 协议注入） | 逐帧 `requestAnimationFrame` 间隔、长任务、draw call 数、heapUsed | [`degrade-*.json`](perf/shell-ab-2026-09-19/)、[`raf-*.json`](perf/shell-ab-2026-09-19/)、[`reload-ab-*.json`](perf/shell-ab-2026-09-19/) |
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

### 3.3 抖动来源：长任务阻塞，而非"均匀地慢"

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

### 3.4 综合根因

```
每帧 32~35 ms（预算 16.7 ms）
├─ ~28 ms  页内计算（场景遍历/动画/spine/物理 + 引擎逐帧逻辑）   ← 主因（证据 A+B+C）
├─ ~10 ms  WebGL 提交（约 250~400 次 draw，每次 0.087~0.107 ms）  ← 次因，且与像素量无关（证据 D）
└─ GPU 侧：未饱和（最高频占比 0%，证据 §3.1）                      ← 不是原因
```

### 3.5 被本次实测**排除**的假设

| 假设 | 实测结果 | 结论 |
|:---|:---|:---|
| "GPU 性能不足" | 最高频占比 0.00%、平均频率 44.6% | 排除 |
| "分辨率/抗锯齿太贵" | 像素降 61%、关 MSAA 后每 draw 不变 | 排除 |
| "渲染进程模式选错" | 移动端 SINGLE 为官方默认；改 MULTIPLE 反而增加内存 | 排除（见 §5） |
| "`lite` 负载更小所以更快" | 每 draw 成本与 `gpnext` 相同 | 排除 |
| "30 fps 上限更稳" | 60 上限 35.65 fps > 30 上限 32.28 fps > 不设限 29.46 fps | 反向（见 §4.3） |

---

## 4. D：已实施的壳层改动与验证

### 4.1 改动清单

| # | 位置 | 改动 | 对应结论 |
|:--|:---|:---|:---|
| 1 | `resources/rawfile/touchPatch.js` | 三个 document 级 touch 监听补 `{ capture: true, passive: false }` | 修复 `preventDefault()` 被忽略 + 每次触摸一条 Error（143 条/分钟 → 0） |
| 2 | `pages/Index.ets` | `onConsole` 只转发 Warn/Error，并 `return true` 抑制默认 hilog | 去掉逐帧 info 级日志对主线程的负担 |
| 3 | `entryability/EntryAbility.ets` | `setWindowKeepScreenOn(true)` | 挂机常亮；并降低熄屏转后台被系统回收的概率 |
| 4 | `entryability/EntryAbility.ets` | `setRenderProcessMode` 按设备分流（移动 SINGLE / 2in1 MULTIPLE）+ hilog 输出实际模式 | 依官方《ArkWeb 进程》移动端默认策略，避免在移动端白白多用内存 |
| 5 | `resources/rawfile/touchPatch.js` | 新增可调查性能档位 `FRAME_RATE_CAP`（默认 **60**）/ `RENDER_SCALE` / `DISABLE_MSAA` | 由 §4.3 的实测驱动 |

### 4.2 逐项验证

| 改动 | 验证方式 | 结果 |
|:---|:---|:---|
| 1 | 注入 12 次触摸后统计被动监听相关 Error | 🅑 0 条（改前 143 条/分钟） |
| 2 | `onConsole` 计数 | 🅑 web-console 只剩 warn/error |
| 3 | 设备端观察 | 🅑 屏幕不再自动熄灭 |
| 4 | `hilog` 输出 | 🅑 `渲染进程模式: SINGLE(移动设备)` |
| 5 | 页内探针 3 档对照 | 🅐 [`raf-framerate-ab.json`](perf/shell-ab-2026-09-19/raf-framerate-ab.json) |

### 4.3 引擎帧率上限：60 优于不设限（可操作的一项）

| `cc.game.frameRate` | fps | 平均帧间隔 | p95 | 超 33 ms 帧数 |
|:---|---:|---:|---:|---:|
| 999（不设限，原状） | 29.46 | 33.94 ms | 66.7 | 195 / 590 |
| **60** | **35.65** | **28.05 ms** | **50.0** | **152 / 713** |
| 30 | 32.28 | 30.98 ms | 50.1 | 186 / 646 |

不设限（`999`）会让引擎按"能跑多快跑多快"驱动，在 120 Hz 面板上产生持续的帧预算竞争；
**限到 60 反而提升 21%**。这是本次唯一一项明确正向的帧率改动，已作为默认值写入 `touchPatch.js`。

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
| 壳层继续做"性能优化" | 壳层已无余量：§3 证明瓶颈是页内逐帧计算，壳层能动的只有日志与生命周期（已做完） |
| 重新编码基础版游戏负载 | 与"保留原版发布产物、可逐字节比对"的仓库定位冲突（见 WEBVIEW_PERF.md §2 结论） |

**剩余唯一有量级的优化方向在负载侧（游戏 JS/引擎）**，不在壳层，且需要改动第三方导出产物——本报告不主张做。

---

## 6. 复现方式

### 6.1 页内逐帧探针（需要 DevTools 通道）

```bash
# 1) 构建时打开 Web 调试（Index.ets 中 ENABLE_WEB_DEBUG = true），安装并启动
# 2) 找到渲染进程 pid（注意：本应用会存在两个 :render 进程，累计 CPU 时间大的那个才是干活的）
hdc shell "ps -ef | grep com.gardendless.gpnext"
# 3) 建立 DevTools 通道（devtools 只监听 localhost/::1，用 127.0.0.1 会 404）
hdc fport tcp:9367 localabstract:webview_devtools_remote_<忙的 render pid>
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

1. **每帧 32 ms 的构成还不能分解到线程级**：证据 A 只能给出"主进程每帧 ≈31 ms"的下限
   （渲染进程未计入），证据 C（🅑）给出"其中约 10 ms 与 GL 提交相关"。
   要把"JS 计算 / GL 提交 / 等待"三者拆开，需要线程级 CPU 时间：
   `@ohos.hidebug.getAppThreadCpuUsage()` 或 DevEco Profiler 的线程时间线。
   这是**下一步唯一值得做的实验**。
2. **`:render` 有两个进程**（一个累计 CPU 0 s 的"闲孪生"）这一现象未查明来源，
   本报告只如实记录；`setRenderProcessMode` 的取值是否影响它，尚未验证。
3. **降分辨率 A/B 的场景不同**（对照 292 draw vs 降级 371 draw），
   只能比较"低 draw 数区间"的两点（203 vs 259），n 偏小。
4. **热漂移**未做交替执行（A/B/A/B）设计，§4.4 的"中性"结论是保守表述。
5. `dump-sheet2` 抽样的官方内存序列为**每 10 s 一点**，峰值时刻可能有遗漏（官方给出峰值 PSS 1470.92 MB 可作上界）。

---

## 8. 变更记录

| 日期 | 变更 |
|:---|:---|
| 2026-09-19 | 首版：B（lite vs gpnext 内存/CPU/逐帧成本）、C（根因定位与假设排除）、D（改动清单与验证）、复现方式与局限；原始数据归档至 `docs/perf/shell-ab-2026-09-19/` |
