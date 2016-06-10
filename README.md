# ShadowsocksX-NG

Next Generation of ShadowsocksX in https://github.com/shadowsocks/shadowsocks-iOS

## Why Another Implement

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
- cocoapod 1.0+

## TODO List

- GUI for OTA config
- Copy a ss url to pasteboard in the server profile UI.

## Known Inssues

- ss-local depand on libcrypto.1.0.0.dylib need installed by home brew.

