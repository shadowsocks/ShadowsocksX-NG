#!/bin/sh
# v0.0.5 https://bintray.com/homebrew/bottles/simple-obfs

FILE_DIR=`dirname "${BASH_SOURCE[0]}"`
cd "$FILE_DIR"

NGDir="$HOME/Library/Application Support/ShadowsocksX-NG"
TargetDir="$NGDir/simple-obfs-0.0.5_1"
PluginDir="$NGDir/plugins"

echo ngdir: ${NGDir}

mkdir -p "$TargetDir"
mkdir -p "$PluginDir"

cp -f obfs-local "$TargetDir"

ln -sfh "$TargetDir/obfs-local" "$PluginDir/simple-obfs"
ln -sfh "$TargetDir/obfs-local" "$PluginDir/obfs-local"

echo done
