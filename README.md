# ShadowsocksX-NG

This repo is a fork of https://github.com/shadowsocks/ShadowsocksX-NG with the following changes:
* We have included our own ss-local binary, taken from `brew install shadowsocks-libev`.  To re-copy ss-local, run `./add-ss-local.sh`. In the longer term, we plan to build ss-local from source.
* We have removed privoxy as it's not needed in the default configuration.
