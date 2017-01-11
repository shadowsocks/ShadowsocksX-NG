#!/bin/sh

#  install_kcptun.sh
#  ShadowsocksX-NG
#
#  Created by 邱宇舟 on 2017/1/11.
#  Copyright © 2017年 qiuyuzhou. All rights reserved.

cd `dirname "${BASH_SOURCE[0]}"`
mkdir -p "$HOME/Library/Application Support/ShadowsocksX-NG/kcptun_20161222"
cp -f kcptun_client "$HOME/Library/Application Support/ShadowsocksX-NG/kcptun_20161222/"
rm -f "$HOME/Library/Application Support/ShadowsocksX-NG/kcptun_client"
ln -s "$HOME/Library/Application Support/ShadowsocksX-NG/kcptun_20161222/kcptun_client" "$HOME/Library/Application Support/ShadowsocksX-NG/kcptun_client"

echo "install kcptun done"
