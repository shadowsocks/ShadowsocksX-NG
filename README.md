# ShadowsocksX-NG-R

Current version is 1.3.9-R8

Continuesly release under 1.3.9-R8-buildVersion

[![Build Status](https://travis-ci.org/shadowsocksr/ShadowsocksX-NG.svg?branches=develop)](https://travis-ci.org/shadowsocksr/ShadowsocksX-NG)

Next Generation of [ShadowsocksX](https://github.com/shadowsocks/shadowsocks-iOS) with SSR support.

**After Download Please check the GPG signature!**

First get [My pub key](https://github.com/qinyuhang/Pubkey) and [import the Pub key]()

`gpg --import pubkeys.txt`

Then [verify the signature](http://stackoverflow.com/questions/19011093/how-do-i-verify-a-gpg-signature-matches-a-public-key-file)

Place the `.dmg` and `.dmg.sig` file together in a directory

`gpg --verify {drag the ShadowsocksX-NG-R8.dmg.sig into your terminal}`

## Why?

It's hard to maintain the original implement. There are too many unused code in it. 
It also embed ss-local source. It's crazy to maintain depandences of ss-local. 
So it's hard to update ss-local version.

Now I just copy the ss-local from home brew. Run ss-local executable as a Launch Agent in background. 
Serve pac js file as a file url. So there are only some souce code related to GUI left. 
Then I rewrite the GUI code by swift.

## Requirements

### Running

- macOS 10.11 +

### Building

- Xcode 8.2.1+
- cocoapod 1.0.1+

## Fetures

- SSR features!
- Ability to check update from GitHub.
- White domain list & white IP list
- Use ss-local from shadowsocks-libev 2.5.6
- Ability to update PAC by download GFW List from GitHub.
- Ability to update white list from GutHub.
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
  - White List url.
  - Auto update PAC list & white list.
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

- [x] Embed the http proxy server [privoxy](http://www.privoxy.org/), [get it](https://homebrew.bintray.com/bottles/privoxy-3.0.26.sierra.bottle.tar.gz).


- [ ] ACL mode support [Shadowsocks ACL](https://github.com/shadowsocksr/shadowsocksr-libev/tree/master/acl)

## Know Issue
Solved [Issue 1.]() Auto PAC & White list is not working on macOS 10.12 Serria because system proxy not allow [file:///](file:///) protocol.
[Issue 2.]() The net speed is how ever have some problem with macOS 10.12, welcome logs from all users.

## License

The project is released under the terms of GPLv3.

