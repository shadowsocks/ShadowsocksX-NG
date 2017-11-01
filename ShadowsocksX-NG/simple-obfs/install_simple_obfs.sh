#!/bin/sh

FILE_DIR=`dirname "${BASH_SOURCE[0]}"`
cd "$FILE_DIR"

NGDir="$HOME/Library/Application Support/ShadowsocksX-NG"
TargetDir="$NGDir/simple-obfs-0.0.2"
PluginDir="$NGDir/plugins"

echo ngdir: ${NGDir}

mkdir -p "$TargetDir"
mkdir -p "$PluginDir"

cp -f obfs-local "$TargetDir"

ln -sfh "$TargetDir/obfs-local" "$PluginDir"

echo done
