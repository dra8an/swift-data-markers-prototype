#!/bin/bash
# Builds and runs everything after a change: the checks, the size apps (full and cut data), and the bench apps.
set -u
P=/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/prototype-large
cd $P
. ../env.sh
export LOCALES=cases/locales.txt DATES=cases/dates.txt
step() { echo "$(date +%H:%M:%S) $*"; }
step "check builds"
swift/build.sh normal data/full Check out/normal-full || exit 1
swift/build.sh embedded data/full Check out/embedded-full || exit 1
(cd rust-copy && RUST_COPY_DATA=$P/data/full/rust/data.rs cargo build --release --offline --bin check 2>&1 | grep -E "^error" -A8)
step "checks"
out/normal-full/Check > results/swift-normal-check.tsv
out/embedded-full/Check > results/swift-embedded-check.tsv
rust-copy/target/release/check > results/rust-copy-check.tsv
python3 -I -B tools/compare.py results/icu4x-reference.tsv results/swift-normal-check.tsv "Swift normal"
python3 -I -B tools/compare.py results/icu4x-reference.tsv results/swift-embedded-check.tsv "Swift Embedded"
python3 -I -B tools/compare.py results/icu4x-reference.tsv results/rust-copy-check.tsv "Rust copy"
step "sizes, full data"
swift/build-sizes.sh data/full out/full | tail -1
for b in gregorian_ymd japanese_ymdt any_calendar; do
    (cd rust-copy && RUST_COPY_DATA=$P/data/full/rust/data.rs cargo build --release --offline --bin $b 2>&1 | grep -E "^error" -A8)
    cp rust-copy/target/release/$b out/full-rustcopy/$b
done
step "sizes, cut data"
tools/build-cut.sh ja | tail -1
step "bench builds"
tools/build-bench.sh | tail -1
step "bench runs"
tools/run-bench.sh
step "ALL DONE"
