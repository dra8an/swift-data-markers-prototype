#!/bin/bash
# Builds both apps in both modes with both data sets: 8 builds.
P=/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/prototype
for mode in embedded normal; do
  for data in full all-locales; do
    for app in OnlyJapaneseMonths AllMarkers; do
      perl -e 'alarm shift; exec @ARGV' 600 $P/build.sh $mode $P/data/$data $app $P/out/$mode-$data-$app
    done
  done
done
echo "ALL DONE"
