#!/bin/bash
# Builds the 3 modules and one app with swiftc (DESIGN.md, decision 9).
# usage: build.sh <embedded|normal> <data folder> <app name> <out folder> [extra swiftc flags for every module]
# The optimization is -Osize unless OPT is set, for example OPT=-O.
set -u
P=/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/prototype-large/swift
mode=$1; data=$2; app=$3; out=$4; shift 4
mkdir -p "$out"
export TMPDIR=/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/tools/rust/tmp
if [ "$mode" = embedded ]; then
    swiftc=/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-06-24-a.xctoolchain/usr/bin/swiftc
    flags=(-enable-experimental-feature Embedded -target arm64-apple-macos15 -sdk "$(xcrun --show-sdk-path)")
else
    swiftc=$(xcrun -f swiftc)
    flags=(-sdk "$(xcrun --sdk macosx --show-sdk-path)")
fi
flags+=(${OPT:--Osize} -wmo -module-cache-path "$out/module-cache" -I "$out" "$@")
module() {
    local name=$1; shift
    local start=$(date +%s)
    "$swiftc" "${flags[@]}" -parse-as-library -module-name "$name" -emit-module -emit-module-path "$out/$name.swiftmodule" -c -o "$out/$name.o" "$@" > "$out/$name.log" 2>&1 || { echo "FAILED $name"; grep -m12 -A3 "error:" "$out/$name.log"; exit 1; }
    echo "$name: $(( $(date +%s) - start )) s" >> "$out/times.txt"
}
if [ "${SKIP_LIBS:-0}" != 1 ]; then
    module DataMarkers $P/Sources/DataMarkers/*.swift
    module DateTimeFormat $P/Sources/DateTimeFormat/*.swift
    module DateTimeData "$data"/swift/*.swift
fi
[ "$app" = none ] && { echo "built the modules in $out"; exit 0; }
"$swiftc" "${flags[@]}" -module-name "$app" "$P/apps/$app/main.swift" "$out/DataMarkers.o" "$out/DateTimeFormat.o" "$out/DateTimeData.o" -Xlinker -dead_strip -o "$out/$app" > "$out/$app.log" 2>&1 || { echo "FAILED $app"; grep -m12 -A3 "error:" "$out/$app.log"; exit 1; }
echo "built $out/$app"
