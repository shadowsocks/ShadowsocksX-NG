#!/bin/sh

#  install_v2ray_plugin.sh
#  ShadowsocksX-NG
#
#  Created by lkebin on 2019/2/18.
#  Copyright © 2019 qiuyuzhou. All rights reserved.
# https://github.com/shadowsocks/v2ray-plugin/

# v2ray-core/v4 v4.38.3
# build by go1.16.4
#
# v2ray-plugin_darwin_universal: Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64]
# v2ray-plugin_darwin_universal (for architecture x86_64):        Mach-O 64-bit executable x86_64
# v2ray-plugin_darwin_universal (for architecture arm64): Mach-O 64-bit executable arm64

cd "$(dirname "${BASH_SOURCE[0]}")"

mkdir -p "$HOME/Library/Application Support/ShadowsocksX-NG/v2ray-plugin"
cp -f v2ray-plugin "$HOME/Library/Application Support/ShadowsocksX-NG/v2ray-plugin/"

ln -sfh "$HOME/Library/Application Support/ShadowsocksX-NG/v2ray-plugin/v2ray-plugin" "$HOME/Library/Application Support/ShadowsocksX-NG/plugins/v2ray-plugin"
ln -sfh "$HOME/Library/Application Support/ShadowsocksX-NG/v2ray-plugin/v2ray-plugin" "$HOME/Library/Application Support/ShadowsocksX-NG/plugins/v2ray"

echo "install v2ray-plugin done"
