# ShadowsocksX-NG

Current version is 1.3

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

- XCode 8.0+
- cocoapod 1.0.1+

## Download

From [here](https://github.com/shadowsocks/ShadowsocksX-NG/releases/)

## Fetures

- Use ss-local from shadowsocks-libev 2.4.6
- Update PAC by download GFW List from GitHub.
- Show QRCode for current server profile.
- Scan QRCode from screen.
- Auto launch at login.
- User rules for PAC.
- Support OTA
- An advanced preferences panel to configure:
	- Local socks5 listen address.
	- Local socks5 listen port.
	- Local socks5 timeout.
	- If enable UDP relay.
	- GFW List URL.
- Manual specify network service profiles which would be configure the proxy.
- Could reorder shadowsocks profiles by drag & drop in servers preferences panel.

## Different from orignal ShadowsocksX

Run ss-local as a background service through launchd, not as an in-app process.
So after you quit the app, the ss-local maybe be still running.

Added a manual mode which won't configure the system proxy settings.
Then you could configure your apps to use socks5 proxy manual.

Added global Keyboard shortcut <kbd>⌃</kbd> + <kbd>⌘</kbd> + <kbd>P</kbd> to switch between `global` mode and `auto` mode.

## Contributing

Contributions must be available on a separately named branch based on the latest version of the main branch develop.

ref: [GitFlow](http://nvie.com/posts/a-successful-git-branching-model/)

## TODO List

- [x] Embed the http proxy server [privoxy](http://www.privoxy.org/), [get it](https://homebrew.bintray.com/bottles/privoxy-3.0.26.sierra.bottle.tar.gz).

## License

The project is released under the terms of the GPLv3.

