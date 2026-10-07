# 资源缓存（LRU）A/B 实测：结论是**负优化**

> 日期：2026-10-07 ｜ 设备：HUAWEI Mate 60（BRA-AL00 型号，API 26）
> 被测代码：`entry/src/main/ets/services/PayloadServer.ets` 的 `ENABLE_RESOURCE_CACHE` 开关
> 实验目的：判定 `ResourceManager` 这条 LRU 负载缓存**是收益还是负优化**（来自性能审查报告结论 2–5）

## 结论（先说结果）

**它是负优化。** 同一条路径、同一份负载，只把"取字节的方式"换掉：

| 指标（中位数，各 3 次，交替）| **A：同步整文件读 + 回填 LRU** | **B：`$rawfile` 直传（不查缓存）** | 差 |
| :--- | ---: | ---: | ---: |
| `native heap`（kB）| **189,018** | **46,661** | **−142,357（−75%）** |
| `Total Pss`（kB）| **863,522** | **724,166** | **−139,356（−16%）** |
| `ark ts heap`（kB）| 9,107 | 8,493 | −614 |
| 缓存命中率 | 0–1% | ——（不查缓存）| —— |

⇒ **约 139 MB 的 native 堆，换 0–1% 的命中率。** 3 次 A 与 3 次 B 的取值区间**毫无重叠**
（A：140,405–198,768；B：46,565–47,579），属结构性差异，不是抖动。

## 方法（可复现）

| 项 | 做法 |
| :--- | :--- |
| 变量隔离 | 两个 HAP 由**同一份源码**、只差 `ENABLE_RESOURCE_CACHE` 一个常量构建，产物哈希不同 |
| 顺序 | A / B / A / B / A / B **交替**共 6 轮（每档 3 次），避免系统性漂移 |
| 每轮流程 | `aa force-stop` → `install -r` → `aa start`（冷启动）→ **等 30 s** → `hidumper --mem <pid>` |
| 指标取法 | `hidumper --mem` 的 `ark ts heap` / `native heap` / `arkweb-pa heap` / 总 `Total` 行 |
| 缓存签名 | 另开 `hilog -T JSAPP \| grep payload-cache`：A 组报 `21/18/26 项`，**B 组三轮全是 `0 项`** ⇒ 开关确实生效 |
| 自动化脚本 | `.clean-staging/gpnext-diag/run-ab-auto.ps1`（产物放 `dist/` **之外**，构建会清 `dist/`）|

## 为什么"省内存"能省这么多

缓存项是 `Uint8Array`（底层 `ArrayBuffer`）⇒ 占的是 **native 堆**，不是 ArkTS 对象堆 —— 这解释了
`ark ts heap` 几乎不变而同一次测量的 `native heap` 差 139 MB。此外 A 组每轮都要为**每个未命中请求**
分配一份整文件副本（负载里有单文件 8～17 MB 的大图），短命副本会让 native 堆的 Pss 高位滞留
（A 组三轮 140 → 189 → 199 MB **逐轮上行**，B 组稳定在 46.6 ± 1 MB）。

另有一个此前的独立实测：A 组约 3 分钟内 `clearCache`（`onMemoryLevel` 触发）**被调 2 次、每次全清**
⇒ 缓存在真实使用中经常是空的，命中率因此长期趴在 1% ⇒ **收益更小、代价不变**。

## 未测 / 待办

- ⚠️ **启动耗时这 6 轮没有采集**。此前只有各 1 次、且**未配对**的观测（A 快约 0.7–1.2 s），
  **不足以定论**；若要拍板"默认关"，建议补一轮带时间线采集的交替实验（同一脚本加 `hilog` 时间戳即可）。
- ⚠️ 6 轮为"冷启动 + 30 s"，不含游玩；游玩场景目前各 1 次（A 135 MB / B 60 MB，**方向一致**）。
- ⚠️ 本结论来自**手机**；平板未测（预期方向相同，幅度可能不同）。

## 建议

1. 把 `ENABLE_RESOURCE_CACHE` 默认值改为 **false**（最小改动、可随时回退）。
2. 随后清理因之失效的死代码：`ResourceManager` 整类、`PayloadServer` 的同步字节读分支、
   `Index.ets` 的 `readRawfileBytes` 与缓存统计打点、`onMemoryLevel` 里的 `clearCache()`。
3. 若要保留"命中率"这条观测线，改为在 `docs/` 里记录实验，而不是留在生产路径上。

## 相关

- `docs/perf/WEBVIEW_PERF.md`（H1：缓存"只查不写"的原始审计项）
- `.clean-staging/gpnext-diag/AB-EXPERIMENT-LOG.md`（本次实验的现场记录与两包哈希）
- `.clean-staging/gpnext-diag/ab-auto-results.csv`（6 轮原始数据）
