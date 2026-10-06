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

   **格式决定（2026-10-06）：导出为单个 `.json`，不用 zip。** 理由：
   - `localStorage` 的值**本质都是字符串** ⇒ JSON 无损，没有非文本内容可压
   - 实测真实数据量 ≈ **325KB**（玩家档 175KB + 四份计数各约 5KB + 设置/面板约 4KB）；
     日志键 `gpn_level_log_lines_v1_*`（实测 101KB 且持续增长）**默认排除** ⇒ 压缩省下的那点体积没有价值
   - 备份更需要**可读、可手改、可 diff**；JSON 还能自带 `format`/`version` 供**导入时校验**
   - 若将来要导"**模组文件本体**"（`files/gp-next/packs/**`，MB 级）或做**完整备份**
     （localStorage + `files/gp-next/` + Preferences），**那时才改用 zip** ——
     原生 `@ohos.zlib` 已有 `zipFile`/`unzipFile`（可**整目录**打包）与 `compressFile`/`createZip`，
     且本工程已在用 `zlib.decompressFile` 解模组包

   导出文件的形状（导入侧只接受 `format` 匹配且 `version` 已知者，否则明确报错且**不改动任何数据**）：

   ```json
   { "format": "pvzge-localstorage", "version": 1,
     "exportedAt": "2026-10-06T13:50:00+08:00",
     "origin": "https://cocos.local",
     "app": { "bundle": "com.gardendless.gpnext", "version": "0.15.0" },
     "entries": { "<localStorage 键>": "<值>", "...": "..." } }
   ```
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
### 9.8 导出范围与导入语义（2026-10-06 定稿）

**导出范围 —— 三选一（不做逐键勾选，面板放不下也不必要）**

| 范围 | 内容 | 体积（实测基准）| 适用 |
| :--- | :--- | :--- | :--- |
| **① 全部**（默认）| **所有 `localStorage` 键，一个不落**（含日志键 `gpn_level_log_lines_v1_*`）| ≈ 330KB | **备份 / 回滚**（主用途；手动导出就该是"真·完整备份"）|
| **② 仅模组数据** | 仅 `gpn_*`（仍排除日志键）| ≈ 25KB | 分享 / 迁移某个模组的数据 |
| **③ 仅游戏存档** | 仅 `PvZ2_*` | ≈ 178KB | 只备份玩家进度与游戏设置 |

**默认包含日志键**（用户 2026-10-06 明确："手动的话就应该导出所有的键"）—— 手动导出是低频的完整备份，
宁可多带 101KB 也不要漏。若只想给个"能发出去的小文件"，再勾选"排除调试日志"（≈250KB）。

**导入语义（比导出更重要）**

1. **只覆盖、从不删除** —— 只对文件里出现的键执行 `setItem`；文件里没有的键**一律保留**。
   ⇒ 因此导一份"仅模组"的文件**绝不会**动到游戏存档；任何范围导出的文件都能安全回导。
2. **导入前自动备份当前状态**（先自动导一份到应用自身目录）⇒ 导错可退。
3. **二次确认 + 明确提示**（显示将写入多少个键）。
4. **不自动重载** ⇒ 提示"重启应用后生效"（游戏在启动时读 `localStorage`）。
5. **只接受 `format` 匹配且 `version` 已知的文件** ⇒ 否则明确报错且**不改动任何数据**。
6. 文件内保留**原始键名**（见 §9.2 的形状）⇒ 范围选择只影响"导出哪些"，不影响"导入到哪"。
---

## 10. A1.1：把白名单扩为「全部键」——**⛔ 本节不采纳**（2026-10-06 用户拍板）

> **结论：不采纳。** 用户明确划分：**自动**那条路只需"把存档搞好之类的"（精准、轻量、少 I/O），
> **完整**交给**手动导出**（见 §11）。本节保留其**官方限额数据**（键长 1024B / 值长 16MB / 配额可查询），
> 这些仍是 A6 护栏的依据；但"自动镜像全部键"的做法**不做**。

