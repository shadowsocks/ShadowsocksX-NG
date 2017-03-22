#!/bin/bash

#  install_ss_local.sh
#  ShadowsocksX-NG
#
#  Created by 邱宇舟 on 16/6/6.
#  Copyright © 2016年 qiuyuzhou. All rights reserved.


cd `dirname "${BASH_SOURCE[0]}"`

NGDir="$HOME/Library/Application Support/ShadowsocksX-NG"
TargetDir="$NGDir/ss-local-3.0.5"
LatestTargetDir="$NGDir/ss-local-latest"

echo ngdir: ${NGDir}

mkdir -p "$TargetDir"
cp -f ss-local "$TargetDir"
rm -f "$LatestTargetDir"
ln -s "$TargetDir" "$LatestTargetDir"
#ln -s "$HOME/Library/Application Support/ShadowsocksX-NG/ss-local-3.0.5/" "$HOME/Library/Application Support/ShadowsocksX-NG/ss-local-latest/"
#rm -f "$HOME/Library/Application Support/ShadowsocksX-NG/ss-local"
#ln -s "$HOME/Library/Application Support/ShadowsocksX-NG/ss-local-2.5.6/ss-local" "$HOME/Library/Application Support/ShadowsocksX-NG/ss-local"

cp -f libev.4.dylib "$TargetDir"
cp -f libmbedcrypto.2.4.2.dylib "$TargetDir"
cp -f libpcre.1.dylib "$TargetDir"
cp -f libsodium.18.dylib "$TargetDir"
cp -f libudns.0.dylib "$TargetDir"

#cp -f libcrypto.1.0.0.dylib "$HOME/Library/Application Support/ShadowsocksX-NG/"
#cp -f libpcre.1.dylib "$HOME/Library/Application Support/ShadowsocksX-NG/"
#rm -f "$HOME/Library/Application Support/ShadowsocksX-NG/libpcre.dylib"
#ln -s "$HOME/Library/Application Support/ShadowsocksX-NG/libpcre.1.dylib" "$HOME/Library/Application Support/ShadowsocksX-NG/libpcre.dylib"

echo done
