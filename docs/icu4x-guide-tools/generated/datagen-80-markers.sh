#!/bin/bash
export TMPDIR=/tmp/deep-review/rust/tmp
read -r -a markers < /tmp/deep-review/icu4x-run/app-a-markers.txt
echo "markers: ${#markers[@]}"
perl -e 'alarm shift; exec @ARGV' 900 /tmp/deep-review/rust/target-unstable/release/icu4x-datagen --cldr-root /tmp/deep-review/cldr-49b4/full --tzdb-root /tmp/deep-review/tzdb-2026e/root --markers "${markers[@]}" --locales ko --attribute-filter datetime_month_length=/5/ --format baked --out /tmp/deep-review/icu4x-run/ko-app-a-markers-tz
echo "rc=$?"
