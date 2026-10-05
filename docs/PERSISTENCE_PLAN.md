# 预案：让 GP-Next 模组的数据也能挺过「清除缓存」

> 状态：**仅预案，未改任何代码**。写于 2026-10-05。
> 触发问题：用户安装模组《植物等级扩展》后，**在系统里清除应用缓存**，该模组的游玩数据（植物等级/成长计数）**归零** ✗。
> 相关文档：[本地资源读取机制](RESOURCE_LOADING.md)、[架构概览](ARCHITECTURE.md)

---

## 1. 问题与确诊

### 1.1 现象
- 模组：《植物等级扩展》v0.5.3（uuid `904e0c30-08cf-4722-903f-92503e8edbb5`，能力 `combat.behavior-hook`）
- 清缓存后：**游戏本体存档完好** ✓，**该模组的游玩数据归零** ✗

### 1.2 确诊：模组把数据放在 `localStorage`
证据来自模组自身代码（`files/gp-next/packs/<mod>/js/main.js`，875.8 KB）：

| 用途 | 键 |
| :--- | :--- |
| 四份成长计数 | `gpn_killlevel_plantkills_v3`、`gpn_killlevel_plantproduces_v3`、`gpn_killlevel_plantsupports_v4`、`gpn_killlevel_plantplanted_v3` |
| 等级/觉醒/突破基准 | `gpn_killlevel_kills_v2`、`gpn_killlevel_awaken_v1`、`gpn_killlevel_awakenbase_v1`、`gpn_killlevel_breakbase_v1` |
| 存档作用域与指纹 | `gpn_killlevel_save_id`、`gpn_killlevel_lastscope_v1`、`gpn_killlevel_scopefp_v1` |
| 配置与 HUD 状态 | `gpn_killlevel_threshold_cfg_v1`、`gpn_killlevel_hud_folded`、`gpn_killlevel_lsoff_v2`、`gpn_killlevel_reset_v4` |
| 日志与注入控制 | `gpn_level_log_db`、`gpn_level_log_lines_v1`、`gpn_level_inject_blacklist_v1`、`gpn_level_inject_blacklist_ver`、`gpn_level_inject_subset`、`gpn_level_once_reset_ver` |
| 玩家档备份 | `gpn_killlevel_pvbackup_v1`（另有 `PV_KEY = 'PvZ2_PlayerProperties'`，即直接读写游戏存档） |
| 动态键 | `LOG_KEY = LOG_KEY_LEGACY + '_' + BUILD_TAG`（键名**运行时拼接**） |

模组目录内**只有静态内容**（`js/` + `jsons/{extensions,features,objects}` + `pack.json`），`files/` 下**无任何近期写入** ⇒ **它不写沙箱目录**。

### 1.3 为什么清缓存会丢
- ArkWeb 的 `localStorage`（DOM Storage）物理位置在应用私有目录的 **`cache/web`** 下
  （实测存在 `/data/app/el2/100/base/<bundle>/cache/web`，且为应用私有权限，普通 shell 与 `run-as` 均不可读）
- 系统「清除缓存」= 清理 `cache/` ⇒ **`localStorage` 被整体删除** ⇒ 模组数据丢失
- 而**游戏本体存档**之所以没事：`PvZ2_PlayerProperties` / `PvZ2_Settings` / `gp-next-settings` 已在
  `touchPatch.js` 的 `PERSIST_KEYS` 白名单里，被**镜像**到 Preferences（`game_save`）⇒ 清缓存后能回填

### 1.4 结论
这是**同一个根因的第二例**：以前是"面板设置"没进白名单，这次是**第三方模组的键**没进白名单。
模组的键名是**它自定义且动态的**，现有的**固定键白名单**天然覆盖不到。

---

## 2. 目标与非目标

**目标**
- 模组写在 `localStorage` 里的数据，在**清除缓存 / 冷启动**后仍能恢复
- 不改动游戏存档格式、不改动模组代码、不引入网络依赖

**非目标**
- 不做"跨设备/云同步"
- 不解释或改写模组的数据语义（我们只做**搬运与回填**）
- 不替模组作者修它的作用域判定逻辑

---

## 3. 方案对比

| 方案 | 做法 | 优点 | 缺点/风险 | 谁做 |
| :--- | :--- | :--- | :--- | :--- |
| **A1（推荐·一期）** | 把白名单从"固定键"扩展为"**前缀允许列表**"：凡形如 `gpn_` 的键一律镜像 | 一条规则覆盖本模组**全部 22 个键**（含动态拼接键）；改动小、语义清晰；`gpn_` 是 GP-Next 自己的命名空间，撞车概率极低 | 若将来出现超大值（如 `pvbackup` ≈ 玩家档大小）会推高 Preferences 体积 | 我们 |
| A2（二期可选） | **全量镜像**：除一个**黑名单**外，所有 `localStorage` 键都镜像 | 一劳永逸，任何模组都受益 | 会把引擎/浏览器自身的杂键也搬进来（体积与语义不可控）⇒ 需要**键数上限 + 单值上限 + 黑名单** | 我们 |
| A3 | 模组在 `pack.json` 里**声明自己的存储键** | 精确、可控 | 需要改**模组规范**并让作者逐一适配 ⇒ 覆盖不了存量模组 | 上游+作者 |
| A4 | 模组改用**沙箱目录**（`files/gp-next/…`，本来就不怕清缓存） | 最彻底（数据根本不在 `cache/`）| 需要作者改代码；且模组是"网页上下文"，走文件得经 GP-Next 的文件 API | 作者 |
| A5 | 不动，仅记录已知限制 | 零风险 | 问题保留 | — |

