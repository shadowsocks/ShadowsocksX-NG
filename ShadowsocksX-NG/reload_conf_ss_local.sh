#!/bin/sh

#  reload_conf_ss_local.sh
#  ShadowsocksX-NG
#
#  Created by 邱宇舟 on 16/6/6.
#  Copyright © 2016年 qiuyuzhou. All rights reserved.

#launchctl kill SIGHUP "$HOME/Library/LaunchAgents/com.qiuyuzhou.shadowsocksX-NG.local.plist"

launchctl unload "$HOME/Library/LaunchAgents/com.qiuyuzhou.shadowsocksX-NG.local.plist"
launchctl load "$HOME/Library/LaunchAgents/com.qiuyuzhou.shadowsocksX-NG.local.plist"
