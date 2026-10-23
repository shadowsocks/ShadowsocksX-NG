# ShadowsocksX-NG2

[English](README.md) | 简体中文

面向 Apple Silicon Mac 的原生 Shadowsocks 客户端。通过菜单栏管理服务器、订阅和代理规则，并为 Mac 应用提供 SOCKS5 与 HTTP 代理入口。

> **下载**：请从 [GitHub Releases](https://github.com/shadowsocks/ShadowsocksX-NG/releases) 下载最新的 ShadowsocksX-NG2 版本。发布页也会保留旧版 1.x。

## 项目状态

ShadowsocksX-NG 正在进行大规模重构。旧版已停止维护，ShadowsocksX-NG 2 仍在开发中。

我们会关闭旧版遗留的所有 Issue。v2 代码稳定并正式发布前，我们暂不接受新的 Issue 和 PR。

这段时间里，如果你有使用问题或发现 Bug，欢迎到 [Discussions](https://github.com/shadowsocks/ShadowsocksX-NG/discussions) 交流。感谢大家的理解与支持，也欢迎在那里分享反馈和建议。

## 系统要求

- macOS 15 或更新版本
- Apple Silicon（arm64）Mac

本项目提供客户端，不提供服务器或订阅服务。

## 功能

- **管理服务器和订阅**：手动添加或导入 Shadowsocks 配置，按分组和收藏整理服务器；添加 HTTPS SIP-008 订阅，并查看服务商提供的流量与到期信息。
- **选择代理方式**：使用全局模式、规则模式或直连模式。规则模式支持查看内置规则、编写自定义规则，并为目标选择代理或直连。
- **连接 Mac 应用和局域网设备**：提供本机 SOCKS5 与 HTTP 代理。需要时可开启局域网监听，并设置访问凭据；局域网监听默认关闭。
- **使用代理插件**：内置 [v2ray-plugin](https://github.com/shadowsocks/v2ray-plugin) 和 [Cloak](https://github.com/cbeuw/Cloak)，也支持配置用户自己的插件。内嵌的 `v2ray-plugin` 还提供 [Hysteria2 传输模式](https://github.com/shadowsocks/v2ray-plugin#shadowsocks-over-hysteria2-transport)，用于传输 Shadowsocks TCP 流量；通信两端都需使用该模式，普通 Hysteria2 代理节点不兼容。
- **保护本地配置并导出诊断**：服务器库和监听配置以 age 格式加密保存在本机。诊断报告会排除密码、插件选项和订阅地址等敏感内容。
- **使用熟悉的界面**：原生 macOS 菜单栏应用，界面提供简体中文和英语，也可设置登录时启动。

## 与旧版 ShadowsocksX-NG 的差异

| | ShadowsocksX-NG2 | 旧版 1.x |
| --- | --- | --- |
| 系统要求 | macOS 15 或更新版本，Apple Silicon | 旧版项目说明标注 macOS 10.12 或更新版本 |
| 代理规则 | 在应用内使用全局、规则和直连模式；可管理内置规则与自定义规则 | 提供 PAC、GFWList 和手动模式 |
| 安装与配置 | 独立应用和配置目录；不会覆盖旧版 | 旧版应用与其配置仍可单独保留 |
| 导入旧配置 | 可主动导入旧版服务器配置 | 旧版偏好、代理模式、规则和登录项不会自动迁入 |

NG2 是独立的新应用，不是旧版的原位升级。两者可以分别安装；导入服务器配置不会更改旧版数据。macOS 的系统代理设置由两款应用共用，切换客户端时请确认由哪一款管理系统代理。

## 项目与文档

- [旧版源码归档](https://github.com/shadowsocks/ShadowsocksX-NG/tree/legacy-v1)
- [NG2 开发文档](ShadowsocksX-NG2/README.zh.md)
- [开发与验证指南](docs/development.zh.md)
- [GPL-3.0 许可证](LICENSE)
