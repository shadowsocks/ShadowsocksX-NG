# ShadowsocksX-NG

> 🚧 重新实现进行中 —— 本仓库正在使用现代技术栈重写 ShadowsocksX-NG macOS 客户端。

新实现位于 [`ShadowsocksX-NG2/`](ShadowsocksX-NG2/README.md)，面向 macOS 15+ / Apple Silicon（arm64）。外部二进制使用上游发布产物，不再通过 git 子模块在仓库内构建。

## 开发入口

- [首次构建与常用命令](ShadowsocksX-NG2/README.md#开发构建与测试)
- [开发指南](docs/development.md)：统一验证、测试证据、代码风格工具与 Git hooks。
- [工程与专题文档](ShadowsocksX-NG2/README.md#文档导航)：源码布局、供应链与签名、规则快照、配置说明。
- [术语表](GLOSSARY.md)与[架构决策记录（ADR）](docs/adr/)；文档语言约定见[开发指南](docs/development.md#领域文档语言)。

## 旧版归档

旧版工程源码已从本仓库移除，归档在 [shadowsocks/ShadowsocksX-NG 的 legacy-v1 分支](https://github.com/shadowsocks/ShadowsocksX-NG/tree/legacy-v1)，仅供参考，不保证可构建。旧版功能说明与使用文档见 [legacy-v1 的 README](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/README.md)。
