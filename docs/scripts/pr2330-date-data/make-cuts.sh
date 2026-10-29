#!/bin/bash
# Builds the PR #2330 date tables for several locale cuts, as in FOUNDATION-DATE-DATA-ARCHITECTURE.md section 4.
# Usage: make-cuts.sh <PR 2330 files at 80ebeafa3d> <output folder>
# The first folder must have utils/ and Sources/_FoundationInternationalizationData/ of the PR.
# Writes nothing into the PR folder. The tool is compiled into the output folder.
set -u
PR=$1; OUT=$2; mkdir -p "$OUT"
cd "$PR" || exit 1
# A debug build prints the message of a failed precondition. A build with -O exits with code 133 and no message.
swiftc -Onone -g -parse-as-library utils/date-format-data-schema.swift utils/cldr-locale-fallback.swift utils/build-date-format-data-impl.swift -o "$OUT/build-date" || exit 1
J=Sources/_FoundationInternationalizationData/DateFormatData.json
FORTY=ar,ca,cs,da,de,el,en,en_AU,en_GB,en_IN,es,es_419,fi,fr,fr_CA,he,hi,hr,hu,id,it,ja,ko,ms,nb,nl,pl,pt,pt_PT,ro,ru,sk,sv,th,tr,uk,vi,zh,zh_Hant,zh_Hant_HK
for set in "all:" "en_US:en_US" "en_US+es_US:en_US,es_US" "five:de,fr,ja,zh,es" "forty:$FORTY" "zh_Hans-only:zh_Hans"; do
  name=${set%%:*}; locales=${set#*:}
  env INPUT=$J OUTPUT_SWIFT="$OUT/DateFormatData-$name.swift" LOCALES="$locales" FALLBACK= "$OUT/build-date" > "$OUT/$name.log" 2>&1
  echo "$name exit $?: $(tr '\n' ' ' < "$OUT/$name.log")"
done
# Expected: "zh_Hans-only" stops with "zh_AA needs a redirect for every region".
