# 拦截机制选型评估：`onInterceptRequest` vs `WebSchemeHandler`

> 日期：2026-10-07 ｜ 触发：性能审查报告 §5 把「中期迁 `WebSchemeHandler` + fd 分块流式」列为 GPnext 的 **P3**
> 结论：**不迁**。理由全部来自官方文档原文，不是偏好。

## 一句话结论

我们的场景（**把游戏负载作为本地静态资源返回**）正是官方把 `onInterceptRequest` 列为推荐用法的那一类，
而且 ArkTS 版 `WebSchemeHandler` 传响应体**只有 `ArrayBuffer` 一条路** ⇒ 迁过去会**强制每个请求都整文件进 ArkTS 堆**，
等于把我们已经修掉的病重新装回去。

## 官方原文（`Web组件拦截能力的使用.md`）

| 位置 | 原文 | 说明 |
| :--- | :--- | :--- |
| `:153` | onInterceptRequest 核心用法之一：「**将频繁使用的静态资源缓存至本地**，在访问这些资源时，返回本地响应，用于提升页面的加载速度和响应性能」 | ⭐ **这就是我们**；官方把它归在 onInterceptRequest 名下 |
| `:158` | 「onInterceptRequest 支持通过**文件句柄、Resource 资源**、ByteBuffer 或 String 的方式替换请求内容，要求开发者一次性提供完整的请求内容。… 相较于基于 WebSchemeHandler 的拦截方案，**本方案的实现更加轻量**」 | 官方明确说 **onInterceptRequest 更轻** |
| `:172` | 「（WebSchemeHandler）…还提供了更灵活的流式处理能力…在需要拦截网络请求，**获取更多请求内容**或进行流式处理等复杂业务场景下，建议采用本方案」 | SchemeHandler 的适用前提是"要请求内容/要流式" |

## 迁过去会付出的代价（这条是决定性的）

ArkTS 版 `WebSchemeHandler` 给响应体只有一种接口：

```
didReceiveResponseBody(data: ArrayBuffer): void          // Class (WebResourceHandler).md:55，API 12+
```

⇒ **只接受 `ArrayBuffer`**：没有 `Resource`、没有文件句柄 ⇒ 要返回一个 rawfile，必须**先在 ArkTS 侧把整个文件读成字节**。
而 `WebSchemeHandlerResponse`（`:75-233`）只提供 url / netErrorCode / status / statusText / mimeType / encoding /
`setHeaderByName` —— **没有任何承载响应体的方法**。

**对比现状**：我们现在是 `setResponseData($rawfile(path))`（`Resource`）⇒ 实测 native 堆 **46,783 kB**（见
`RESOURCE_CACHE_AB.md` 的落地复核）。迁到 SchemeHandler 就会退回"每个请求一次整文件 ArkTS 堆分配"。

## 报告那句"官方依据"为什么不成立

报告 §5 的 P3 依据写的是「官方：此类场景需改用 SchemeHandler」。在官方介绍三种拦截机制的同一页里**查不到**这句话；
原文对 SchemeHandler 的"建议采用"是**带前提的**（要请求体 / 要流式），而我们的场景恰恰被官方归到 onInterceptRequest。
⇒ 属**转述失真**，不能作为迁移依据。

## 那"文件句柄"这条路呢（不用换机制）

`Class (WebResourceResponse).md:152` 官方对参数 `data` 的说明：

> 「`string` 表示 HTML 格式的字符串。**`number` 表示文件句柄，此句柄由系统的 Web 组件负责关闭**。
> `Resource` 表示应用 rawfile 目录下文件资源。`ArrayBuffer` 表示资源的原始二进制数据。」

⇒ 同一机制内还存在 **`setResponseData(fd)`**：由我们 `fs.openSync` 打开 rawfile、把 fd 交出去，**内核自己读**，
且**系统负责关闭句柄**（不会漏 fd）。它比 `Resource` 更"通用"（`Resource` 明确限于"应用 rawfile 目录"）。

**当前不需要**（`Resource` 路径实测没有内存/耗时问题），但它是**唯一值得保留的备选**：
如果将来出现 `Resource` 表达不了的资源（比如负载之外的文件、或需要 Range 分段），先试 fd，而不是换机制。

## 何时才该重新考虑 SchemeHandler

只有同时满足下面任一条时才值得重新评估（且届时应走 **NDK** 版而不是 ArkTS 版，因为只有 NDK 侧才能拿 fd 做真正的流式）：

1. 需要读**请求体**（POST / PUT），例如负载开始依赖表单上传；
2. 出现**单文件大到不能一次占内存**的资源（当前负载最大 17.38 MB，整包 1283.8 MB 由内核按需读，无此问题）；
3. 官方把 `onInterceptRequest` 标记废弃（目前是并列推荐且注明"更轻量"）。

## 相关

- `docs/perf/RESOURCE_CACHE_AB.md`（缓存移除与真机复核数据）
- `.clean-staging/gpnext-diag/ACTION-LIST-STATUS.md`（报告 §5 全清单的逐条状态）
