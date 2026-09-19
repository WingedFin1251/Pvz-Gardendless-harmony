# 归档：2026-09-19 壳层性能真机复测的原始输出

配套报告：**[../../SHELL_PERF_2026-09-19.md](../../SHELL_PERF_2026-09-19.md)**

设备：HUAWEI MatePad 11.5"S 灵动款（`DMG-W00`），OpenHarmony 6.1.1.120，
ArkWeb 6.1.0.120 / Chromium 132，8 GB RAM + 6 GB swap，屏幕 1840×2800（测试期间 120 Hz）。
应用：`com.gardendless.gpnext` / `com.gardendless.lite`，版本 0.14.0（versionCode 1000007）。

## 文件清单

### 官方「性能分析」导出（196 s，约 1 Hz）

| 文件 | 内容 |
|:---|:---|
| `official-fps-summary.md` | 官方 xlsx「数据」sheet 第 10–11 行及 CPU / GPU / 内存 / 温度 / 功耗各小节的**逐字转录** |
| `official-memory-detail.tsv` | 官方 xlsx「内存明细」sheet 的逐秒序列，按每 10 s 抽样一点（单位 MB） |
| `SOURCE-PROVENANCE.md` | 原始导出各文件的体积与 SHA256；原始导出本身未入库（`.gitignore` 的 `/testing data/`） |

### 设备侧 `hidumper`（每进程内存分类与 CPU 占用）

| 文件 | 取样时刻 | 内容 |
|:---|:---|:---|
| `hidumper-gpnext.txt` / `hidumper-lite.txt` | 启动后 **~35 s** | 第一轮：**只采到主进程与那个"闲" `:render` 孪生进程**（累计 CPU 0 s），漏掉了真正干活的渲染进程 |
| `hidumper2-gpnext.txt` / `hidumper2-lite.txt` | 启动后 **28 s** | 第二轮：**主进程 + 两个 `:render` 全采**。报告 §2.1 的表格用这一轮 |

> 第一轮保留下来有两个原因：一是它与第二轮的主进程 PSS 差异（1202.4 vs 849.6 MB）
> 本身就是"启动期内存快速上涨、取样时刻必须固定"的证据；二是它记录了
> **同一个应用会存在两个 `:render` 子进程**这一现象。
> 两轮都做了裁剪（丢弃 `hidumper -p` 的线程表），未改动任何数字。

### 页内探针（ArkWeb DevTools 协议注入，JSON）

| 文件 | 内容 |
|:---|:---|
| `degrade-new-build.json` | `gpnext` **改动后**构建，5 轮 × 35 s，含 `tickMean` / `drawCalls` / `stalls` |
| `degrade-old-build.json` | `gpnext` **改动前**构建，同条件 5 轮（用于 A/B） |
| `degrade-lite-clean.json` | `lite`，4 轮，**干净样本**（另一个应用已 `aa force-stop`） |
| `degrade-lite-contaminated.json` | `lite`，5 轮，**污染样本**：`gpnext` 同时在后台运行，见报告 §2.3 |
| `degrade-earlier-7rounds.json` | 同日更早的 7 轮基线 |
| `raf-baseline.json` | 30 s 逐帧间隔 + 长任务列表（抖动分析，报告 §3.3） |
| `raf-framerate-ab.json` | ⚠️ **已作废**：`cc.game.frameRate` 三档的**顺序**采样。它用 rAF 回调间隔当帧数，限帧后会把空帧计成帧，因此「限帧 60 更快」是假象；结论见 `rate-ab-engine.json` 与报告 §4.3 |
| `raf-framerate-30.json` | 同上，30 上限的详细分布（同样作废） |
| `rate-ab-engine.json` | ✅ **交替 A/B**（每档 n=3，逐轮交替，读 `cc.director.getTotalFrames()` 真实引擎帧数）：999 → 16.44/16.10/17.04 fps，60 → 12.77/14.82/15.14 fps |
| `reload-ab-control.json` | 分辨率/抗锯齿 A/B 的**对照**组：canvas 2240×1472、antialias `true`、dpr 2.5 |
| `reload-ab-injected.json` | 分辨率/抗锯齿 A/B 的**降级**组：canvas 1400×920、antialias `false`、dpr 1.25 |

### JS 逐帧归因（CDP Profiler + `Performance.getMetrics` + 引擎钩子）

采集条件：`inGameScene`（含 Zomboss 与恐龙的重载场景），三次 12 s 窗口，200 µs 采样，
`cc.game.frameRate = 999`。

| 文件 | 内容 |
|:---|:---|
| `attrib-999-heavy.json` | 一次运行的完整结果：资源清单（含 wasm 请求）、`Performance` 指标增量、引擎阶段耗时、组件级耗时 top-40、V8 profile 的 self Top-40。**已裁掉 2.4 MB 的原始调用树** |
| `analyze-attrib.txt` | 用原始调用树做的离线分析全文：按文件聚合、self Top 30、wasm/GC/idle 帧、`tick`/`frameMove`/`advanceTime` 子树展开、self Top 15 的**调用祖链** |

> 想复现调用树分析，需要重新采集并保留原始 `profile`（驱动脚本 `.tools/cdp-attrib.mjs` 会把
> 完整 profile 写进 JSON），再用 `.tools/analyze-profile.mjs` 分析。

## 引用这些数据的注意事项

1. **只有同次运行、同一取样时刻的数字才能互相比较**：启动后第一分钟内内存快速上涨
   （主进程 PSS 28 s → 849.6 MB，35 s → 1202.4 MB）。
2. **不要从绝对数字直接推结论**：`drawCalls` 随场景状态在 249–451 波动，
   必须折算成"每 draw 成本"（`tickMean ÷ drawCalls`）才可比。
3. **污染样本已单独标注**，不要把它当作 `lite` 的真实表现。
4. 官方导出的功耗/温度含采集工具自身开销（`/bin/hidumper` + `hidumper_service` 共 80.25 mA，
   占整机 8.5%），绝对值偏高。
5. **单轮 fps 不可比**：同一配置连续三次为 27.38 / 21.05 / 18.20 fps（差 1.5 倍）。
   任何 A/B 都要**逐轮交替**（`rate-ab-engine.json` 就是这么做的），
   或改用更稳的「每帧 JS 执行时间」。
6. **不要用 rAF 回调间隔当帧数**：限帧后部分回调是空帧，会把 fps 算高——
   `raf-framerate-ab.json` 正是这么产生的错误结论（报告 §4.3 已推翻）。要用
   `cc.director.getTotalFrames()` 的增量。
7. 归因数据（`attrib-999-heavy.json`）里的组件名是 `cc.js.getClassName` 的真实类名，
   但引擎内部函数名仍是压缩后的；且探针自身的包装帧在 profile 里显示为
   `target.<computed> @ (inline):40`，**不要用经过它的 inclusive 数**。
