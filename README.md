# ShadowsocksX-NG

Current version is 1.2

[![Build Status](https://travis-ci.org/qiuyuzhou/ShadowsocksX-NG.svg?branch=develop)](https://travis-ci.org/qiuyuzhou/ShadowsocksX-NG)

Next Generation of [ShadowsocksX](https://github.com/shadowsocks/shadowsocks-iOS)

## Why?

It's hard to maintaine the original implement. There are too many unused code in it. 
It also embed ss-local source. It's crazy to maitaine depandences of ss-local. 
So it's hard to update ss-local version.

Now I just copy the ss-local from home brew. Run ss-local executable as a Launch Agent in background. 
Serve pac js file as a file url. So there are only some souce codes related to GUI left. 
Then I rewrite the gui code by swift.

## Requirements

### Running

- Mac OS X 10.10 +

### Building

- XCode 7.3+
- cocoapod 1.0.1+

## Fetures

- Use ss-local from shadowsocks-libev 2.4.6
- Update PAC by download GFW List from github.
- Show QRCode for current server profile.
- Scan QRCode from screen.
- Auto launch at login.
- User rules for PAC.
- Support OTA
- An advance preferences panel to configure:
	- Local socks5 listen address.
	- Local socks5 listen port.
	- Local socks5 timeout.
	- If enable UDP relay.
	- GFW List url.
- Manual spesify network service profiles which would be configure the proxy.
- Could reorder shadowsocks profiles by drag & drop in servers preferences panel.

## Different from orignal ShadowsocksX

Run ss-local as backgroud service through launchd, not in app process.
So after you quit the app, the ss-local maybe is still running. 

Add a manual mode which won't configure the system proxy settings. 
Then you could configure your apps to use socks5 proxy manual.

## Contributing

Contributions must be available on a separately named branch based on the latest version of the main branch develop.

ref: [GitFlow](http://nvie.com/posts/a-successful-git-branching-model/)

## TODO List

- [ ] Embed the http proxy server [privoxy](http://www.privoxy.org/).

## License

The project is released under the terms of GPLv3.

