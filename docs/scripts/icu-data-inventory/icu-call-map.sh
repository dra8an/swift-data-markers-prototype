#!/bin/bash
# Prints each ICU C function family with the files and functions that call it.
# Usage: icu-call-map.sh <source folder>
# Used on swift-foundation main bfbded0f70 (Sources/) and on the Darwin Foundation checkout 1e2ed46155.
cd "$1" || exit 1
grep -rnoE '\b(u[a-z]{2,12}_[a-zA-Z0-9]+|u_[a-zA-Z0-9]+)\(' --include='*.swift' --include='*.c' --include='*.m' --include='*.mm' --include='*.cpp' --exclude-dir=.build --exclude-dir=Tests --exclude-dir=Benchmarks --exclude-dir=Fuzzing . \
 | sed 's/($//' \
 | awk -F: '{f=$1; sub(/^\.\//,"",f); fn=$3; split(fn,a,"_"); if(a[1] ~ /^(uuid|uid|unix|uniq|unset)$/) next; key=a[1]"\t"f; if(!((key SUBSEP fn) in s)){s[key SUBSEP fn]=1; funcs[key]=funcs[key]" "fn}} END{for(k in funcs) print k"\t"funcs[k]}' \
 | sort
