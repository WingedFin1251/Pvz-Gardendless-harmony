# PvZ2 Gardendless for HarmonyOS
## 项目简介
本项目基于 [pvzge.com](https://pvzge.com/) 原版 **PvZ2 Gardendless（植物大战僵尸2 无花园重制版）**，完整迁移并深度适配 **HarmonyOS NEXT / OpenHarmony** 平台，采用纯鸿蒙原生架构开发，保留原版核心玩法与工具链，为鸿蒙设备提供流畅、完整的游戏体验。

- 非EA/PopCap官方产品，为爱好者社群开源移植项目
- 一次开发，多端部署：支持鸿蒙手机、平板等设备
- 原生性能优化：Cocos Creator 鸿蒙适配 + ArkUI 原生界面

## 核心特性
✅ **鸿蒙原生适配**：基于HarmonyOS NEXT Stage模型，纯血鸿蒙运行
✅ **完整功能保留**：游戏本体、在线图鉴、存档编辑器、MOD工具链
✅ **模块化架构**：游戏引擎层、工具层、UI层解耦，易于二次开发
✅ **开源可定制**：全源码开放，支持自定义植物/僵尸/关卡

## 技术栈
- 操作系统：HarmonyOS NEXT / OpenHarmony 5.0+
- 开发语言：ArkTS、TypeScript、C++
- UI框架：ArkUI（声明式）
- 游戏引擎：Cocos Creator 鸿蒙适配版
- 工程工具：DevEco Studio 5.0+、OHPM包管理

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
PvZ2-Gardendless-HarmonyOS/
├── AppScope/           # 应用全局配置
├── entry/              # 主Entry模块（HAP）
│   ├── src/main/
│   │   ├── ets/        # ArkTS 业务逻辑与UI
│   │   ├── cpp/        # Cocos 原生引擎与桥接
│   │   └── resources/  # 资源文件
├── pvzge-game/         # 移植后的游戏核心工程
├── docs/               # 适配文档、FAQ
└── README.md
```

## 功能模块
1. **游戏核心**：完整关卡、植物、僵尸、战斗系统
2. **在线图鉴**：植物/僵尸属性、ID、CodeName查询




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
