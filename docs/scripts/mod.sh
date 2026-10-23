#!/bin/bash
# usage: mod.sh <module name> <source dir> [extra swiftc args...] : builds an Embedded static module into l2/mods
set -u
W=/tmp/deep-review/embedded-20261020; O=$W/work/l2/mods
T=/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-06-24-a.xctoolchain/usr/bin/swiftc
export TMPDIR=$W/tmp
name=$1; dir=$2; shift 2
files=(); while IFS= read -r f; do files+=("$f"); done < <(find "$dir" -name '*.swift' | sort)
perl -e 'alarm shift; exec @ARGV' 600 "$T" -enable-experimental-feature Embedded -target arm64-apple-macos26 -sdk /Applications/Xcode4.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk -Osize -wmo -parse-as-library -module-name "$name" -module-cache-path $W/tmp/mc-l2-x4 -I $O -emit-module -emit-module-path $O/$name.swiftmodule -c -o $O/$name.o "$@" "${files[@]}" > $W/work/l2/$name.log 2>&1
rc=$?; echo "$name rc=$rc files=${#files[@]} errors=$(grep -c 'error:' $W/work/l2/$name.log)"
