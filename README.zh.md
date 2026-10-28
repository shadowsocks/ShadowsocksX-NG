# ShadowsocksX-NG2

[English](README.md) | 简体中文

面向 Apple Silicon Mac 的原生 Shadowsocks 客户端。通过菜单栏管理服务器、订阅和代理规则，并为 Mac 应用提供 SOCKS5 与 HTTP 代理入口。

> 请从 [GitHub Releases](https://github.com/shadowsocks/ShadowsocksX-NG/releases) 下载最新的 ShadowsocksX-NG2 版本。发布页也会保留旧版 1.x。

## 项目状态

ShadowsocksX-NG 正在进行大规模重构。旧版已停止维护，ShadowsocksX-NG 2 仍在开发中。

我们会关闭旧版遗留的所有 Issue。v2 代码稳定并正式发布前，暂不接受新的 Issue 和 PR。

在此期间，欢迎到 [Discussions](https://github.com/shadowsocks/ShadowsocksX-NG/discussions) 提问、报告 Bug 或分享反馈和建议。感谢大家的理解与支持。

## 系统要求

- macOS 15 或更新版本
- Apple Silicon（arm64）Mac

> [!NOTE]
> 本项目提供客户端，不提供服务器或订阅服务。

## 功能

- 手动添加或导入 Shadowsocks 配置，按分组和收藏整理服务器；添加 HTTPS SIP-008 订阅，并查看服务商提供的流量与到期信息。
- 使用全局模式、规则模式或直连模式。规则模式提供三种规则方案：`仅代理 GFW 列表内目标`、`中国大陆目标直连`、`中国大陆目标代理`。可查看内置规则，并为每个方案管理自定义规则。
- 通过上游 `sslocal` 支持 SIP022 AEAD-2022 加密方法、SIP023 Shadowsocks 2022 可扩展身份标头和多服务器负载均衡。
- 支持服务器延迟检测。
- 通过本机 SOCKS5 与 HTTP 代理连接 Mac 应用和局域网设备。需要时可开启局域网监听，并设置访问凭据；局域网监听默认关闭。
- 内置 [v2ray-plugin](https://github.com/shadowsocks/v2ray-plugin) 和 [Cloak](https://github.com/cbeuw/Cloak)，也支持配置用户自己的插件。内嵌的 `v2ray-plugin` 还提供 [Hysteria2 传输模式](https://github.com/shadowsocks/v2ray-plugin#shadowsocks-over-hysteria2-transport)，用于传输 Shadowsocks TCP 流量；通信两端都需使用该模式，普通 Hysteria2 代理节点不兼容。
- 服务器库和监听配置以 age 格式加密保存在本机。诊断报告会排除密码、插件选项和订阅地址等敏感内容。
- 菜单栏界面提供简体中文和英语，可设置登录时启动。

## 项目与文档

- [旧版源码归档](https://github.com/shadowsocks/ShadowsocksX-NG/tree/legacy-v1)
- [NG2 开发文档](ShadowsocksX-NG2/README.zh.md)
- [开发与验证指南](docs/development.zh.md)
- [GPL-3.0 许可证](LICENSE)