**起因（用户提出）**：`gpn_` 是 GP-Next 自己的命名约定，只覆盖"按约定命名"的模组；
别人写的模组可以用**任意键名**（`MyMod_save` / `plantLv2`，甚至 `settings`）
⇒ **A1 会漏掉它们**。这是 A1 的真实软肋。

**官方限额（本次核对，可作为护栏依据）**

| 常量 | 官方值 | 说明 |
| :--- | :--- | :--- |
| `MAX_KEY_LENGTH` | **1024 字节** | 键长上限（A1 现用 128，偏保守）|
| `MAX_VALUE_LENGTH` | **16MB** | 单值上限（A1 现用 256KB，**偏小 ⇒ 会误丢模组的合法大值**）|
| DOM Storage 配额 | 每源一个配额，**可查询**（`WebStorage.getOriginQuota` / `getOriginUsage`）| 具体数值文档未给，需真机实测 |

**改动（A1.1）**

| 项 | A1（现状）| A1.1（建议）| 理由 |
| :--- | :--- | :--- | :--- |
| 覆盖范围 | 固定 3 键 + `gpn_` 前缀 | **全部键**（不再看前缀）| **与模组命名无关** —— 直接解决本节的起因 |
| 键名上限 | 128 字符 | **1024 字节**（官方值）| 避免误丢合法长键名 |
| 单值上限 | 256KB | **4MB**（官方允许 16MB）| 避免误丢模组的大存档 |
| 键数上限 | 64 | **512** | 避免误丢"写了很多键"的模组 |
| 总量 | 无 | **≈8MB 预算**（超预算则记 warning 并停止新增）| localStorage 每源配额有限，留余量 |
| 写频率 | 每次 `setItem` 一次桥调用 | **页面侧按 key 去抖（~500ms）**，并在 `pagehide`/`visibilitychange` 时强制刷 | 防"每帧都写"的模组把 JavaScriptProxy 调用打爆 |

**代价（如实记录）**
- 会把**垃圾键**（各类缓存、临时标志）也镜像进 Preferences；
- Preferences 文件会变大（当前 313KB ⇒ 可能到数 MB）；
- 换来的收益是**任何模组都不丢**（而不是"按约定命名的模组不丢"）。

**与 A6 的关系**：A6（手动导出/导入）**天生与模组命名无关**；A1.1 让**自动**那一半也做到无关
⇒ 两者合起来才真正覆盖"别人用不一样模组"的场景。

**实施顺序建议**：A1 已在真机端到端验证通过（清缓存后数据原样恢复，见提交 6fafc19）；
A1.1 是在其之上**放宽白名单 + 加固护栏 + 加去抖**，可用同一套"指纹比对"验证法回归。
---

## 11. 最终范围决定（2026-10-06 用户拍板）：自动求准，手动求全

| | **自动镜像（A1）** | **手动导出/导入（A6）** |
| :--- | :--- | :--- |
| **范围** | 固定 3 键（`PvZ2_PlayerProperties` / `PvZ2_Settings` / `gp-next-settings`）∪ `gpn_` 前缀 | **所有 `localStorage` 键，一个不落**（含日志键；可勾选排除）|
| **定位** | 日常"不丢"：游戏存档 + 面板设置 + 模组计数 | **真·完整备份**：能搬走、能回滚、能挺过卸载 |
| **频率代价** | 每次 `setItem` 一次跨端写（有去抖）⇒ 所以**要窄** | 低频、用户主动 ⇒ 所以**要全** |
| **要不要改代码** | **不改**（保持现状，已真机端到端验证 6fafc19）| 待实现 |

**为什么自动不扩到"全部键"**（原 A1.1 被否的理由）：
1. 自动那条路每次存档都要跨端写一次；镜像缓存、临时标志等垃圾键只会**徒增 I/O 与噪音**；
2. 完整性由**手动导出**兜底 ⇒ 自动侧没必要承担这个成本；
3. 自动侧一旦放宽，还会把"垃圾键的旧值"在启动时**填回**页面，语义上更脏。

**用户原始表述（存档）**："手动的话就应该导出所有的键，而一般自动的话就一般只要把存档搞好之类的就可以了。
自动不需要导出那么多东西。"

