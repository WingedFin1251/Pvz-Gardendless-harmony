# 内存健康复核：**不是泄漏**（平板 10 分钟长采样）

> 日期：2026-10-07 ｜ 设备：HUAWEI MatePad 11.5"S 灵动款（tablet）
> 起因：平板测试期间短采样看到 `Total Pss` 5 分钟涨了约 50MB，怀疑增长/泄漏。

## 方法（关键：要跑够长，并且看"谷底"而不是瞬时值）

- 每 **30 秒**采样一次，共 **20 次（9.7 分钟）**，全程同一进程（pid `49452`，无重启）；
- 每次把 **`hidumper --mem <pid>` 原文整份存档**（`tablet-mem-raw-*.txt`），指标另存 CSV；
- ⭐ 判据：**看 GC 后的"谷底"有没有抬升**，以及 `native heap` / `Total Pss` 有没有单调增长
  —— 单个采样点根本区分不出"泄漏"和"锯齿"。

## 结果

| 指标 | 起点 | 峰值 | 终点 | 判定 |
| :--- | ---: | ---: | ---: | :--- |
| `Total Pss` | 1,481,072 kB | 1,365,168 kB | **1,292,367 kB** | ✅ **净降 190MB**，无增长 |
| `native heap` | 56,912 kB | 51,078 kB | **46,782 kB** | ✅ 稳定在 43~51MB 区间 |
| `ark ts heap` | 5,041 kB | **59,286 kB** | 59,286 kB | ✅ **锯齿 + 平台期**（不是单调上升）|
| `Swap Total`（整进程）| 99,780 kB | 115,112 kB | **103,668 kB** | ✅ 净增仅 +3.9MB，且会回落 |

**`ark ts heap` 的完整走势**（典型锯齿）：
`5 → 12 → 18 → 19 → 20 → 21 → 22 → 18(谷底) → 22 → 17.6(谷底) → 29 → 43 → 57 → 58 → 59 → 59 → 58 → 58 → 59`（MB）

⇒ ⭐ **谷底对比**：上一轮短采样谷底 24.8MB → 本轮谷底 **17.6MB** ⇒ **没有抬升** ⇒ **不是泄漏**。
本轮末尾停在 ~59MB 是**平台期**（存活集大小），不是持续增长。

**一个附带的好信号**：`ark ts heap` 的 Swap 从 11,516 kB 掉到 **1,368 kB（−88%）**
⇒ GC/稳定后堆被换回物理内存。

## 结论

✅ **10 分钟游玩 + 待机期间内存稳定，没有泄漏迹象**：
`native heap` 平稳、`Total Pss` 净下降、`ark ts heap` 呈锯齿且谷底不抬升、swap 稳定。

⚠️ **边界（必须说清）**：
1. **只覆盖 9.7 分钟**。AGENTS 里有一条旧记录：真机 **8 小时会话**后 swap 用满、被 `SwapFull` /
   `LowMemoryKill` 各杀一次（当初因此加了 `setRenderProcessMode(SINGLE)`）。
   ⭐ 今天省下的 **140MB native 堆**应当直接改善这条，但**10 分钟窗口证明不了 8 小时** ⇒
   要确认得跑一次长会话。
2. 本结论来自**平板**；手机未做同等长采样（手机当前装的是带临时计数器的诊断构建）。

## 工具坑（本次踩到）

- ⭐ **读取自己的 CSV 时用错了过滤条件**：我用 `^\d\d:\d\d:\d\d` 去挑行，而每行其实以 `sample,` 开头
  ⇒ 得到"0 个采样点"的假结论（又犯了"先怀疑探针"这条）。**教训：读自己的产物前，先看一条真实行的样子。**
- `hidumper --mem` 的行名**不是固定标签**：平板输出里没有 `arkweb-pa heap`（该项留空），
  且不同机型/版本的行名可能不同 ⇒ 采样脚本应**动态抓所有 `…heap` 行**（本轮已改成这样并把原文存档）。

## 相关

