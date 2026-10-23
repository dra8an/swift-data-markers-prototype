#!/bin/bash
# usage: build.sh <name> <embedded yes|no> <DateFormatData.swift path>
set -u
W=/tmp/deep-review/embedded-20261020; D=$W/src/Sources/_FoundationInternationalizationData
T=/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-06-24-a.xctoolchain/usr/bin/swiftc
SDK=$(xcrun --show-sdk-path); export TMPDIR=$W/tmp
name=$1; emb=$2; data=$3
flags=(-Osize -wmo -sdk "$SDK" -module-cache-path "$W/tmp/mc-$emb" -module-name DateProg -package-name FoundationPkg -enable-experimental-feature Lifetimes -DFOUNDATION_DATE_FORMAT_SWIFT)
[ "$emb" = yes ] && flags+=(-enable-experimental-feature Embedded -target arm64-apple-macos15 -Xlinker -dead_strip )
[ "$emb" = no ] && flags+=(-Xlinker -dead_strip)
files=("$D/DataLocaleIdentifier.swift" "$data" "${LOOKUP:-$D/DateFormatLookup.swift}" "$W/work/prog/main.swift")
[ "$name" = hello ] && files=("$W/../emb-hello.swift")
perl -e 'alarm shift; exec @ARGV' 300 "$T" "${flags[@]}" "${files[@]}" -o "$W/work/$name" > "$W/work/$name.build.log" 2>&1
echo "$name rc=$? $(stat -f %z "$W/work/$name" 2>/dev/null) bytes"
grep -m5 "error:" "$W/work/$name.build.log"
