#!/bin/bash

# A shadowsocks SIP003 adapter shell script.
#
# SIP003 Docucment: https://github.com/shadowsocks/shadowsocks-org/issues/28
#
# Created by Qiu Yuzhou on 2019-09-09
# Copyright © 2019 Qiu Yuzhou. All rights reserved.

# test data, Start
# SS_REMOTE_HOST=127.0.0.1
# SS_REMOTE_PORT=8088
# SS_LOCAL_HOST=192.168.1.1
# SS_LOCAL_PORT=888
# test data, End

SS_ENV_NAMES=(SS_REMOTE_HOST SS_REMOTE_PORT SS_LOCAL_HOST SS_LOCAL_PORT)

for i in "${SS_ENV_NAMES[@]}"; do
    if [ -z ${!i} ]
    then
        echo Not found env variable $i
        exit
    fi
done

# Split options
IFS=';' read -ra _OPTS <<< "${SS_PLUGIN_OPTIONS}"

# Prepend `--`
OPTS=()
for i in "${_OPTS[@]}"; do
    OPTS+=("--$i")
done

PLUGIN_NAME="kcptun"
PLUGIN_BINARY_NAME="client"

CMD="$(dirname "${BASH_SOURCE[0]}")/../${PLUGIN_NAME}/${PLUGIN_BINARY_NAME}"

# Check if it is an IPv6 address
if  [[ $SS_REMOTE_HOST == *":"* ]]; then
    SS_REMOTE_ADDR="[${SS_REMOTE_HOST}]:${SS_REMOTE_PORT}"
else
    SS_REMOTE_ADDR="${SS_REMOTE_HOST}:${SS_REMOTE_PORT}"
fi

# Check if it is an IPv6 address
if  [[ $SS_LOCAL_HOST == *":"* ]]; then
    SS_LOCAL_ADDR="[${SS_LOCAL_HOST}]:${SS_LOCAL_PORT}"
else
    SS_LOCAL_ADDR="${SS_LOCAL_HOST}:${SS_LOCAL_PORT}"
fi

# Update this line when adapted other plugin.
# echo -r "${SS_REMOTE_ADDR}" -l "${SS_LOCAL_ADDR}" ${OPTS[@]}
"$CMD" -r "${SS_REMOTE_ADDR}" -l "${SS_LOCAL_ADDR}" ${OPTS[@]}
