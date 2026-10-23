#!/bin/bash
set -e
echo "start $(date +%H:%M:%S)"
rsync -a /tmp/deep-review/rust/rustup /tmp/deep-review/rust/cargo /tmp/deep-review/rust/dl /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/tools/rust/ && echo "rust done"
cp /tmp/deep-review/rust/target/release/icu4x-datagen /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/tools/bin/icu4x-datagen
cp /tmp/deep-review/rust/target-unstable/release/icu4x-datagen /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/tools/bin/icu4x-datagen-unstable && echo "tools done"
rsync -a /tmp/deep-review/icu4x-src /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/tools/ && echo "icu4x-src done"
rsync -a /tmp/deep-review/cldr-49b4/cldr-49.0.0-BETA4-json-full.zip /tmp/deep-review/cldr-49b4/full /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/data/cldr-49.0.0-BETA4/ && echo "cldr done"
rsync -a /tmp/deep-review/tzdb-2026e/tzdata2026e.tar.gz /tmp/deep-review/tzdb-2026e/root /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/data/tzdata-2026e/ && echo "tzdata done"
rsync -a --exclude 'target*' /tmp/deep-review/icu4x-apps /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/icu4x-experiments/apps-src-tmp && echo "apps done"
rsync -a /tmp/deep-review/icu4x-run /tmp/deep-review/icu4x-guide /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/icu4x-experiments/ && echo "runs done"
echo "end $(date +%H:%M:%S)"