**对"别人用不一样模组"的处理**：
- 自动侧只覆盖**已知命名约定**（`gpn_`）与**游戏本体键**；
- 若某个模组用了别的键名，**自动不保证**，但用户随时可以**手动导出**拿到**全部键**（含该模组的数据），
  需要时再**手动导入**回来 ⇒ 这是"手动求全"存在的意义。
---

## 12. A6 改动地图（实施定位）：自动与手动是"两条入口"，不靠条件分支

### 12.1 改哪些文件

| 文件 | 改动 | 量级 |
| :--- | :--- | :--- |
| `components/SettingsPanel.ets` | 新增「数据备份」一节 + 导出/导入两个按钮 | ~40 行 |
| `services/StorageBackup.ets`（**新文件**）| 打包成 JSON、落盘、读回 + 校验、导入前自动备份 | ~150 行 |
| `common/FilePickerHelper.ets` | ✅ **已具备**（`selectSavePath()` 与第二个 select 方法）| **0 行** |
| `pages/Index.ets` | 新增 2 个给页面调用的 `public` 方法（收集 / 应用）+ 注册进 JavaScriptProxy 方法表 | ~20 行 |
| `resources/rawfile/touchPatch.js` | ⭐ **只加两个小函数**（收集器 / 应用器），挂在 `window` 上 | **~20 行** |

**为什么必须动 touchPatch**：只有**页面**能读 `localStorage` —— 原生侧读不到
（官方 `WebStorage` 只能查用量与删除，见 §9.6）⇒ 收集与写回都必须在页面里做。

### 12.2 自动与手动怎么分开：**入口不同，不需要加条件**

| | 自动（A1）| 手动（A6）|
| :--- | :--- | :--- |
| 谁发起 | 页面 **`setItem` 钩子自动**触发 | **用户点按钮** |
| 路径 | `localStorage.setItem` 被覆写 ⇒ 白名单判定 ⇒ `saveToNative` | 按钮 ⇒ 原生 ⇒ **主动调用**页面函数 |
| 是否互相干扰 | **不干扰**（各走各的）| |

⇒ touchPatch 里新增的只是两个挂在 `window` 上的函数，**没有任何 `if (手动/自动)` 判断**：

```js
// A6：供原生侧调用的手动导出/导入（与 A1 的自动镜像互不干扰）
window.__pvzStorageExport = function () {
    var out = {};
    for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        out[k] = localStorage.getItem(k);      // 全收，一个不落（符合"手动求全"）
    }
    return JSON.stringify(out);
};
window.__pvzStorageApply = function (json) {
    var obj = JSON.parse(json), n = 0;
    for (var k in obj) {
        if (Object.prototype.hasOwnProperty.call(obj, k) && typeof obj[k] === 'string') {
            localStorage.setItem(k, obj[k]);   // 只覆盖、从不删除
            n++;
        }
    }
    return n;
};
```

### 12.3 唯一的一处交汇（而且正是想要的）

手动**导入**时写回用的是 `localStorage.setItem` ⇒ **会自动触发 A1 的钩子** ⇒ **镜像同步更新**。
这正是需要的：否则导入成功后一清缓存，又会被回填成**导入前**的旧值。

⚠️ **但要如实说明边界**：能被镜像更新的只有 **A1 范围内的键**（固定 3 键 ∪ `gpn_`）。
手动导入一个**非 `gpn_` 前缀**的模组数据，**这次能用，但下次清缓存仍会丢** ——
这是"自动求准、手动求全"设计的必然结果（§11）。要长期保住它，只能不清缓存，或把它加进自动白名单。

### 12.4 桥怎么走

| 方向 | 方式 | 原因 |
| :--- | :--- | :--- |
| 页面 → 原生（导出）| `runJavaScript` / `runJavaScriptExt` | 结果只有一份 JSON（约 330KB）；注意官方说明：**异步、必须 UI 线程**，且"执行失败或无返回值时返回 null"，必须把 null 当失败处理（§9.6）|
| 原生 → 页面（导入）| **消息端口**（`createWebMessagePorts` + `postMessage`，端口支持 `ArrayBuffer \| string`）| 不能把 ~330KB 的 JSON 拼进脚本文本（转义风险 + 长度风险）|

