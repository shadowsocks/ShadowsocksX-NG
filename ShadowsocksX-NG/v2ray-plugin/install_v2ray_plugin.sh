#!/bin/sh

#  install_v2ray_plugin.sh
#  ShadowsocksX-NG
#
#  Created by lkebin on 2019/2/18.
#  Copyright © 2019 qiuyuzhou. All rights reserved.
# https://github.com/shadowsocks/v2ray-plugin/

VERSION="1.3.1-7-g997ef6e"

cd "$(dirname "${BASH_SOURCE[0]}")"

mkdir -p "$HOME/Library/Application Support/ShadowsocksX-NG/v2ray-plugin_$VERSION"
cp -f v2ray-plugin "$HOME/Library/Application Support/ShadowsocksX-NG/v2ray-plugin_$VERSION/"

ln -sfh "$HOME/Library/Application Support/ShadowsocksX-NG/v2ray-plugin_$VERSION/v2ray-plugin" "$HOME/Library/Application Support/ShadowsocksX-NG/plugins/v2ray-plugin"
ln -sfh "$HOME/Library/Application Support/ShadowsocksX-NG/v2ray-plugin_$VERSION/v2ray-plugin" "$HOME/Library/Application Support/ShadowsocksX-NG/plugins/v2ray"

echo "install v2ray-plugin done"