- `docs/perf/RESOURCE_CACHE_AB.md`（缓存移除：native 堆 −140MB）
- `docs/perf/MIRROR-DEDUPE.md`（镜像节流 −92% 跨进程搬运 + 双设备帧率验收）
- 原始数据：`.clean-staging/gpnext-diag/tablet-mem-raw-152315.txt`、`tablet-mem-long-152315.csv`

---

# 补充分项分析（同日稍晚）：内存的 **74% 是负载的 `GL`**，壳层侧已到头

方法：把之前长采样时**存档的 `hidumper --mem` 原文**逐份解析（**不用设备、0 成本**），
看 `Total Pss` 到底由哪些类别构成、以及**哪一项在波动**。

## 最终构成（Total 1,292,367 kB）

| 项 | Pss | 占 Total |
| :--- | ---: | ---: |
| ⭐ **`GL`（图形/GPU 内存）** | **956,156 kB** | ⭐ **74.0%** |
| `Graph` | 81,904 kB | 6.3% |
| `.so`（引擎代码） | 69,043 kB | 5.3% |
| `ark ts heap` | 59,286 kB | 4.6% |
| `native heap` | 46,782 kB | 3.6% |
| `AnonPage other` | 17,409 kB | 1.3% |
| `FilePage other` | 15,306 kB | 1.2% |
| 其余（`stack`/`.hap`/`.ttf`/`.db`/`dev`）| < 2,200 kB | < 0.2% |

## ⭐ 关键发现：总波动 **99.9% 由 `GL` 解释**

- `Total` 的峰-谷 = **342,092 kB**
- `GL` 的峰-谷 = **341,672 kB**
- `GL` 在采样中**自己从 1,182,664 → 840,992 → 956,156 kB**（一次 **342 MB 的摆动**）

⇒ 说明这份贴图内存是**可释放的**，且**实际发生过释放**。

## 结论

| 归属 | 大小 | 还能压吗 |
| :--- | :--- | :--- |
| ⭐ **壳层自有**（`native heap` + `ark ts heap` + `AnonPage` + `FilePage`）| **约 140 MB（≈9%）** | ⚠️ **基本到头**（今天已砍掉 140MB 的 LRU 缓存）|
| `.so`（引擎代码）| 69 MB | ❌ 不可压 |
| ⭐ **`GL`（负载贴图）** | ⭐ **约 1 GB（74%）** | ⚠️ **只能从负载侧压**（贴图分辨率 / 图集 / `assetManager.autoReleaseAssets`，引擎里该 API 存在）|

## ⚠️ 一次"差点提重复项"的自我修正（值得记）

我一度准备把「**让页面在内存压力下释放未使用的贴图**」列为**新的**优化方向
（依据正是上面那个 342 MB 摆动 + 引擎里确有 `releaseUnusedAssets`）。
**动手前先读了代码**，结果发现：`EntryAbility.onMemoryLevel`（L57-71）**早就实现了**，而且是走**官方 API**：

```ts
if (level >= AbilityConstant.MemoryLevel.MEMORY_LEVEL_CRITICAL) {
    pressure = webview.PressureLevel.MEMORY_PRESSURE_LEVEL_CRITICAL;   // 修过：原实现 `>= MODERATE(=0)` 恒真
}
webview.WebviewController.trimMemoryByPressureLevel(pressure);
```

⇒ 这比"用 `runJavaScript` 去调 `cc.assetManager.releaseUnusedAssets()`"**更好**（平台正规路径，且修剪整个 Web 引擎）。
⇒ ⭐ **教训：提"新方向"之前，先读一遍现有代码**；"以为删掉了"的东西可能还在、而且是对的。

## 壳层侧内存手段清单（都已具备）

1. ✅ **删掉 LRU 负载缓存整条路径**（native 堆 **−140 MB**，实测）
2. ✅ **内存压力响应**：`onMemoryLevel` → `trimMemoryByPressureLevel`（含等级映射修正）
3. ✅ **单渲染进程** `setRenderProcessMode(SINGLE)`（针对真机长会话被 `LowMemoryKill`）
4. ✅ **不做整份数组拷贝**（`onInterceptRequest` 直通；已删掉 `toExactArrayBuffer`）

⇒ **结论：壳层这边没有量级可挖的内存项了**；剩下的在**负载资产**上（属上游）。
