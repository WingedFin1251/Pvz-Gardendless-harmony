# 归档：2026-09-19 游戏侧（负载侧）归因实测

配套文档：**[../../GAME_SIDE_OPTIMIZATION.md](../../GAME_SIDE_OPTIMIZATION.md)**
壳层侧原始数据：[`../shell-ab-2026-09-19/`](../shell-ab-2026-09-19/)

设备：HUAWEI MatePad 11.5"S 灵动款（`DMG-W00`），OpenHarmony 6.1.1.120，
ArkWeb 6.1.0.120 / Chromium 132；应用 `com.gardendless.gpnext` 0.14.0，场景 `inGameScene`。

> ⚠️ 全部数据**包含已安装的 mod 包**（`gp-next://<uuid>/js/main.js`，3 个包、7 个周期定时器）。
> 出厂长按时表现可能更好。

## 文件清单

| 文件 | 内容 | 对应文档章节 |
|:---|:---|:---|
| `install-state.json` | 注入钩子（长任务观察器 + `setInterval` 注册者识别）后 reload 的状态：场景、已注册定时器清单、长任务列表（含时长） | §2.3 |
| `timers-baseline.json` | **周期定时器成本排行榜基线**（20 s）：hp-overlay 81.4 ms/s、mod 500 ms 11.0 ms/s、mod 50 ms 0.7 ms/s；同窗口 `Script`/`Task`/非脚本占比与长任务 | §2.1 · §2.2 |
| `timers-hp-throttled-3.json` | hp-overlay 降频到 1/3 后同格式：81.4 → 26.4 ms/s，非脚本 16.6% → 10.9% | §2.2 |
| `timers-hp-and-mod-throttled-3.json` | hp 1/3 + mod 500 ms 1/3 | §2.2 |
| `ab-hp-frequency.json` | 早先 6×12 s 交替 A/B（hp 1/3 交替）：hp 71.03 → 24.93 ms/s，`ScriptDuration` 几乎不变（787.6 → 780.8 ms/s）——这条证明了 hp 的开销不在 JS 桶里 | §2.2 |
| `alloc-hp-full-speed.json` | hp 全速时的分配采样（`HeapProfiler.startSampling`，16 KB 间隔，12 s）：总 2.45 MB（209 KB/s），Top 分配方 | §2.4 |
| `alloc-hp-throttled-3.json` | hp 降频 1/3 时的分配采样：总 1.84 MB（157 KB/s） | §2.4 |

## 引用注意

1. **不要用 fps 验收这里的效果**：同一关卡相邻 20 s 窗口实测 38.10 / 20.25 / 19.90 fps（差 2 倍），
   5% 级别的收益被场景波动完全淹没。请用「目标模块主线程占用 ms/s」或
   `TaskDuration`/`ScriptDuration` 增量占比。
2. `timers-*` 里的 `timers[label].ms` 是探针给该回调测得的**墙钟时间**（含非 JS 的原生工作，
   如 Label 文本重绘与纹理上传），因此它**大于** `ScriptDuration` 里该模块的份额。
3. `longtask` 条目**没有脚本级归属**（ArkWeb 下 `attribution.containerSrc` 为空），
   所以"稳态 42 个长任务是谁造成的"仍未定位。
4. 分配采样对引擎侧大对象/纹理可能低估，"GC 不由 JS 小对象驱动"的结论**限于 JS 堆**。
