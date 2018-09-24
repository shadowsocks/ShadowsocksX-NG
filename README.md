# ShadowsocksX-NG, API Supported

Current version is 1.8.1

## Introduction

[shadowsocks/**ShadowsocksX-NG**](https://github.com/shadowsocks/ShadowsocksX-NG) doesn't support Alfred control. So I steal code from [yichengchen/**ShadowsocksX-R**](https://github.com/yichengchen/ShadowsocksX-R/blob/42b409beb85aee19a4852e09e7c3e4c2f73f49d3/ShadowsocksX-NG/ApiServer.swift) , replace obsolete methods to get it work. Now the app is equipped with **HTTP API**.  You may want to download the **Alfred workflow** from [yangziy/Alfred_ShadowsocksController](https://github.com/yangziy/Alfred_ShadowsocksController).

All credits go to the original authors. Any distribution & reproduction must follow the original licenses. [GPLv3](https://www.gnu.org/licenses/quick-guide-gplv3.en.html)

## Feature

The **HTTP API** enables users to do the following:

- Check current status (on/off)
- Toggle the client
- Get server list
- Add new server
- Modify server
- Delete server
- Get current server
- Select server
- Get current mode
- Switch mode

For usage, consult [HTTP API Specification](https://github.com/yangziy/ShadowsocksX-NG_WithAPI/blob/master/HTTPAPI.md) .