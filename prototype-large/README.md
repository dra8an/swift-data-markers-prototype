# prototype-large: a date formatter with the data design of ICU4X, in Swift and in Rust

Made on 2026-10-23. The small prototype is in `../prototype/` and did not change. Dragan does all git work.

## Start here

1. `RESULTS.md`: the answers, and all numbers.
2. `DESIGN.md`: the scope, the markers, and the decisions.
3. `STATUS.md`: the progress of the run (100% done).

## Folders

| Folder | Content | In git |
|---|---|---|
| `generator/` | `generate.py`: makes the Swift and Rust tables from the JSON of `icu4x-datagen`, and cuts them | yes |
| `swift/Sources/` | The Swift modules `DataMarkers` and `DateTimeFormat` | yes |
| `swift/Sources/DateFormatting/` | The value API in the style of Foundation (`RESULTS.md`, "A value API"). Built only with `VALUE_API=1` | yes |
| `swift/apps/` | `Check`, `GregorianYMD`, `JapaneseYMDT`, `AnyCalendar`, `Bench`, `Baseline`, and for the value API `ValueCheck`, `ValueChinese`, `ValueRuntime`, `ValueBench` (`tools/build-value.sh`) | yes |
| `swift/build.sh`, `swift/build-sizes.sh` | The Swift builds | yes |
| `rust-copy/` | The Rust copy of the Swift design, with the same apps in `src/bin/` | yes, not `target/` |
| `icu4x-apps/` | `reference` (the correctness reference), `chinese-table`, `sizes` (built-in data, and `bench`), `sizes-cut` (cut data) | yes, not `target/` |
| `cases/` | The test locales, the test dates, and the Chinese years | yes |
| `data/` | The generated tables: `full` (all locales) and `cut-ja-<app>` | yes (8 MB) |
| `results/` | Sizes, speed, marker sizes, marker lists | yes, not the check outputs (22 MB each) |
| `tools/` | `compare.py`, `measure.py`, `build-cut.sh`, `build-bench.sh`, `run-bench.sh`, `run-all.sh` | yes |
| `logs/` | The logs of the runs | yes |
| `icu4x-data/` | The JSON output of `icu4x-datagen` (66 MB) | no, make it again |
| `out/` | The build output (685 MB) | no |
| `explore/` | Scratch runs for the design and the tests of `InlineArray` and the crash | no, can be deleted |

## Commands

Run `. ../env.sh` first (from this folder: `. /Users/draganm4/Projects/dra8an/swift-data-markers-prototype/env.sh`).

```
# 1. The source data (DESIGN.md, decision 1)
icu4x-datagen-unstable --cldr-root $CLDR_ROOT --markers $(cat markers.txt) --locales recommended --deduplication maximal --format fs --out icu4x-data/fs-recommended
icu4x-datagen-unstable --cldr-root $CLDR_ROOT --markers LocaleLikelySubtagsLanguageV1 LocaleParentsV1 --locales recommended --format fs --out icu4x-data/fs-fallback

# 2. The ICU4X reference and the Chinese years
(cd icu4x-apps/reference && cargo build --release --offline)
icu4x-apps/reference/target/release/reference cases/locales.txt cases/dates.txt > results/icu4x-reference.tsv
(cd icu4x-apps/chinese-table && cargo build --release --offline)
icu4x-apps/chinese-table/target/release/chinese-table > cases/chinese-years.txt

# 3. The tables (add --replace to write over an earlier run)
python3 -I -B generator/generate.py --fs icu4x-data/fs-recommended --fallback icu4x-data/fs-fallback --out data/full \
  --fallback-swift swift/Sources/DataMarkers/FallbackTables.swift --fallback-rust rust-copy/src/fallback_tables.rs \
  --chinese-table cases/chinese-years.txt --chinese-swift swift/Sources/DateTimeFormat/ChineseYears.swift --chinese-rust rust-copy/src/chinese_years.rs

# 4. Everything else: the checks, the sizes (full and cut for ja), the speed tests
tools/run-all.sh
```

The ICU4X apps with cut data need the marker lists of `--markers-for-bin` and their own data:

```
(cd icu4x-apps/sizes && cargo build --profile markers --offline)     # no LTO, so the marker tags stay
icu4x-datagen-unstable --markers-for-bin icu4x-apps/sizes/target/markers/gregorian_ymd --cldr-root $CLDR_ROOT --tzdb-root $TZDB_ROOT --locales none --format fs --out <new folder>
icu4x-datagen-unstable --cldr-root $CLDR_ROOT --tzdb-root $TZDB_ROOT --markers $(cat results/icu4x-markers-gregorian_ymd.txt) --locales ja --format baked --use-separate-crates --out icu4x-data/cut-ja-gregorian_ymd
(cd icu4x-apps/sizes-cut && ICU4X_CUT_DATA=$PWD/../../icu4x-data/cut-ja-gregorian_ymd/mod.rs cargo build --release --offline --bin gregorian_ymd)
```

## Notes

1. The apps read the locale from `LOCALE`. `Check` reads `LOCALES` and `DATES` (Embedded Swift has no `CommandLine`).
2. Use `python3 -I -B`, so that Python writes no `__pycache__` folder.
3. The settings do not allow deletes. The generator writes over its own output with `--replace` only.
4. Embedded Swift with `-O` crashes (`RESULTS.md`, "Open problems"). The scripts use `-Osize` for Embedded Swift, except the one `-O` bench build that shows the crash.

## Leftovers that Dragan may delete

* `explore/` (122 MB): scratch runs.
* `generator/__pycache__/`: made by one test import.
* `icu4x-apps/sizes/target/markers/` and the other `target/` folders: Cargo build output.
