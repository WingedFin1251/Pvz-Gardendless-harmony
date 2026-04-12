# PvZ2 Gardendless for HarmonyOS
## 项目简介
本项目基于 [pvzge.com](https://pvzge.com/) 原版 **PvZ2 Gardendless（植物大战僵尸2 无花园重制版）**，完整迁移并深度适配 **HarmonyOS NEXT / OpenHarmony** 平台，采用纯鸿蒙原生架构开发，保留原版核心玩法与工具链，为鸿蒙设备提供流畅、完整的游戏体验。

- 非EA/PopCap官方产品，为爱好者社群开源移植项目
- 一次开发，多端部署：支持鸿蒙手机、平板等设备
- 原生性能优化：Cocos Creator 鸿蒙适配 + ArkUI 原生界面

## 安装方法

您可以使用[小白调试助手Auto-installer](https://github.com/likuai2010/auto-installer)进行安装。
> [!NOTE]
> 在HarmonyOS NEXT使用自签名的方式进行侧载的App默认只有14天的有效期，进行[开发者实名认证](https://developer.huawei.com/consumer/cn/verified/enrollment)后即可将有效期提升至180天。

## 快速开始
### 环境准备
1. 安装 [DevEco Studio 5.0+](https://developer.harmonyos.com/cn/develop/deveco-studio)
2. 配置 HarmonyOS NEXT SDK（API 12+）
3. 安装 Cocos Creator 3.8.6+（鸿蒙发布支持）

### 构建运行
```bash
# 克隆仓库
git clone https://github.com/你的用户名/PvZ2-Gardendless-HarmonyOS.git
cd PvZ2-Gardendless-HarmonyOS

# 使用DevEco Studio打开工程
# 连接鸿蒙设备或启动模拟器
# 点击“运行”生成HAP并安装
```

### 目录说明
```
entry/
├── src/main/
│   ├── ets/
│   │   ├── entryability/
│   │   │   └── EntryAbility.ets                 # 主Ability（全屏、横屏配置）
│   │   ├── pages/
│   │   │   └── Index.ets                         # 主页（Web组件、桥接、拦截器）
│   │   └── entrybackupability/
│   │       └── EntryBackupAbility.ets             # 备份扩展能力（可选）
│   ├── resources/
│   │   ├── base/
│   │   │   ├── element/
│   │   │   │   └── string.json                    # 模块级字符串（如ability名称）
│   │   │   ├── media/
│   │   │   │   ├── foreground.png                 # 图标前景
│   │   │   │   ├── background.png                 # 图标背景
│   │   │   │   └── layered_image.json             # 分层图标配置文件
│   │   │   └── profile/
│   │   │       └── main_pages.json                 # 页面路由配置
│   │   └── rawfile/                                 # 游戏静态资源
│   │       ├── index.html                           # 游戏入口
│   │       ├── style.css                            # 样式
│   │       ├── src/                                  # 核心JS文件夹
│   │       │   ├── polyfills.bundle.js
│   │       │   ├── system.bundle.js
│   │       │   └── import-map.json
│   │       ├── cocos-js/                             # Cocos引擎文件
│   │       │   └── ... (多个js/wasm文件)
│   │       ├── assets/                               # 游戏资源
│   │       │   └── ... (图片、音频等)
│   │       ├── cloudSaver.js                         # 云存档模块
│   │       ├── tmpPatch.js                            # 临时补丁（可能未使用）
│   │       └── touchpatch.js                          # 触摸补丁
│   └── module.json5                                   # 模块配置（设备类型、权限、横屏等）
└── ...
```


## 贡献指南
欢迎提交 Issue、PR 参与共建：
1. Fork 本仓库
2. 创建功能分支（feature/xxx 或 fix/xxx）
3. 遵循 ArkTS 代码规范与鸿蒙工程规范
4. 提交 PR 并附清晰说明
5. 等待评审与合并

## 许可证
- 本移植项目：**MIT License**
- 原版 PvZ2 Gardendless：遵循 [pvzge.com](https://pvzge.com/) 社群授权协议
- 游戏素材版权归原作者所有，本项目仅用于学习与交流

## 免责声明
本项目为非官方开源移植作品，仅供学习与技术交流使用，严禁用于商业用途。使用本项目需遵守当地法律法规与原版社群协议，因使用产生的任何风险由使用者自行承担。

---

🌟 如果本项目对你有帮助，欢迎 Star、Fork、分享！
📧 联系与反馈：GitHub Issues 或 项目讨论区
