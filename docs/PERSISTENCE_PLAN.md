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
| 配置与 HUD 状态 | `gpn_killlevel_threshold_cfg_v1`、`gpn_killlevel_hud_folded`、`gpn_killlevel_lsoff_v2`、`gpn_killlevel_reset_v4`、`gpn_killlevel_debug` |
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
| **A1（推荐·一期）** | 把白名单从"固定键"扩展为"**前缀允许列表**"：凡形如 `gpn_` 的键一律镜像 | 一条规则覆盖本模组**全部 23 个键**（含 1 个 HUD 调试读数开关）（含动态拼接键）；改动小、语义清晰；`gpn_` 是 GP-Next 自己的命名空间，撞车概率极低 | 若将来出现超大值（如 `pvbackup` ≈ 玩家档大小）会推高 Preferences 体积 | 我们 |
| A2（二期可选） | **全量镜像**：除一个**黑名单**外，所有 `localStorage` 键都镜像 | 一劳永逸，任何模组都受益 | 会把引擎/浏览器自身的杂键也搬进来（体积与语义不可控）⇒ 需要**键数上限 + 单值上限 + 黑名单** | 我们 |
| A3 | 模组在 `pack.json` 里**声明自己的存储键** | 精确、可控 | 需要改**模组规范**并让作者逐一适配 ⇒ 覆盖不了存量模组 | 上游+作者 |
| A4 | 模组改用**沙箱目录**（`files/gp-next/…`，本来就不怕清缓存） | 最彻底（数据根本不在 `cache/`）| 需要作者改代码；且模组是"网页上下文"，走文件得经 GP-Next 的文件 API | 作者 |
| A5 | 不动，仅记录已知限制 | 零风险 | 问题保留 | — |
| **A6（本文补充）** | 在**设置面板里加「导出 / 导入」按钮**：把 `localStorage` 导出成文件（用户自选位置），需要时再导回 | 用户自己掌控 ✓；不依赖模组的键名 ✓；文件在应用之外 ⇒ **连卸载都挺得过** ✓✓；任何模组都受益 ✓ | **手动**（得记得导）；导入方向有风险（写回 localStorage 可能弄坏存档）⇒ 必须配套校验/自动备份/二次确认 | 我们 |

---

## 4. 推荐方案（A1）的改动点

> 目标：**只扩张"要镜像的键"的判定，不改变镜像与回填的机制**。

1. **注入脚本（`entry/src/main/resources/rawfile/touchPatch.js`）**
   - 现在：`PERSIST_KEYS = ['PvZ2_PlayerProperties', 'PvZ2_Settings', 'gp-next-settings']`，按**精确匹配**决定是否 `saveToNative`
   - 改为：`shouldPersist(key)` 判定 = **精确列表 ∪ 前缀列表**（前缀列表先放 `['gpn_']`）
   - 回填侧（`loadFromNative` 的填充循环）用**同一个判定**，避免"写得进、填不回"的不对称
   - 保持既有教训：回填条件必须是 **`if (nativeValue)`**（原生侧有值就覆盖），不要再退回"页面侧没有才填"
2. **ArkTS 侧（`services/PreferenceStore.ets`）**
   - 它**不做键校验**（只 `store.put(key, value)`）⇒ **白名单判定其实只在 `touchPatch.js` 一侧** ⇒ A1 实际上只需改**一个文件**
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
---

## 9. 补充方案 A6：设置面板里的「导出 / 导入」

> 由用户提出：既然模组把数据放在 `localStorage`，那就在**设置里加一个导出按钮**，把 `localStorage` 导出到本地。
> 结论：**可行且推荐作为 A1 的补充**（不是替代）—— A1 负责"日常不丢"，A6 负责"能搬走、能回滚、能挺过卸载"。

### 9.1 架构上的关键约束

**面板（ArkTS）读不到 `localStorage`** —— 那是网页上下文里的东西，必须走"原生 ↔ 页面"通道。

| 能力 | 官方 API（已核对 SDK `@ohos.web.webview.d.ts`）| 我们现状 |
| :--- | :--- | :--- |
| 原生 → 页面（执行 JS 并取回结果） | `runJavaScript(script: string): Promise<string>`；`runJavaScriptExt(script: string \| ArrayBuffer): Promise<JsMessageExt>` | 未用（控制器已在手） |
| 页面 → 原生 **大数据通道** | `createWebMessagePorts(isExtentionType?): Array<WebMessagePort>` + `postMessage(name, ports, uri)`；端口收发支持 **`ArrayBuffer \| string`** | 未用 |
| 选落点保存文件 | `DocumentViewPicker.save` | ✅ 已有 `FilePickerHelper.selectSavePath()` |
| 选文件打开（导入用） | `DocumentViewPicker.select` | ✅ 已有第二个方法 |

⇒ **不需要引入任何新文件 API**；主要是把"面板 → 页面"这条通道接起来。

### 9.2 导出流程（建议）

1. 设置面板新增一节「数据备份」，一个按钮 **「导出存档与模组数据」**
2. ArkTS → 页面：执行收集脚本，遍历 `localStorage`（`length` + `key(i)`），产出 `{ key: value }` 的 JSON
3. 结果通过**消息端口**（大数据）或 `runJavaScriptExt` 回传；**不建议**用 `runJavaScript` 回传整份大字符串
4. 调 `FilePickerHelper.selectSavePath('pvzge-localstorage-<日期>.json')` ⇒ **用户自选位置**（如「下载」）
5. 复用现有落盘逻辑写文件 + `StatusToast` 提示成功与文件名
6. 可选：先提示**体积**（整份可能 0.4~1 MB，其中玩家档约 175 KB、模组备份键可能再约 175 KB）

