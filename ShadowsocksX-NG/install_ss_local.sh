#!/bin/sh

#  install_ss_local.sh
#  ShadowsocksX-NG
#
#  Created by 邱宇舟 on 16/6/6.
#  Copyright © 2016年 qiuyuzhou. All rights reserved.


cd `dirname "${BASH_SOURCE[0]}"`
mkdir -p "$HOME/Library/Application Support/ShadowsocksX-NG/ss-local-2.5.6"
cp -f ss-local "$HOME/Library/Application Support/ShadowsocksX-NG/ss-local-2.5.6/"
rm -f "$HOME/Library/Application Support/ShadowsocksX-NG/ss-local"
ln -s "$HOME/Library/Application Support/ShadowsocksX-NG/ss-local-2.5.6/ss-local" "$HOME/Library/Application Support/ShadowsocksX-NG/ss-local"

cp -f libcrypto.1.0.0.dylib "$HOME/Library/Application Support/ShadowsocksX-NG/"
cp -f libpcre.1.dylib "$HOME/Library/Application Support/ShadowsocksX-NG/"
rm -f "$HOME/Library/Application Support/ShadowsocksX-NG/libpcre.dylib"
ln -s "$HOME/Library/Application Support/ShadowsocksX-NG/libpcre.1.dylib" "$HOME/Library/Application Support/ShadowsocksX-NG/libpcre.dylib"

echo done