### 12.5 实施顺序（建议）

1. **前置验证**：先用 `FilePickerHelper.selectSavePath()` 选位置并写一个小文件、再读回来
   —— 同时覆盖验收清单里"下载 mod"那条**未验证项**；
2. **导出**（页面收集 → 原生落盘 → Toast 提示体积与文件名）；
3. **导入**（选文件 → 校验 → 自动备份 → 消息端口写回 → 提示重启生效）。
   回归验证用 §9.5 的 5 步，其中"卸载重装后仍能导入找回"是 A6 独有的价值。

**A1 的代码一行不改**（`setItem` 钩子保持现状，已真机端到端验证）。
---

## 13. 实测对比：A6 导出 vs 游戏原生存档（2026-10-06）

对比两份真实文件：`pvzge-localstorage-20261006-1430.json`（本壳层 A6 导出，176.3KB）
与 `Fish(v0.15.0).json`（游戏/GP-Next 自己的存档导出，152.6KB）。

| | **A6 导出**（我们的）| **游戏原生存档**（GP-Next 的）|
| :--- | :--- | :--- |
| 本质 | **localStorage 全量快照**（"容器"）| **游戏存档本体**（"容器里的那件东西"）|
| 顶层结构 | `{format, version, exportedAt, origin, app, entries}` | 存档字段直接铺开：`name/gem/coin/plantProps/worldProps/levelProps/zombieProps/…` |
| 覆盖范围 | **22 个键**（游戏存档 + 设置 + **19 个模组键**）| **只有存档**（1 个对象）+ 模组字段 `gpn_killlevel_save_id` |
| 存档形态 | `"PvZ2_PlayerProperties"` = **`[{…}]`**（**数组**包着）| **解开数组**，就是 `{…}` 本体 |
| 时效 | 导出瞬间的实时值（`coin=890520`）| 较旧（`coin=890050`，`time=2026-10-04 19:43:57`）|
| 能否被 A6 导入 | ✅ 就是本格式 | ❌ **不能**（无 `format`/`entries`）⇒ 明确报错且不改动数据 |
| 生成者 | 设置面板「导出全部数据」| 游戏/GP-Next 自己的存档导出 |

### 13.1 三条实测发现（值得记）

1. **A1 的覆盖面会自己长大**：设备上 Preferences 现有 **23 个键**，其中 **22 个**落在 A1 范围内
   （**19 个 `gpn_*`**）。模组同时写**"全局"与"按存档"两套**键
   （如 `gpn_killlevel_plantkills_v3` 与 `gpn_killlevel_plantkills_v3.<存档后缀>` 并存），
   先前只观察到 8 个 ⇒ **前缀规则自动把它们全收了**（这正是它存在的意义）。
2. **"175KB"这类数字曾被 XML 转义放大**：Preferences 的 XML 把 `"` 写成 `&quot;`（6 字符），
   于是 `PvZ2_PlayerProperties` 在 XML 里显示 **175,234** 字符，而**真实 JSON 只有 104,634 字符**。
   ⇒ 引用体积时应以导出文件里的原始长度为准。
3. **游戏原生存档是 `{…}`，而 localStorage 里存的是 `[{…}]`**（多一层数组包装）。
   另外游戏写的 `exportTime` 字段**不可信**（该文件里是 2026-03-17，而实际导出时间是 10 月）
   ⇒ 判断新旧请看 `time` 或 `coin/gem` 这类活动字段。

### 13.2 提案 A6.1：兼容导入"游戏原生存档"

由于差异 3 只是**一层数组包装**，可以加一条兼容路径：

- 若文件**没有** `format` 字段，但**看起来像存档**（含 `name` + `plantProps` + `worldProps` 等标志字段）
  ⇒ 把它**包成数组**后写入 `PvZ2_PlayerProperties`（即 `'[' + text + ']'`）；
- **必须先校验**：是合法 JSON 对象、含若干必需字段、体积在限内；否则明确报错且不改动任何数据；
- 仍然保留"**导入前自动备份**"与"二次确认"，并提示"重启后生效"；
- 风险：存档结构随游戏版本变化 ⇒ 只做**形状校验**，不做字段级迁移；宁可拒绝也不要写坏。

