# 构建与部署

## 构建配置

### 基本配置 (`build-profile.json5`)

```json5
{
  "app": {
    "signingConfigs": [
      { "name": "debug", "type": "HarmonyOS", "material": { "storeFile": "..." } }
    ],
    "products": [
      { "name": "default", "signingConfig": "debug", "compatibleSdkVersion": "6.0.0(20)", "targetSdkVersion": "6.0.2(21)" }
    ],
    "buildModeSet": [{ "name": "debug" }, { "name": "release" }]
  },
  "modules": [{ "name": "entry", "srcPath": "./entry" }]
}
```

### 模块构建配置 (`entry/build-profile.json5`)

```json5
{
  "apiType": "stageMode",
  "buildOption": {
    "arkOptions": {
      "obfuscation": { "ruleOptions": { "enable": false, "files": ["./obfuscation-rules.txt"] } }
    }
  },
  "targets": [{ "name": "default" }, { "name": "ohosTest" }]
}
```

> 当前混淆配置的 `enable` 为 `false`。发布正式版时可开启并完善 `obfuscation-rules.txt`。

## 签名配置

### Debug 签名

项目使用 `build-profile.json5` 中配置的 `.p12` 调试证书签名：

- **密钥算法**: SHA256withECDSA
- **Profile 类型**: debug

### Release 签名（正式发布）

正式发布前需在 `build-profile.json5` 中新增 release 签名配置：

```json5
{
  "name": "release",
  "type": "HarmonyOS",
  "material": {
    "storeFile": "path/to/release.p12",
    "storePassword": "********",
    "keyAlias": "releaseKey",
    "keyPassword": "********",
    "profile": "path/to/release.p7b",
    "signAlg": "SHA256withECDSA"
  }
}
```

然后将 `products` 中的 `signingConfig` 改为 `"release"`。

## 应用版本信息

### 版本号定义 (`AppScope/app.json5`)

| 字段 | 值 | 说明 |
|------|---|------|
| `bundleName` | `com.Pvz2.gardendless` | 应用包名（唯一标识） |
| `versionCode` | `1000001` | 版本号（整数递增） |
| `versionName` | `0.9.3` | 用户可见版本号 |

### 更新版本步骤

1. 修改 `AppScope/app.json5` 中的 `versionCode` 和 `versionName`
2. 如需同时更新 `module.json5` 中的设备类型或权限，同步修改
3. 重新构建并签名

## 构建产物

构建后在以下目录生成产物：

```
entry/build/default/outputs/default/
├── entry-default-signed.hap       # 签名后的 HAP
└── entry-default-unsigned.hap     # 未签名的 HAP
```

## 部署方式

### 方式一：DevEco Studio 直接运行

1. 连接设备（USB 或 Wi-Fi）
2. 选择 `Run → Run 'entry'`
3. 等待编译签名部署完成

### 方式二：手动安装 HAP

```bash
hdc install entry/build/default/outputs/default/entry-default-signed.hap
```

需要提前安装 [hdc (HarmonyOS Device Connector)](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hdc)。

### 方式三：AppGallery 发布

1. 在 AppGallery Connect 创建应用（包名 `com.Pvz2.gardendless`）
2. 上传 release 签名的 HAP
3. 填写应用信息、截图、隐私政策等
4. 提交审核

## 模块结构

| 模块 | 类型 | 说明 |
|------|------|------|
| `entry` | entry | 主模块，包含所有页面和资源 |
| `entry_test` | feature | 测试模块（ohosTest） |

## 代码检查

项目配置了 `code-linter.json5`，启用以下检查规则：

- `@performance/recommended` — 性能最佳实践
- `@typescript-eslint/recommended` — TypeScript 规范
- 安全规则（加密算法相关）：禁止不安全 AES/Hash/DH/DSA/ECDSA/RSA/3DES 算法

运行代码检查：
```
在 DevEco Studio 中右键项目 → Code Linter → Run Linting
```

## 依赖管理

| 依赖 | 版本 | 用途 |
|------|------|------|
| `@ohos/hypium` | 1.0.25 | 测试框架（devDependency） |
| `@ohos/hamock` | 1.0.0 | Mock 工具（devDependency） |

运行测试：
```
在 DevEco Studio 中右键 test 目录 → Run 'tests'
```

## 负载目录约定与更新流程

游戏负载（Cocos 构建产物）**整体**放在 `entry/src/main/resources/rawfile/game/` 下，`rawfile/` 根目录只留壳层自己提供的文件。

