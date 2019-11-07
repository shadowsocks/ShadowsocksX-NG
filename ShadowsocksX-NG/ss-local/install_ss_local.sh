#!/bin/bash

#  install_ss_local.sh
#  ShadowsocksX-NG
#
#  Created by 邱宇舟 on 16/6/6.
#  Copyright © 2016年 qiuyuzhou. All rights reserved.


cd "$(dirname "${BASH_SOURCE[0]}")"

NGDir="$HOME/Library/Application Support/ShadowsocksX-NG"
TargetDir="$NGDir/ss-local-3.2.5"
LatestTargetDir="$NGDir/ss-local-latest"

echo ngdir: ${NGDir}

# 3.2.5 https://bintray.com/homebrew/bottles/shadowsocks-libev/
mkdir -p "$TargetDir"
cp -f ss-local "$TargetDir"
rm -f "$LatestTargetDir"
ln -s "$TargetDir" "$LatestTargetDir"

cp -f libev.4.dylib "$TargetDir"

# 2.8.0 https://bintray.com/homebrew/bottles/mbedtls
cp -f libmbedcrypto.2.12.0.dylib "$TargetDir"
ln -sfh  "$TargetDir/libmbedcrypto.2.12.0.dylib" "$TargetDir/libmbedcrypto.2.dylib"
ln -sfh  "$TargetDir/libmbedcrypto.2.12.0.dylib" "$TargetDir/libmbedcrypto.3.dylib"

# 8.42 https://bintray.com/homebrew/bottles/pcre
cp -f libpcre.1.dylib "$TargetDir"

# 1.0.18 https://bintray.com/homebrew/bottles/libsodium
cp -f libsodium.23.dylib "$TargetDir"
ln -sfh "$TargetDir/libsodium.23.dylib" "$TargetDir/libsodium.dylib"

#cp -f libudns.0.dylib "$TargetDir"

# 1.15.0 https://bintray.com/homebrew/bottles/c-ares
cp -f libcares.2.dylib "$TargetDir"
ln -sfh "$TargetDir/libcares.2.dylib" "$TargetDir/libcares.dylib"

echo done
