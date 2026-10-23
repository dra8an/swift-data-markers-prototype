#!/bin/bash
# Builds the bench apps (DESIGN.md, decision 9): Swift in 3 modes with -O and -Osize, the Rust copy and ICU4X with opt-level 3 and "s".
set -u
P=/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/prototype-large
cd $P
. ../env.sh
flags3=(-Xfrontend -internalize-at-link -Xfrontend -conditional-runtime-records -lto=llvm-full)
OPT=-O swift/build.sh embedded data/full Bench out/bench-O-embedded || exit 1
OPT=-O swift/build.sh normal data/full Bench out/bench-O-normal || exit 1
OPT=-O swift/build.sh normal data/full Bench out/bench-O-normal3 "${flags3[@]}" || exit 1
SKIP_LIBS=1 swift/build.sh embedded data/full Bench out/full-embedded || exit 1
SKIP_LIBS=1 swift/build.sh normal data/full Bench out/full-normal || exit 1
SKIP_LIBS=1 swift/build.sh normal data/full Bench out/full-normal3 "${flags3[@]}" || exit 1
mkdir -p out/bench-rust
for profile in speed release; do
    (cd rust-copy && RUST_COPY_DATA=$P/data/full/rust/data.rs cargo build --profile $profile --offline --bin bench 2>&1 | grep -E "^error" -A8)
    cp rust-copy/target/$profile/bench out/bench-rust/rustcopy-$profile
    (cd icu4x-apps/sizes && cargo build --profile $profile --offline --bin bench 2>&1 | grep -E "^error" -A8)
    cp icu4x-apps/sizes/target/$profile/bench out/bench-rust/icu4x-$profile
done
echo "ALL DONE"