### 13.3 与 A1 的关系（再次确认设计）

本次对比显示：**这台设备的 localStorage 恰好 100% 落在 A1 范围内**（因为模组用的就是 `gpn_` 约定）。
但"别人用不一样模组"时（§10/§11）自动侧不保证 ⇒ **手动导出仍是唯一能拿到"全部键"的路径**，
而且它额外附带了"**能搬走、能回滚、能挺过卸载**"这一点（游戏原生导出做不到搬走整个 localStorage）。
---

## 14. A6.2 导入方式重做：暂存 → 立即重载 → document-start 同步应用（2026-10-06 用户指出）

### 14.1 原设计为什么错

原实现是"**在游戏运行中写 localStorage，然后提示重启**"。用户指出：注入必须在**游戏加载之前**。
进一步分析后确认这不仅是"脆弱"，而是**基本必然失效**：

- 实测证据：两次快照之间游戏存档的 `time` 变了、`coin` 从 890050 变成 890520
  ⇒ **游戏会把内存里的存档定期写回**；切后台/退出时通常还会再写一次。
- 后果：运行中导入的数据**最迟在下一次自动回写时被覆盖**；连"导入后立刻重启"也救不了
  —— 重启过程中游戏会先把自己的旧存档写回去。

### 14.2 新流程（零间隙）

```
① 面板点导入 → 校验通过 → 把 entries JSON 写进**原生暂存位**（Preferences 键 __a6_pending_import）
   ↑ 这一步完全不碰页面
② 立刻把该 JSON **内联进注入脚本**（变成不同的 @State 值）→ 等一帧 → webController.refresh()
③ document-start：注入脚本末尾同步调用 window.__pvzApplyImportSync(<内联 JSON>)
   ⇒ 发生在**负载任何代码之前**，游戏启动读到的就是导入后的数据
④ 应用成功即清掉暂存位（写空串）
```

关键点：**不是"运行中写 + 等下一次加载"，而是"下一次加载的最开头同步写"** —— 竞态被消除而非减小。

### 14.3 实现要点（含两个坑）

| 点 | 说明 |
| :--- | :--- |
| **暂存位键名** | `__a6_pending_import`：既不是固定键、也不是 `gpn_` 前缀 ⇒ **不在 A1 白名单内**，不会被镜像/回填 |
| **为什么用 `@State injectedScript`** | 注入只能走组件属性 `javaScriptOnDocumentStart`（SDK 里**没有** `runJavaScriptOnDocumentStart`）⇒ 只有状态变化才会让 Web 组件重新取该属性 |
| ⚠️ **坑 1** | reload 里若写 `this.injectedScript = this.injectedScript`（同值）⇒ `@State` 不触发 ⇒ 注入脚本里没有新数据 ⇒ **导入静默失效**。必须用"不含导入数据的基底 + 新 JSON"拼出**不同**的值 |
| ⚠️ **坑 2** | 清暂存位刻意**不新增代理方法**：复用 `saveToNative('__a6_pending_import', '')` —— `PreferenceStore.save` 不做键名白名单校验（只限值大小），空串在读取侧即"无待应用数据" |
| **失败兜底** | 若"等一帧 + refresh"在真机上仍不生效（属性时序），退路是改用 `context.terminateSelf()` 重启应用：进程重启一定会重新执行 `aboutToAppear` 并在拼脚本时读到暂存位 |

### 14.4 待验证（真机）

1. 导出全部数据 → 确认日志 `[A6] 写入成功（第 1 种路径形式）`；
2. 导入该文件 → 日志应出现 `[A6] 导入数据已暂存` + `[A6] 注入脚本已更新（内联 N 字符导入数据）`，
   随后页面自动重载；
3. 重载后确认数据确实**生效**（可用一份**改动过的**备份做对照：改掉某个计数值再导入，看游戏里是否变化）；
4. 回归：游戏能正常启动、A1 的自动镜像不受影响。
---

