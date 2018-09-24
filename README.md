# ShadowsocksX-NG, API Supported

Current version: 1.8.1

This is a fork with minor feature added. All credits go to the **original authors**.

## Introduction

[shadowsocks/**ShadowsocksX-NG**](https://github.com/shadowsocks/ShadowsocksX-NG) doesn't support Alfred control. So I copy code from its obsolete fork [yichengchen/**ShadowsocksX-R**](https://github.com/yichengchen/ShadowsocksX-R/blob/42b409beb85aee19a4852e09e7c3e4c2f73f49d3/ShadowsocksX-NG/ApiServer.swift) to euip the app with **HTTP API**, enabling Alfred Control. You may want to download the **Alfred workflow** from [yangziy/Alfred_ShadowsocksController](https://github.com/yangziy/Alfred_ShadowsocksController).

With the **HTTP API** you could also control the app with **curl** in **terminal**.

## Feature

The **HTTP API** enables users to do the following:

- Check current status (on/off)
- Turn on/off or toggle the client
- Get server list
- Add new server
- Modify server
- Delete server
- Get current server
- Select server
- Get current mode
- Switch mode

For usage, consult [HTTP API Specification](https://github.com/yangziy/ShadowsocksX-NG_WithAPI/blob/master/HTTPAPI.md) .