### 9.3 导入流程（建议，**这是有风险的方向**）

1. 面板「导入」按钮 ⇒ 用已有的 `DocumentViewPicker.select` 选文件
2. **先校验**：必须是 JSON 对象、键与值均为字符串、总大小有上限、键数与键名长度有上限
3. **自动备份**：覆盖前先把**当前** `localStorage` 导出一份到应用自己的 `files/` 下（安全性 > 便利性）
4. 经**消息端口**把 JSON 送进页面，在页面侧逐键 `setItem`
5. **不做自动重载**：提示用户"重启应用后生效"（游戏在启动时读 `localStorage`）
6. 每步都要有明确的成功/失败提示；**绝不在启动时自动导入**

### 9.4 与 A1 的关系（互补，不是二选一）

| | A1（前缀镜像到 Preferences）| A6（导出/导入文件）|
| :--- | :--- | :--- |
| 触发 | **自动**，用户无感 | **手动**，用户主动 |
| 覆盖范围 | 我们选定的键（如 `gpn_`） | **全部** `localStorage`，且**不依赖键名** |
| 清缓存后 | ✅ 自动恢复 | ✅ 可手动恢复 |
| 卸载后 | ❌ 一起没（Preferences 随应用删除） | ✅ 文件在应用之外，**仍在** |
| 可回滚 | 弱 | ✅ 导出前后可对比、可回退 |
| 风险 | 低（只读镜像 + 有护栏） | 中（**导入写回**可能弄坏存档 ⇒ 靠校验/备份/确认兜住）|

### 9.5 验证方案（A6 专项）

1. **导出**：按按钮 → 选「下载」→ 确认文件存在且是合法 JSON（可读回键名列表）
2. **清缓存**：`bm clean -c` + `force-stop` → 冷启动 ⇒ 模组数据归零（复现）
3. **导入**：按按钮 → 选刚导出的文件 → 按提示重启 ⇒ **模组等级/计数恢复**
4. **回归**：游戏本体存档与面板设置不受影响；无崩溃；导入非法文件时**给出明确报错且不改动任何数据**
5. **卸载验证**（A6 独有的价值）：卸载应用 → 重装 → 导入该文件 ⇒ 数据仍能找回
### 9.6 官方文档复核结论（2026-10-05，用 harmonyos-docs 技能逐条核对）

对 §9.1 的 API 表做了官方文档复核（不只看 `.d.ts` 签名，还看文档的用法与限制），四点结论：

1. **`WebStorage` 不能读数据** —— 官方只有这些方法：
   `deleteOrigin(origin)`、`getOrigins()`、`getOriginQuota(origin)`、`getOriginUsage(origin)`、`deleteAllData(incognito?)`。
   ⇒ **没有读取键值的接口** ⇒ 导出/导入**仍然必须走 JS 通道**（§9.2 / §9.3 成立，不用改）。
2. **但 `WebStorage` 有一个白送的用途**：面板可以**完全不碰 JS** 就显示"网页存储占了多少字节"
   （`getOriginUsage` / `getOriginQuota` / `getOrigins`）⇒ 导出前先给用户看体积；
   另有 `deleteOrigin` / `deleteAllData` 可做"清空网页存储"（危险操作，需强确认）。
3. **`runJavaScript` 的官方注意事项**：
   - 「**异步**执行…结果通过异步回调返回」「必须在**用户界面（UI）线程**上使用」
   - 「JavaScript 脚本若执行失败**或无返回值时，返回 null**」⇒ 必须把 null 当作失败处理，不能当空数据
   - 存在错误码 `17100003`（经 runJavaScript 调用返回空 ArrayBuffer 的 JS 方法）
   - **文档没有写出返回值大小上限** ⇒ §9.2 里"大数据优先用消息端口"是**稳妥选择**而非硬性限制（如实表述）
4. **`WebMessagePort` 确实能扛大数据**：官方示例显示端口可收发 `string` 与 `ArrayBuffer`
   （`setString` / `setArrayBuffer`，接收侧用 `onMessageEvent` 按 `WebMessageType.STRING/ARRAYBUFFER` 分发）。

**另有一条尚存的未知**：文件选择器（`DocumentViewPicker.save`）在**本应用里的**落盘行为
与"下载上传"路径**尚未在真机上端到端验证过**（验收清单第 6 项仍为未验证）⇒
A6 实施时，**第一步应先验证"能选位置并写成功"**，再谈导入。
### 9.7 官方对 DOM Storage 的措辞 vs 我们的实测（重要澄清）

官方《管理Cookie及数据存储》原文：

> **DOM Storage 包含了 Session Storage 和 Local Storage 两类**。Session Storage 为临时数据，
> 其存储与释放跟随会话生命周期；**Local Storage 为持久化数据，保存在应用目录下**。

⚠️ 但本项目**实测**：Local Storage 的物理位置在应用私有目录的 **`cache/web`** 下，
**系统的「清除缓存」会把它一起删掉**（这正是用户遇到的现象），而 Preferences（`game_save`）不受影响。

⇒ 结论：官方所说的"**持久化**"指的是**跨会话保存**（关掉再开还在），
**并不等于"免疫系统清缓存"**。请勿据此认为模组数据本来就安全 —— **它确实会被清掉**。

**推论（对 A6 有利）**：既然原生侧只能"查询用量/删除"（§9.6 第 1、2 条），
那么**导出**就只能走 JS 通道；而"**显示占用体积**"与"**清空网页存储**"可以用原生的
`WebStorage` / `removeCache` 完成，不必经过页面。
