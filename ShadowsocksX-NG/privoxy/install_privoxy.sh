#!/bin/sh

#  install_privoxy.sh
#  ShadowsocksX-NG
#
#  Created by 王晨 on 16/10/7.
#  Copyright © 2016年 zhfish. All rights reserved.


cd "$(dirname "${BASH_SOURCE[0]}")"

privoxyVersion=3.0.29
targetDir="$HOME/Library/Application Support/ShadowsocksX-NG/privoxy-$privoxyVersion"
latestDir="$HOME/Library/Application Support/ShadowsocksX-NG/privoxy-latest"

mkdir -p "$targetDir"
cp -f privoxy "$targetDir"

# libpcreposix
cp -f libpcreposix.0.dylib "$targetDir"

rm -f "$latestDir"
ln -s "$targetDir" "$latestDir"

rm -f "$HOME/Library/Application Support/ShadowsocksX-NG/privoxy"
ln -s "$targetDir/privoxy" "$HOME/Library/Application Support/ShadowsocksX-NG/privoxy"

echo done
