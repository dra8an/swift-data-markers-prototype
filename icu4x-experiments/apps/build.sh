#!/bin/bash
export RUSTUP_HOME=/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/tools/rust/rustup CARGO_HOME=/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/tools/rust/cargo PATH=/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/tools/rust/cargo/bin:$PATH TMPDIR=/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/tools/rust/tmp
app=$1; shift
cd /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/icu4x-experiments/apps/$app && perl -e 'alarm shift; exec @ARGV' 1800 env "$@" cargo build --release --jobs 6 > /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/icu4x-experiments/apps/$app.build.log 2>&1
echo "rc=$?" >> /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/icu4x-experiments/apps/$app.build.log
