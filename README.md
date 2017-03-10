# ShadowsocksX-NG

Current version is 1.5

[![Build Status](https://travis-ci.org/shadowsocks/ShadowsocksX-NG.svg?branch=develop)](https://travis-ci.org/shadowsocks/ShadowsocksX-NG)

Next Generation of [ShadowsocksX](https://github.com/shadowsocks/shadowsocks-iOS)

## Why?

It's hard to maintain the original implementation as there is too much unused code in it.
It also embeds the ss-local source. It's crazy to maintain dependencies of ss-local.
So it's hard to update the ss-local version.

Now I just copied the ss-local from homebrew. Run ss-local executable as a Launch Agent in the background.
Serve PAC js file as a file URL. So there is only some source code related to GUI left.
Then I will rewrite the GUI code in Swift.

## Requirements

### Running

- Mac OS X 10.11 +

### Building

- XCode 8.2.1+
- cocoapod 1.2+

## Download

From [here](https://github.com/shadowsocks/ShadowsocksX-NG/releases/)

## Features

- Use ss-local from shadowsocks-libev 2.5.6
- Could Update PAC by download GFW List from GitHub.
- Show QRCode for current server profile.
- Scan QRCode from screen.
- Auto launch at login.
- User rules for PAC.
- Support OTA
- HTTP Proxy by [privoxy](http://www.privoxy.org/)
- Over [kcptun](https://github.com/xtaci/kcptun)
- Export/Import configure file.
- An advanced preferences panel to configure:
	- Local socks5 listen address.
	- Local socks5 listen port.
	- Local socks5 timeout.
	- If enable UDP relay.
	- GFW List URL.
- Manual specify network service profiles which would be configure the proxy.
- Could reorder shadowsocks profiles by drag & drop in servers preferences panel.
- Configurable global shortcuts for toggle running and switch proxy mode.

## Different from orignal ShadowsocksX

Run ss-local as a background service through launchd, not as an in-app process.
So after you quit the app, the ss-local maybe be still running.

Added a manual mode which won't configure the system proxy settings.
Then you could configure your apps to use socks5 proxy manual.

## Contributing 

[![gitter](https://badges.gitter.im/Join Chat.svg)](https://gitter.im/ShadowsocksX-NG/Lobby)

Contributions must be available on a separately named branch based on the latest version of the main branch develop.

ref: [GitFlow](http://nvie.com/posts/a-successful-git-branching-model/)

## License

The project is released under the terms of the GPLv3.

