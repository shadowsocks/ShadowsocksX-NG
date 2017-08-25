#!/bin/sh

#  fix_dir_owner.sh
#  ShadowsocksX-NG
#
#  Created by 邱宇舟 on 2017/8/25.
#  Copyright © 2017年 qiuyuzhou. All rights reserved.


LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
sudo chown $@ "$HOME/Library/LaunchAgents"