## 15. A6.2 的一个真实回归：`aboutToAppear` 的 await 位置（2026-10-06）

**现象**：偶发启动失败，负载报
`[Cocos Bootstrap] failed to start game StartupFailure: Cocos startup failed at beforeEngineImport:
[gp-next-shim] 原生桥尚未就绪: plugin:fs|exists`，随后触发负载自带的 `startup-recovery`
（日志里能看到它连试 4 次）。

**根因**：A6.2 为了"在拼注入脚本之前读导入暂存位"，把两个 `await` 插到了**创建 `gpNextBridge` 之前**。
`aboutToAppear` 是 async 的，框架**不等它** —— 只保证"第一个 `await` 之前的同步部分"先于
`build()` / `onControllerAttached` 完成。于是 `onControllerAttached` 先触发时 `gpNextBridge` 还是
`undefined` ⇒ `registerGpNextBridge()` 直接跳过注册 ⇒ 页面 document-start 调 `bridge` 失败 ⇒ 负载启动失败。
表现为**偶发**（等待时长与 Web 组件挂载存在竞态）。

**修法**：把 `this.gpNextBridge = new GpNextBridge(...)` 挪到 `filePickerHelper` 之后、
**本函数第一个 `await` 之前**；读暂存位的 `await` 保持在拼注入脚本之前（那是它必须的位置）。
自检：`建桥行 < 第一个真正的 await 行`（比较时必须剔除注释行）。

**验证**（真机，`hilog -T JSAPP` 流式对比）：
- 修前：连续多次启动都是 `GP-Next 原生桥未初始化，跳过注册` + `StartupFailure`（含负载自动重试 4 次）
- 修后：**5 次启动全部 `GP-Next 原生桥已注册`，零 `StartupFailure`**

**教训（已同步到 AGENTS.md）**：凡是"必须在 `build()`/`onControllerAttached` 之前就绪"的对象，
一律放在 `aboutToAppear` 的第一个 `await` 之前；竞态类问题**必须多次启动**才算验证。
---

## 16. 启动确定性闸门：脚本就绪前不创建 Web（2026-10-06）

§15 修掉了"建桥晚于 `onControllerAttached`"的竞态；但还剩一个**同类但更隐蔽**的时序窗口：

- 注入脚本的拼接发生在 `aboutToAppear` 的 **await 之后**，而它的初值只有 `GPNEXT_SHIM`
  ⇒ 若 Web 在此窗口内已经开始加载文档，注入的可能只是 shim（缺 touchPatch / 缺 A6 内联数据）。
- 目前靠"await 比文档真正加载更快"**容忍**着 —— 实测成立（A6 内联导入确实生效），
  但这是时序运气，不是保证。

**改法（启动确定性闸门）**：新增 `@State injectedScriptReady`，`build()` 里
`if (this.injectedScriptReady) { Web(...) } else { 纯黑加载态 }`。

- 三个放行点：脚本拼接成功 / `touchPatch.js` 内容为空 / 读文件抛异常
  —— **异常路径也必须放行**，否则页面会永远停在加载态（这是闸门最大的风险点）。
- 打开闸门后才创建 Web ⇒ `onControllerAttached` 必然发生在"桥已建 + 脚本已拼"之后
  ⇒ 桥与脚本两件事都变成**确定性**的。

**与 A6 的关系**：A6 导入时会把新脚本（内联了导入 JSON）写进 `@State injectedScript` 再 `refresh()`；
闸门不参与刷新路径（组件已存在），因此不影响导入。实测：带闸门的构建上完整走通了一次导入。

**验证（真机）**：
- **5 次连续启动**全部 `GP-Next 原生桥已注册`、**零 `StartupFailure`**，
  且每次都出现">8MB 纹理被跳过"三连（= 引擎确实在拉资源 ⇒ 游戏真的起来了）
- 带闸门构建上 A6 导入一次成功（读取 → 暂存 → 内联 → 重载）

**如实说明**：闸门是**健壮性改进**，不是某个已观测故障的修复
（§15 的桥顺序修复之后启动本就已稳定）；它的价值是**消除那个"脚本可能还只有 shim"的窗口**。
