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

cp -f libev.4.dylib "$TargetDir"
cp -f libmbedcrypto.2.4.2.dylib "$TargetDir"
ln -s  "$TargetDir/libmbedcrypto.2.4.2.dylib" "$TargetDir/libmbedcrypto.0.dylib"
cp -f libpcre.1.dylib "$TargetDir"
cp -f libsodium.18.dylib "$TargetDir"
cp -f libudns.0.dylib "$TargetDir"

echo done
