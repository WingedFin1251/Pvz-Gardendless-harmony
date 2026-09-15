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
| `bundleName` | `com.gardendless.gpnext` | 应用包名（唯一标识） |
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

1. 在 AppGallery Connect 创建应用（包名 `com.gardendless.gpnext`）
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

## 游戏资源（不纳入版本管理）

`entry/src/main/resources/rawfile/` 下的游戏负载来自第三方 Cocos 构建产物，**不纳入版本管理**，
仓库中只保留两个手写壳层文件：

| 保留跟踪 | 说明 |
|:---|:---|
| `index.html` | 壳层入口页 |
| `touchPatch.js` | 触摸 / GP-Next 面板补丁 |

其余内容已被 `.gitignore` 忽略，**需自行获取后放入该目录**；否则应用能编译通过，但运行时会白屏：

- `assets/` — Cocos 资源包（约 570 MB）
- `cocos-js/` — Cocos 引擎运行时
- `src/` — `settings.json` 等构建配置
- `application.js`、`index.js`、`style.css` — Cocos 构建产物

这些文件**不在本仓库的 git 历史中**（本仓库为独立重建的精简历史，不含游戏负载），
需自行从上游获取后放入该目录：

- 上游仓库：[WingedFin1251/Pvz-Gardendless-harmony](https://github.com/WingedFin1251/Pvz-Gardendless-harmony)
  （可从其 Release 下载 HAP，解压后取 `rawfile/`）
- 游戏本体：[pvzge.com](https://pvzge.com/)

> 注意：`.gitignore` 中的规则必须写成 `/entry/src/main/resources/rawfile/*` 加反选（`!`）。
> 若写成 `rawfile/**` 或直接忽略整个 `rawfile/` 目录，反选会失效——Git 不允许反选“父目录已被排除”的文件。

## 常见构建问题

### 签名失败

- 检查 `build-profile.json5` 中 `storeFile` 路径是否正确
- 确认 `.p12` 证书有效期未过期
- Debug 证书需在 DevEco Studio 中重新生成

### 资源找不到

- 确保 `rawfile` 资源在 `entry/src/main/resources/rawfile/` 下
- 检查文件路径大小写（Linux 文件系统区分大小写）
- 若缺少游戏负载，参见上文「游戏资源（不纳入版本管理）」

### WebView 白屏

- 确认 `onInterceptRequest` 正确拦截 `https://cocos.local/*` 请求
- 检查 `index.html` 及其引用资源是否完整存在于 `rawfile/` 中
