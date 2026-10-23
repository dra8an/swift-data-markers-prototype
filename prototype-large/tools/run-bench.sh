#!/bin/bash
# Runs every bench app once, one after another. Output: results/bench-<name>.tsv
P=/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/prototype-large
cd $P
for pair in swift-embedded-O:out/bench-O-embedded/Bench swift-normal-O:out/bench-O-normal/Bench swift-normal3-O:out/bench-O-normal3/Bench \
            swift-embedded-Osize:out/full-embedded/Bench swift-normal-Osize:out/full-normal/Bench swift-normal3-Osize:out/full-normal3/Bench \
            rustcopy-opt3:out/bench-rust/rustcopy-speed rustcopy-opts:out/bench-rust/rustcopy-release icu4x-opt3:out/bench-rust/icu4x-speed icu4x-opts:out/bench-rust/icu4x-release; do
    name=${pair%%:*}; bin=${pair##*:}
    start=$(date +%s)
    perl -e 'alarm shift; exec @ARGV' 300 $bin > results/bench-$name.tsv 2>&1
    echo "$name: $(( $(date +%s) - start )) s"
done
echo "ALL DONE"
