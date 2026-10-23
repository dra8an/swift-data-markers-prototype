#!/bin/bash
# Builds the 3 modules and one app with swiftc. See DESIGN.md, decision 9.
# usage: build.sh <embedded|normal> <data folder> <app name> <out folder> [extra swiftc flags for every module]
set -u
P=/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/prototype
mode=$1; data=$2; app=$3; out=$4; shift 4
mkdir -p "$out"
export TMPDIR=$P/../tools/rust/tmp
if [ "$mode" = embedded ]; then
    swiftc=/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-06-24-a.xctoolchain/usr/bin/swiftc
    flags=(-enable-experimental-feature Embedded -target arm64-apple-macos15 -sdk "$(xcrun --show-sdk-path)")
else
    swiftc=$(xcrun -f swiftc)
    flags=(-sdk "$(xcrun --sdk macosx --show-sdk-path)")
fi
flags+=(-Osize -wmo -module-cache-path "$out/module-cache" -I "$out" "$@")
module() {
    local name=$1; shift
    "$swiftc" "${flags[@]}" -parse-as-library -module-name "$name" -emit-module -emit-module-path "$out/$name.swiftmodule" -c -o "$out/$name.o" "$@" > "$out/$name.log" 2>&1 || { echo "FAILED $name"; grep -m6 "error:" "$out/$name.log"; exit 1; }
}
module DataMarkers $P/Sources/DataMarkers/*.swift
module DateNames $P/Sources/DateNames/*.swift
module DateNamesData "$data"/*.swift
"$swiftc" "${flags[@]}" -module-name "$app" "$P/apps/$app/main.swift" "$out/DataMarkers.o" "$out/DateNames.o" "$out/DateNamesData.o" -Xlinker -dead_strip -o "$out/$app" > "$out/$app.log" 2>&1 || { echo "FAILED $app"; grep -m6 "error:" "$out/$app.log"; exit 1; }
echo "built $out/$app"
