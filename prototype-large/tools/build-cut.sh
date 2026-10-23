#!/bin/bash
# Builds the size apps with data cut for one locale (DESIGN.md, decision 8), for Swift (3 modes) and the Rust copy.
# The markers of each app are the tags in its Embedded Swift build with the full data (tools/measure.py), as --markers-for-bin does in ICU4X.
# usage: build-cut.sh <locale>
set -u
P=/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/prototype-large
locale=$1
cd $P
. ../env.sh
flags3=(-Xfrontend -internalize-at-link -Xfrontend -conditional-runtime-records -lto=llvm-full)
for pair in GregorianYMD:gregorian_ymd JapaneseYMDT:japanese_ymdt AnyCalendar:any_calendar; do
    app=${pair%%:*}; bin=${pair##*:}
    markers=$(python3 -I -B tools/measure.py data/full/markers.json out/full-embedded/$app | tail -1 | cut -f7)
    echo "$app: markers $markers"
    data=data/cut-$locale-$app
    python3 -I -B generator/generate.py --fs icu4x-data/fs-recommended --fallback icu4x-data/fs-fallback --out $data --replace --markers "$markers" --locales $locale | tail -1
    swift/build.sh embedded $data $app out/cut-$locale-$app-embedded || exit 1
    swift/build.sh normal $data $app out/cut-$locale-$app-normal || exit 1
    swift/build.sh normal $data $app out/cut-$locale-$app-normal3 "${flags3[@]}" || exit 1
    features=--no-default-features
    [ $bin = any_calendar ] && features=
    (cd rust-copy && RUST_COPY_DATA=$P/$data/rust/data.rs cargo build --release --offline $features --bin $bin 2>&1 | grep -E "^error" -A8) && true
    mkdir -p out/cut-$locale-rustcopy
    cp rust-copy/target/release/$bin out/cut-$locale-rustcopy/$bin
    echo "built out/cut-$locale-rustcopy/$bin"
done
echo "ALL DONE"
