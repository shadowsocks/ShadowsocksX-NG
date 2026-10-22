# ShadowsocksX-NG2

[English](README.md) | 简体中文

ShadowsocksX-NG 的现代化重写版本，面向 macOS 15+ / Apple Silicon（arm64）。新工程的源码与构建配置位于本目录，旧版归档见[仓库首页](../README.zh.md)。

依赖的 `sslocal`、`v2ray-plugin` 与 Cloak `ck-client` 使用上游发布的可执行文件。HTTP 入站由 shadowsocks-rust 直接提供，不再携带 Legacy Privoxy。

## 开发、构建与测试

准备 Xcode/Swift 工具链、[Task](https://taskfile.dev/)、[XcodeGen](https://github.com/yonaskolb/XcodeGen) 和 SwiftLint；工具基线与安装说明见[开发指南](../docs/development.zh.md#代码风格工具)。

从本目录执行首次构建，先获取外部二进制，再生成工程：

```bash
Scripts/fetch-external-binaries.sh
task gen:prj
task build
```

Debug 默认使用 ad-hoc 签名，无需证书；Developer ID 配置与发布门槛见[签名与分发](../docs/distribution.zh.md)。工程配置以 `project.yml` 为准，生成的 `.xcodeproj` 不入库。

从仓库根目录运行统一验证：

```bash
task --exit-code --taskfile ShadowsocksX-NG2/Taskfile.dist.yml validate
# 按指定顺序只运行所需关卡：
task --exit-code --taskfile ShadowsocksX-NG2/Taskfile.dist.yml validate -- lint test
```

默认顺序为 `lint → test → test:smoke → build`，失败即停止，日志与结果保存在 `ShadowsocksX-NG2/.build/validation/`。在本目录内可直接运行 `task --exit-code validate`。单项任务、证据读取与测试边界见[开发指南](../docs/development.zh.md)。

## 文档导航

| 文档 | 内容 |
| --- | --- |
| [开发、构建与测试](../docs/development.zh.md) | 验证入口与产物、单项任务、代码风格工具、Git hooks、文档语言 |
| [工程结构与源码搜索](../docs/project-structure.zh.md) | 源码分层、测试目录、跨 target 文件约束、搜索方法 |
| [外部二进制、签名与分发](../docs/distribution.zh.md) | 供应链校验、Debug/Release 签名、发布门槛、依赖升级 |
| [内置规则快照](../docs/rule-snapshots.zh.md) | 来源、转换语义、维护脚本与离线检查 |
| [订阅、插件与监听配置](../docs/configuration.zh.md) | 订阅资料、用户插件、Cloak、本地与局域网监听、配置恢复 |
| [服务器库加密格式](../docs/server-library-encryption-format.zh.md) | 加密文件格式与外部解密约定（[English](../docs/server-library-encryption-format.md)） |

领域术语与已定设计见[术语表](../GLOSSARY.md)和[架构决策记录](../docs/adr/)。`docs/design/` 与 `docs/research/` 为历史设计和研究记录，判断当前实现时以代码为准。
