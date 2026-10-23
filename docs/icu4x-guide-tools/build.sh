#!/bin/bash
export RUSTUP_HOME=/tmp/deep-review/rust/rustup CARGO_HOME=/tmp/deep-review/rust/cargo PATH=/tmp/deep-review/rust/cargo/bin:$PATH TMPDIR=/tmp/deep-review/rust/tmp
app=$1; shift
cd /tmp/deep-review/icu4x-apps/$app && perl -e 'alarm shift; exec @ARGV' 1800 env "$@" cargo build --release --jobs 6 > /tmp/deep-review/icu4x-apps/$app.build.log 2>&1
echo "rc=$?" >> /tmp/deep-review/icu4x-apps/$app.build.log
