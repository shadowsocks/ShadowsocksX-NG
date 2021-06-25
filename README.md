# ShadowsocksX-NG

[Download](https://github.com/shadowsocks/ShadowsocksX-NG/releases/latest)

[![Actions Status](https://github.com/shadowsocks/ShadowsocksX-NG/workflows/CI/badge.svg)](https://github.com/shadowsocks/ShadowsocksX-NG/actions)

Next Generation of [ShadowsocksX](https://github.com/shadowsocks/shadowsocks-iOS)

## Why a new implementation?

It's hard to maintain the original implementation as there is too much unused code in it.
It also embeds the `ss-local` source code. It's crazy to maintain dependencies of `ss-local`.
So it's hard to update the `ss-local` version.

Now I just copied the `ss-local` from Homebrew. Run `ss-local` executable as a Launch Agent in the background.
So there is only some source code related to GUI left.
Then I have rewrited the GUI code in Swift.

## Requirements

### Running

macOS 10.12+

### Building

- Xcode 12.5.1+
- CocoaPods 1.10.1+

## Download

From [here](https://github.com/shadowsocks/ShadowsocksX-NG/releases/)

## Features

- `ss-local` from shadowsocks-libev 3.2.5.
- Support SIP003 plugins. Embed `kcptun`,  `simple-obfs` and `v2ray-plugin`.
- Could update PAC by download GFW List from GitHub.
- Share your server profiles by qrcode or url.
- Import server profile urls from pasteboard.
- Import server profile by scan QRCode on screen.
- Custom rules for PAC.
- Support for [AEAD Ciphers](https://shadowsocks.org/en/spec/AEAD-Ciphers.html)
- HTTP Proxy by [privoxy](http://www.privoxy.org/)

## Difference from original ShadowsocksX

`ss-local` is run as a background service through launchd, not as an in-app process.
So after you quit the app, the `ss-local` might be still running.

Added a manual mode which won't configure the system proxy settings,
so that you could configure your apps to use the SOCKS5 proxy manually.

## Contributing

Contributions must be available on a separately named branch based on the latest version of the main branch `develop`.

ref: [GitFlow](http://nvie.com/posts/a-successful-git-branching-model/)

## License

The project is released under the terms of the GPLv3.

