#!/bin/bash
# Builds the 3 size apps in the 3 Swift modes for one data set (DESIGN.md, decision 9).
# usage: build-sizes.sh <data folder> <out prefix>   (example: build-sizes.sh data/full out/full)
set -u
P=/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/prototype-large
data=$1; out=$2
cd $P
flags3=(-Xfrontend -internalize-at-link -Xfrontend -conditional-runtime-records -lto=llvm-full)
first=1
for app in GregorianYMD JapaneseYMDT AnyCalendar; do
    if [ $first = 1 ]; then skip=0; else skip=1; fi
    SKIP_LIBS=$skip swift/build.sh embedded $data $app $out-embedded || exit 1
    SKIP_LIBS=$skip swift/build.sh normal $data $app $out-normal || exit 1
    SKIP_LIBS=$skip swift/build.sh normal $data $app $out-normal3 "${flags3[@]}" || exit 1
    first=0
done
echo "ALL DONE"
