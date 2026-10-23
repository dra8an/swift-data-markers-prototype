#!/bin/bash
export TMPDIR=/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/tools/rust/tmp
read -r -a markers < /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/icu4x-experiments/runs/app-a-markers.txt
echo "markers: ${#markers[@]}"
perl -e 'alarm shift; exec @ARGV' 900 /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/tools/bin/icu4x-datagen-unstable --cldr-root /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/data/cldr-49.0.0-BETA4/full --tzdb-root /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/data/tzdata-2026e/root --markers "${markers[@]}" --locales ko --attribute-filter datetime_month_length=/5/ --format baked --out /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/icu4x-experiments/runs/ko-app-a-markers-tz
echo "rc=$?"
