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

**第二轮（带时间线采集）独立复现**：`native heap` 中位 **188,477 → 48,439 kB**（−140,038 kB，−74.3%）；
`Total Pss` **859,899 → 721,075 kB**。两轮的取值区间均**完全不重叠**。

### 启动耗时（第二轮补充采集，配对 3+3）

| 里程碑（相对每次启动首行）| **A** 中位数 | **B** 中位数 | 差 |
| :--- | ---: | ---: | ---: |
| 注入脚本就绪 | +8 ms | +9 ms | 噪声 |
| 原生桥注册 | +82 ms | +82 ms | 0 |
| ⭐ **首个负载读取**（`plugin:fs`）| **14.109 s** | **14.145 s** | **+36 ms（噪声级）** |
| 引擎启动日志 | +8.49 s | +8.74 s | 噪声 |

⇒ **启动耗时没有差异**：早先"各 1 次、未配对"的观测（A 快约 0.7–1.2 s）**是噪声**，已被配对实验否掉。

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

## 落地（2026-10-07 已完成）

按上面的结论**直接删掉整条缓存路径**（不是把开关默认关掉——留着一条在生产里永不启用的"同步整文件读"
本身就是陷阱）：`ResourceManager.ets` 整类删除（536 行），`PayloadServer` 只把 `$rawfile`（Resource）
交给内核（231 → 176 行），`Index.ets` 去掉 `readRawfileBytes` 与三处统计打点（1270 → 1231 行），
`EntryAbility.onMemoryLevel` 去掉 `clearCache()`。净 **−603 行**。

**真机复核（装的就是上述构建，冷启动 35 s 后）**：
`ark ts heap` 8,332 kB ／ **`native heap` 46,783 kB** ／ `arkweb-pa` 22,180 kB
⇒ 落在 B 组区间内 ⇒ **约 140 MB 的节省在发布构建上真实成立**。
日志侧同时确认：`ResourceManager 已初始化`、`[payload-cache]`、`资源过大，跳过缓存`、
`同步读取失败…favicon.ico` **全部消失**（最后那条是因为不再做同步读，顺带少了两行 warn）。

## 仍未做 / 边界

- ⚠️ 6 轮均为"冷启动 + 30 s"，不含游玩；游玩场景各 1 次（A 135 MB / B 60 MB，**方向一致**）。
- ⚠️ 本结论来自**手机**（HUAWEI Mate 60 / BRA-AL00 型号）；**平板未测**（预期方向相同，幅度可能不同）。
- ⚠️ 该实验用的两个 HAP（`ab-A-cache-on.hap` / `ab-B-rawfile.hap`）保留在
  `.clean-staging/gpnext-diag/ab/`，对应的是**带开关那一版**源码；当前源码已无开关。

## 相关

- `docs/perf/WEBVIEW_PERF.md`（H1：缓存"只查不写"的原始审计项）
- `.clean-staging/gpnext-diag/AB-EXPERIMENT-LOG.md`（本次实验的现场记录与两包哈希）
- `.clean-staging/gpnext-diag/ab-auto-results.csv`（6 轮原始数据）
