#!/bin/bash
cd /tmp/deep-review/pr2330-80ebeafa
S=Sources/_FoundationInternationalizationData
for n in all set-forty set-five DateFormatData-en_US; do
  if [ $n = all ]; then data=$S/DateFormatData.swift; else data=cut/$n.swift; fi
  start=$(date +%s)
  perl -e 'alarm shift; exec @ARGV' 400 swiftc -O -wmo -package-name FoundationData -parse-as-library -module-name DFData -D FOUNDATION_DATE_FORMAT_SWIFT -enable-experimental-feature Lifetimes -c $data $S/DateFormatLookup.swift $S/DataLocaleIdentifier.swift -o obj/$n.o > obj/$n.err 2>&1
  echo "$n exit $? in $(( $(date +%s) - start )) s"
  [ -f obj/$n.o ] && size -m obj/$n.o | grep -E "Section|Segment|total" | grep -v "^\s*$"
done
echo DONE
