#! /bin/bash

# Install latest ss-local (via shadowsocks-libev) and copy it to ShadowsocksX-NG
# folder.
# TODO(dborkan): Find a way to download this that doesn't affect the global
# state of the user's machine.
brew install shadowsocks-libev;
SS_LOCAL_PATH=`which ss-local`;
cp $SS_LOCAL_PATH ShadowsocksX-NG/ss-local;
