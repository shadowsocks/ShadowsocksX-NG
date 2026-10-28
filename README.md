# ShadowsocksX-NG2

English | [简体中文](README.zh.md)

A native Shadowsocks client for Apple Silicon Macs. Manage servers, subscriptions, and routing from the menu bar. Mac apps can connect through its SOCKS5 and HTTP proxies.

> Download the latest ShadowsocksX-NG2 release from [GitHub Releases](https://github.com/shadowsocks/ShadowsocksX-NG/releases). The page also hosts legacy 1.x releases.

## Project status

ShadowsocksX-NG is undergoing a major rewrite. The legacy version is no longer maintained, and ShadowsocksX-NG 2 is still in development.

We will close all remaining legacy issues and temporarily restrict new Issues and PRs until the v2 code is stable and officially released.

Until then, please use [Discussions](https://github.com/shadowsocks/ShadowsocksX-NG/discussions) for questions, bug reports, feedback, and suggestions. Thanks for your understanding and support.

## System requirements

- macOS 15 or later
- An Apple Silicon (arm64) Mac

This project provides a client. It does not provide servers or subscription services.

## Features

- Add or import Shadowsocks configurations, organize servers into groups, and mark favorites. Add HTTPS SIP-008 subscriptions and view traffic and expiry information provided by the service provider.
- Use global, rules, or direct mode. In rules mode, choose a rule preset: `proxy GFW List destinations`, `connect to mainland China destinations directly`, or `proxy mainland China destinations`. Review bundled rules and manage custom rules for each preset.
- Use SIP022 AEAD-2022 ciphers, SIP023 Shadowsocks 2022 Extensible Identity Headers, and load balancing across multiple servers through upstream `sslocal`.
- Test server latency.
- Connect Mac apps and LAN devices through local SOCKS5 and HTTP proxies. You can enable LAN listeners and set access credentials when needed; LAN listeners are off by default.
- [v2ray-plugin](https://github.com/shadowsocks/v2ray-plugin) and [Cloak](https://github.com/cbeuw/Cloak) are included. The bundled `v2ray-plugin` also provides a [Hysteria2 transport mode](https://github.com/shadowsocks/v2ray-plugin#shadowsocks-over-hysteria2-transport) for Shadowsocks TCP traffic. Both ends must use this mode; ordinary Hysteria2 proxy nodes are not compatible. You can also configure your own plugins.
- The server library and listener configuration are encrypted on your Mac using age. Diagnostic reports exclude sensitive data such as passwords, plugin options, and subscription URLs.
- Use the menu bar app in Simplified Chinese or English, and optionally launch it at login.

## Project and documentation

- [Legacy source archive](https://github.com/shadowsocks/ShadowsocksX-NG/tree/legacy-v1)
- [NG2 developer documentation](ShadowsocksX-NG2/README.md)
- [Development and validation guide](docs/development.md)
- [GPL-3.0 license](LICENSE)