---

## 4. 推荐方案（A1）的改动点

> 目标：**只扩张"要镜像的键"的判定，不改变镜像与回填的机制**。

1. **注入脚本（`entry/src/main/resources/rawfile/touchPatch.js`）**
   - 现在：`PERSIST_KEYS = ['PvZ2_PlayerProperties', 'PvZ2_Settings', 'gp-next-settings']`，按**精确匹配**决定是否 `saveToNative`
   - 改为：`shouldPersist(key)` 判定 = **精确列表 ∪ 前缀列表**（前缀列表先放 `['gpn_']`）
   - 回填侧（`loadFromNative` 的填充循环）用**同一个判定**，避免"写得进、填不回"的不对称
   - 保持既有教训：回填条件必须是 **`if (nativeValue)`**（原生侧有值就覆盖），不要再退回"页面侧没有才填"
2. **ArkTS 侧（`services/PreferenceStore.ets`）**
   - 它持有白名单校验（防止网页侧随意写键）⇒ 同样改为"精确 ∪ 前缀"
   - 保持"写失败要重试"的既有逻辑（`flushNow` + 延迟重试）
3. **不必改**：`Index.ets` 的 `saveToNative` / `loadFromNative` 转发、`ResourceManager`、`PayloadServer`

### 需要一并加的护栏
- **单值上限**：超过阈值（建议 256 KB）的键**跳过镜像**并记一条 info 日志（`gpn_killlevel_pvbackup_v1` 可能接近玩家档大小，需实测确认）
- **键数上限**：前缀匹配的键最多镜像 N 个（建议 64），防止异常键名爆炸
- **键名长度上限**：过长的键跳过（防止异常数据）
- **写入频率**：模组在关卡里可能**每 500 ms 写一次**，沿用现有的去抖/flush 合并，不要变成"每写必 flush"

---

## 5. 风险与边界

| 风险 | 说明 | 处置 |
| :--- | :--- | :--- |
| Preferences 体积增长 | 多出模组键；`pvbackup` 可能接近玩家档大小 | 单值上限 + 实测体积；必要时把 `pvbackup` 排除在镜像外（它本身是"备份"，可由模组重建） |
| 语义误解 | 模组的计数是**按存档标识分档**的，我们不该解释它 | **逐字搬运**，不解析、不改写；回填时原样还给页面 |
| 过期镜像 | 模组换了存档作用域，旧镜像可能被回填 | 保持"原生有值即覆盖"的既有语义（已实测有效），并把这一点写进注释；必要时提供"清空镜像"入口 |
| 引擎杂键 | A2 才有的问题 | 一期只做 `gpn_` 前缀，天然避开 |
| 回填时机 | 页面 `document-start` 时就回填，早于模组读取 | 现有机制已经如此（`gp-next-settings` 就是这样救回来的），沿用 |

---

## 6. 验证方案（改完后必须做）

1. **基线**：进入关卡，记下模组的植物等级/计数（截图）
2. **写盘确认**：`bm clean -n com.gardendless.gpnext -c` 前，确认 Preferences 里出现 `gpn_*` 键
   （解析 Preferences 时注意 XML 有**两种形态**：`<boolean key=… value=…/>` 与 `<string key=…>内容</string>`）
3. **清缓存**：执行系统「清除缓存」（等价 `bm clean -c`）→ `force-stop` → 冷启动
4. **恢复确认**：模组的等级/计数**回到清缓存前的值**（截图对比）；同时确认**游戏本体存档与面板设置照旧**（回归）
5. **回归项**：启动页→标题/关卡无卡死；`缓存项数已达上限` 不出现；无崩溃；关卡内不卡顿

---

## 7. 未决问题（需要更多信息才能定稿）

1. `LOG_KEY = LOG_KEY_LEGACY + '_' + BUILD_TAG` 的最终形态 ⇒ 是否也在 `gpn_` 前缀内（从常量名看应在）
2. GP-Next **框架自身**是否还用了别的前缀（如 `gpnext_`/`mod_`）⇒ 需要枚举实际键名才能确认
3. `gpn_killlevel_pvbackup_v1` 的**实际体积**（决定要不要把它排除在镜像外）
4. 是否值得做 A2（全量镜像 + 黑名单）作为二期；若做，黑名单如何维护

> ⚠️ 上述第 1~3 项都需要**读取 `cache/web` 里的真实键名**才能确认，而该目录为**应用私有权限**
> （实测普通 shell 读会 `Permission denied`，设备也不提供 `run-as`）⇒ 建议的取证方式见第 8 节。

---

## 8. 取证建议（零改动）

- 方式一（推荐，无需改代码）：在**模组运行中**、清缓存**之前**，用我们已有的 `[payload-cache]` 式日志思路，
  临时在 `touchPatch.js` 的 `saveToNative` 入口打印**键名列表与各键长度**（仅日志，不改判定）⇒ 一轮即可拿到真实键清单与体积
- 方式二：在 `docs` 之外单独开 Web 调试（`ENABLE_WEB_DEBUG`）用 DevTools 读 `localStorage`（需要重新构建）
- 方式三：用行为级验证替代取证 —— 记录等级 → 清缓存 → 重开 → 观察归零（用户已实际观察到）
