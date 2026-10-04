# 性能文档与原始数据

## 报告
| 文档 | 内容 |
| :--- | :--- |
| [WEBVIEW_PERF.md](WEBVIEW_PERF.md) | ArkWeb 内核版本对应、负载实测、壳层问题清单与优化优先级 |
| [SHELL_PERF_2026-09-19.md](SHELL_PERF_2026-09-19.md) | 壳层性能真机复测（Lite / GP-Next 对照、根因定位、改动验证）|
| [GAME_SIDE_OPTIMIZATION.md](GAME_SIDE_OPTIMIZATION.md) | 游戏侧（负载侧）优化方案分析（周期定时器成本、长任务、分配实测）|

## 原始数据
| 目录 | 内容 |
| :--- | :--- |
| `shell-ab-2026-09-19/` | 壳层 A/B 复测原始输出（hidumper、raf/framerate、归因）|
| `game-side-2026-09-19/` | 游戏侧归因实测（trace、timers、profile）|
| `browser-bench-2026-09-18/` | 浏览器跑分对照（ArkWeb / Edge / WebView，Speedometer 3）|
