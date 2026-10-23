#!/bin/bash
# Builds the apps of the value API in the style of Foundation (RESULTS.md, "A value API").
set -u
P=/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/prototype-large
cd $P
export VALUE_API=1
flags3=(-Xfrontend -internalize-at-link -Xfrontend -conditional-runtime-records -lto=llvm-full)
swift/build.sh normal data/full ValueCheck out/value-normal || exit 1
SKIP_LIBS=1 swift/build.sh normal data/full ValueChinese out/value-normal || exit 1
SKIP_LIBS=1 swift/build.sh normal data/full ValueRuntime out/value-normal || exit 1
for app in ValueChinese ValueRuntime; do
    skip=1; [ $app = ValueChinese ] && skip=0
    SKIP_LIBS=$skip swift/build.sh embedded data/full $app out/value-embedded || exit 1
    SKIP_LIBS=$skip swift/build.sh embedded data/full $app out/value-embedded-lto -lto=llvm-full || exit 1
    SKIP_LIBS=$skip swift/build.sh normal data/full $app out/value-normal3 "${flags3[@]}" || exit 1
done
OPT=-O swift/build.sh normal data/full ValueBench out/value-bench-O-normal3 "${flags3[@]}" || exit 1
SKIP_LIBS=1 swift/build.sh embedded data/full ValueBench out/value-embedded || exit 1
echo "ALL DONE"
