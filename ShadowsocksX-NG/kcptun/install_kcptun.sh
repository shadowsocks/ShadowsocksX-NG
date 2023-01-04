#!/bin/sh

#  install_kcptun.sh
#  ShadowsocksX-NG
#
#  Created by 邱宇舟 on 2018/9/21.
#  Copyright © 2018-2019年 qiuyuzhou. All rights reserved.

# Use kcptune bianry from here which is not support SIP003.
# We use an adatper to handle it.
# https://github.com/xtaci/kcptun/releases

cd "$(dirname "${BASH_SOURCE[0]}")"

mkdir -p "$HOME/Library/Application Support/ShadowsocksX-NG/kcptun"
cp -f client "$HOME/Library/Application Support/ShadowsocksX-NG/kcptun/"

# Delete old kcptun symbol link
rm -f "$HOME/Library/Application Support/ShadowsocksX-NG/plugins/kcptun"

# Copy adapter shell script to plugin folder
cp -f kcptun.sh "$HOME/Library/Application Support/ShadowsocksX-NG/plugins/kcptun"

echo "install kcptun done"