```
entry/src/main/resources/rawfile/
├── touchPatch.js          # 壳层补丁（纳入 Git）；由壳层读入后在 document-start 注入页面
└── game/                  # 游戏负载（不纳入 Git）—— 更新时整目录替换
    ├── index.html         # 负载自带的入口页（原样保留，不要手改）
    ├── application.js / index.js / style.css / tmpPatch.js …
    └── assets/  cocos-js/  src/
```

目录名由 `Index.ets` 顶部的 `PAYLOAD_DIR` 常量定义（默认 `'game/'`），`.gitignore` 也只忽略这一个目录。
**更新负载只需三步**：

1. 删除旧的 `rawfile/game/`；
2. 把新负载（解压 HAP 的 `rawfile/`，或从 [pvzge.com](https://pvzge.com/) 获取）**整体**放入 `rawfile/game/`；
3. 重新构建。

不需要再改 `index.html`，也不需要重新注入 `touchPatch.js` —— 这正是本约定的目的。

### 三点必须知道的行为

1. **负载自带的 `index.html` 可能用根绝对路径**引用自己的模块（如 `/assets/index-<hash>.js`，哈希随版本变），
   所以拦截器会把 `rawfile/` 根之外的请求统一补上 `PAYLOAD_DIR` 前缀（见 `Index.ets` 的 `onInterceptRequest`）。
   这也是负载目录名可以自由更改、只需同步 `PAYLOAD_DIR` 的原因。
2. **不存在的文件返回的是 `200 + 空体`，不是 404** —— 因为拦截器用 `$rawfile()` 组装响应，文件缺失不会抛错。
   因此"换错/换漏目录"的表现是**静默黑屏**而不是报错。为此壳层在启动时自检 `game/index.html` 与
   `game/src/settings.json`，缺失时在顶部状态栏显示「负载缺失: …」。
3. **`rawfile` 在构建时被打进 HAP**：只替换本地目录不会影响已安装的应用，必须重新构建并安装。

## 提交前隐私守卫

仓库带一个提交前钩子（`.githooks/pre-commit`）与同名 CI（`.github/workflows/privacy-guard.yml`），
用于阻止隐私信息进入提交。启用（每份克隆执行一次）：

```bash
git config core.hooksPath .githooks
```

它检查四类问题，命中即在本地**拒绝提交**，CI 上同样拦截：

| 类别 | 说明 |
|:---|:---|
| 签名明文口令 | 签名配置里的口令字段若出现非掩码值；以星号开头的掩码写法（文档示例常用）视为安全 |
| 本机绝对路径 | Windows 盘符形式的用户目录、MSYS/Git-Bash 形式的用户目录——会暴露本机账号名 |
| 设备标识 | 设备 SN 的形态串、`sn` / 序列号字段、MAC 地址、非 noreply 邮箱 |
| 不该入库的文件 | 签名材料（p12 / p7b / cer / csr / jks / keystore）、HAP / APK / zip、数据库、签名配置文件 |

手工扫描某个区间（CI 用的就是这条）：

```bash
PRIVACY_RANGE=<from>..<to> sh .githooks/pre-commit
```

输出**只给「文件:行号 + 命中规则」，刻意不打印命中内容**——避免在 CI 日志里二次泄露。
确认无风险时可临时跳过（会在输出里留记录）：

```bash
ALLOW_PRIVACY=1 git commit -m "…"
```

> 钩子只能防**新增**，历史里已有的旧内容不会因此消失；如需处理已有历史，
> 需权衡历史重写（会改变所有提交哈希、且 GitHub 上旧对象短期内仍可按哈希访问）
> 与签名材料轮换（会改变签名，导致已安装用户无法覆盖升级）两条路。

## 常见构建问题

### 签名失败

- 检查 `build-profile.json5` 中 `storeFile` 路径是否正确
- 确认 `.p12` 证书有效期未过期
- Debug 证书需在 DevEco Studio 中重新生成

### 资源找不到

- 确保负载位于 `entry/src/main/resources/rawfile/game/` 下（见上文「负载目录约定」）
- 检查文件路径大小写（Linux 文件系统区分大小写）

### WebView 白屏

- 确认 `onInterceptRequest` 正确拦截 `https://cocos.local/*` 请求
- 检查 `rawfile/game/index.html` 及其引用资源是否完整；壳层启动自检若提示「负载缺失」即为此因
- 注意：缺失文件会被拦截器返回成 **200 + 空体**（不是 404），所以白屏时不要只看状态码
