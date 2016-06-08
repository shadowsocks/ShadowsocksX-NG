#!/bin/sh

#  reload_conf_ss_local.sh
#  ShadowsocksX-NG
#
#  Created by 邱宇舟 on 16/6/6.
#  Copyright © 2016年 qiuyuzhou. All rights reserved.

#launchctl kill SIGHUP "$HOME/Library/LaunchAgents/com.qiuyuzhou.shadowsocksX-NE.local.plist"

launchctl kickstart -k "$HOME/Library/LaunchAgents/com.qiuyuzhou.shadowsocksX-NE.local.plist"
