# ShadowsocksX-NG2

English | [简体中文](README.zh.md)

A native Shadowsocks client for Apple Silicon Macs. Manage servers, subscriptions, and routing from the menu bar, and provide SOCKS5 and HTTP proxy endpoints for Mac apps.

> **Download:** Download the latest ShadowsocksX-NG2 release from [GitHub Releases](https://github.com/shadowsocks/ShadowsocksX-NG/releases). The page also hosts legacy 1.x releases.

## System requirements

- macOS 15 or later
- An Apple Silicon (arm64) Mac
- A Shadowsocks server configuration or SIP-008 subscription URL

This project provides a client. It does not provide servers or subscription services.

## Features

- **Manage servers and subscriptions:** Add or import Shadowsocks configurations, organize servers into groups, and mark favorites. Add HTTPS SIP-008 subscriptions and view traffic and expiry information provided by the service provider.
- **Choose how traffic is routed:** Use global, rules, or direct mode. In rules mode, review the bundled rules, write custom rules, and choose whether destinations use the proxy or connect directly.
- **Connect Mac apps and LAN devices:** Provide local SOCKS5 and HTTP proxies. You can enable LAN listeners and set access credentials when needed; LAN listeners are off by default.
- **Use proxy plugins:** `v2ray-plugin` and Cloak are included. The bundled `v2ray-plugin` also provides a [Hysteria2 transport mode](https://github.com/shadowsocks/v2ray-plugin#shadowsocks-over-hysteria2-transport) for Shadowsocks TCP traffic. Both ends must use this mode; ordinary Hysteria2 proxy nodes are not compatible. You can also configure your own plugins.
- **Protect local configuration and export diagnostics:** The server library and listener configuration are encrypted on your Mac using age. Diagnostic reports exclude sensitive data such as passwords, plugin options, and subscription URLs.
- **Use a familiar interface:** A native macOS menu bar app with Simplified Chinese and English interfaces. You can also launch it at login.

## How NG2 differs from Legacy

| | ShadowsocksX-NG2 | Legacy 1.x |
| --- | --- | --- |
| System requirements | macOS 15 or later, Apple Silicon | The legacy project documentation lists macOS 10.12 or later |
| Routing | Global, rules, and direct modes in the app; manage bundled and custom rules | PAC, GFWList, and manual modes |
| Installation and configuration | Separate app and configuration directory; can coexist with Legacy | The legacy app and its configuration can remain installed separately |
| Importing legacy settings | Can import legacy server configurations | Legacy preferences, routing mode, rules, and login item are not migrated automatically |

NG2 is a separate new app, not an in-place upgrade. Both apps can be installed side by side, and importing server configurations does not change Legacy data. macOS system proxy settings are shared by both apps, so check which app manages them when switching clients.

## Project and documentation

- [Legacy source archive](https://github.com/shadowsocks/ShadowsocksX-NG/tree/legacy-v1)
- [NG2 developer documentation](ShadowsocksX-NG2/README.md)
- [Development and validation guide](docs/development.md)
- [GPL-3.0 license](LICENSE)
