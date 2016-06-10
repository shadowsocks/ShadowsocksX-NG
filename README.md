# ShadowsocksX-NG

Next Generation of ShadowsocksX in https://github.com/shadowsocks/shadowsocks-iOS

## Why another version

It's hard to maintaine the original implement. There are too many unused code in it. 
It also embed ss-local source. It's crazy to maitaine depandences of ss-local. 
So it's hard to update ss-local version.

Now I just copy the ss-local from home brew. Run ss-local executable as a Launch Agent in background. 
Serve pac js file as a file url. So there are only some souce codes related to GUI left. 
Then I rewrite the gui code by swift.

## TODO List

- Launch At Login
- GUI for OTA config
- Copy a ss url to pasteboard in the server profile UI.
