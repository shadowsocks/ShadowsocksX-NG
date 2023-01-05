#!/bin/sh

#  install_privoxy.sh
#  ShadowsocksX-NG
#
#  Created by 王晨 on 16/10/7.
#  Copyright © 2016年 zhfish. All rights reserved.


cd "$(dirname "${BASH_SOURCE[0]}")"

mkdir -p "$HOME/Library/Application Support/ShadowsocksX-NG/privoxy"
cp -f privoxy "$HOME/Library/Application Support/ShadowsocksX-NG/privoxy/"

echo done
