# Results of the large data marker prototype

**Date:** 2026-10-23. **Folder:** `prototype-large/`. **Design:** `DESIGN.md`. The small prototype in `prototype/` did not change.

## The answers

| Question | Answer |
|---|---|
| Do complex markers work in Swift? | **Yes.** All 25 markers of ICU4X that a date formatter for 6 calendars needs work: enums with 5 cases, packed patterns with header bits, glue patterns, a singleton, and data keyed by a numbering system. |
| Is the output correct? | **Yes.** Swift (normal and Embedded) and the Rust copy give the same text as ICU4X on **327,888 of 327,888** cases. |
| Data size | **About the same as ICU4X.** The tables are 1.11x the size of the ICU4X data in total. In an app that uses one calendar, the data is 1.07x to 1.10x ICU4X with all locales, and 0.96x to 1.03x ICU4X with one locale. |
| Code size | **Smaller than ICU4X**, if normal Swift uses the 3 flags of the small prototype: 19,736 bytes against 77,416 bytes for a Gregorian formatter. Embedded Swift: 42,120 bytes with LTO. |
| Speed | **A little faster than ICU4X** with `-O` and the 3 flags: 421 ns against 466 ns to make a formatter, 82 ns against 98 ns to format a date. The Rust copy of the same design is 1.3x to 2x faster than Swift. |

Two problems came up on the way:
1. **`.span` on a `static let` `InlineArray` copies the whole array**, each time. Because of it, the first version was 14x slower to make a formatter and 33x slower to format (section "The copy of InlineArray"). This can also be a problem for PR #2330.
2. **The Embedded Swift snapshot crashes with `-O`** in the full prototype (section "Open problems").

## What was built

| Part | Where | Content |
|---|---|---|
| Source data | `icu4x-data/` | The JSON output of `icu4x-datagen` for the 25 markers and the 2 fallback markers, for the locales of the ICU4X built-in data |
| ICU4X reference | `icu4x-apps/reference/` | Formats every test case with ICU4X |
| Generator | `generator/generate.py` | Packs the JSON into the same tables for Swift and for Rust. Also cuts the data by marker, locale and attribute |
| Swift | `swift/Sources/` | 3 modules: `DataMarkers` (core, fallback), `DateTimeFormat` (markers, 6 calendars, 4 field sets, the formatter), `DateTimeData` (generated) |
| Rust copy | `rust-copy/` | The same design in Rust, line for line where Rust allows it |
| Apps | `swift/apps/`, `rust-copy/src/bin/`, `icu4x-apps/sizes/`, `icu4x-apps/sizes-cut/` | `Check`, `GregorianYMD`, `JapaneseYMDT`, `AnyCalendar`, `Bench`, `Baseline` in each implementation |
| Chinese years | `icu4x-apps/chinese-table/` | The Chinese years 1900 to 2100 from `icu_calendar` |

## 1. Correct output

The test formats 15 dates for 396 locales (every locale in the data, `und`, and 3 locales that are not in the data), 6 calendars, the field sets `YMD`, `YMDE` and `YMDT`, the field set `T`, and 3 lengths: 338,580 cases.

| Implementation | Same as ICU4X | Outside the Chinese table | Different |
|---|---:|---:|---:|
| Swift, normal | 327,888 | 10,692 | 0 |
| Swift, Embedded | 327,888 | 10,692 | 0 |
| Rust copy | 327,888 | 10,692 | 0 |

The 10,692 cases are the Chinese dates in the ISO years 1868, 50 and `-99`. The prototype has a table for the Chinese years 1900 to 2100 only (`DESIGN.md`, decision 6).

The cases include the hard parts of ICU4X: Hebrew numerals (`י״ב בחשוון ה׳תשפ״ז`), Hebrew Adar I and Adar II, Chinese leap months, cyclic years, the Japanese eras and Meiji 1 to 5 as CE, the year variants (2 digit year, full year, year with era), the digits of the locale (`ar-EG`), flexible day periods, the parent locales (`en-GB` to `en-001`), the likely scripts (`zh-TW` to `zh-Hant`) and a variant (`el-polyton`).

## 2. Data size

### Each marker

The tables of the generator against the sizes that the ICU4X baked data states (`results/marker-sizes.tsv`). The ICU4X numbers are before the linker merges equal constants.

| Kind of marker | Prototype / ICU4X | Why |
|---|---:|---|
| Month, year and weekday names | 0.87 to 1.07 | The pool stores each text once |
| Date and time patterns | 1.19 to 1.31 | A pattern item is 4 bytes, in ICU4X 3 bytes |
| Chinese month names | 2.01 | 24 names for each value, as 4 byte references |
| Decimal symbols and digits | 1.48 and 1.83 | 4 byte references for short texts |
| **All 25 markers** | **1.11** | 1,020,314 bytes against 923,132 bytes |

### In an app

The `__const` sections, minus the baseline app of each toolchain. "3 flags" is `-Xfrontend -internalize-at-link -Xfrontend -conditional-runtime-records -lto=llvm-full`.

| App | Data | Swift, 3 flags | Swift Embedded | Swift, no flags | Rust copy | ICU4X |
|---|---|---:|---:|---:|---:|---:|
| GregorianYMD | all locales | 268,678 | 267,768 | 1,042,468 | 266,644 | 244,416 |
| JapaneseYMDT | all locales | 266,902 | 266,272 | 1,042,436 | 264,716 | 249,416 |
| AnyCalendar | all locales | 956,838 | 974,888 | 1,042,484 | 898,020 | 802,840 |
| GregorianYMD | `ja` | 12,278 | 11,488 | 19,982 | 10,236 | 12,816 |
| JapaneseYMDT | `ja` | 13,806 | 13,296 | 21,974 | 11,420 | 13,392 |
| AnyCalendar | `ja` | 32,302 | 33,976 | 41,788 | 28,092 | 27,024 |

Notes:
* **Markers in the app.** Swift with the 3 flags, Embedded Swift and the Rust copy keep 5, 9 and 24 markers. Normal Swift with no flags keeps all 25 markers in every app, as in the small prototype.
* **AnyCalendar is not a fair comparison.** The any calendar formatter of ICU4X supports 13 calendars and keeps 43 markers. The prototype supports 6 calendars. ICU4X is still smaller. The likely cause (not checked): LLVM merges equal constants, and the month names of the Gregorian, Buddhist, Japanese and ROC calendars are the same in most locales. The prototype starts each table with the tag of its marker, so no two tables are equal.
* **Cut data.** For the cut data, the generator took the marker list from the tags in the Embedded app, as `--markers-for-bin` does in ICU4X. With LTO, the ICU4X apps have no marker tags left, so `--markers-for-bin` found no markers. A build with no LTO found them.

## 3. Code size

`__text` minus the baseline app of each toolchain (`swift/apps/Baseline`, `rust-copy/src/bin/baseline.rs`). The baseline reads the locale and writes one line. Normal Swift uses the shared Swift library, which this number does not count. Embedded Swift and Rust put the parts of their libraries that they use into the app.

| App | Swift, 3 flags | Swift Embedded | Swift Embedded, LTO | Swift, no flags | Rust copy | ICU4X |
|---|---:|---:|---:|---:|---:|---:|
| GregorianYMD | 19,736 | 67,932 | 42,120 | 59,972 | 17,728 | 77,416 |
| JapaneseYMDT | 20,732 | 72,404 | 44,704 | 61,696 | 20,288 | 80,488 |
| AnyCalendar | 37,020 | 94,208 | 71,216 | 85,972 | 55,040 | 103,272 |

The baselines: Swift 720 bytes (3 flags) and 956 bytes (no flags), Embedded Swift 12,752 bytes, Rust 190,328 bytes.

ICU4X has more code because it does more: a general pattern model, parts for the output, more options (hour cycle, alignment, year style), error values, and 13 calendars in the any calendar formatter.

## 4. Speed

Median of 5 runs, in nanoseconds for one operation (`results/bench-summary.tsv`). "new" parses the locale and loads the data for 10 locales. "format" formats 12 dates into a new buffer, and includes the conversion from ISO to the calendar.

| Test | Swift, 3 flags, `-O` | Swift, `-O` | Swift Embedded, `-Osize` | Swift, 3 flags, `-Osize` | Rust copy, opt 3 | ICU4X, opt 3 | ICU4X, opt s |
|---|---:|---:|---:|---:|---:|---:|---:|
| new, Gregorian YMD | 421 | 611 | 551 | 557 | 216 | 466 | 544 |
| new, Japanese YMDT | 591 | 633 | 754 | 744 | 326 | 685 | 788 |
| format, Gregorian YMD, `en` | 82 | 93 | 154 | 174 | 49 | 98 | 132 |
| format, Gregorian YMDT, `en` | 113 | 146 | 238 | 301 | 80 | 184 | 232 |
| format, Japanese YMDT, `ja` | 116 | 157 | 235 | 274 | 88 | 180 | 224 |
| format, Hebrew YMD, `he` | 106 | 117 | 173 | 204 | 74 | 142 | 182 |
| format, Chinese YMD, `zh` | 79 | 89 | 119 | 140 | 39 | 142 | 162 |
| format, Gregorian YMD, `ar-EG` | 84 | 99 | 168 | 190 | 51 | 127 | 163 |

Notes:
* Swift with `-O` and the 3 flags is faster than ICU4X in all 8 tests, by 1.1x to 1.8x.
* The Rust copy runs the same algorithm 1.3x to 2x faster than Swift. The difference is the language and the compiler, for example the checks of `Span` and `Array` indexes and the closure calls of `withTables`. This prototype did not try to remove them.
* `-Osize` makes Swift about 2x slower. `opt-level = "s"` makes Rust only about 1.2x slower.
* Embedded Swift with `-O` crashes (section "Open problems"), so the table shows Embedded Swift with `-Osize`.

## The copy of InlineArray

The first version stored the tables as `static let` `InlineArray` constants, as the small prototype and PR #2330 do. It was very slow: with `-O` and the 3 flags, 6,074 ns to make a formatter and 2,681 ns to format a date. A profile with `sample` showed that 98% of the time was `outlined init with copy of InlineArray<5719, UInt32>`: Swift copied the whole table to the stack each time the code took its `Span`.

A small test (`explore/copytest/`) with a table of 20,000 `UInt32` gave the same result in normal and in Embedded Swift:

| How the code reads one element | Time for one read |
|---|---:|
| `static let` `InlineArray`, `.span` in the app | 1,057 ns |
| `static let` `InlineArray`, `.span` in its own module | 897 ns |
| `static let` `InlineArray`, subscript in its own module | 0 ns |
| `static let` `Array` literal, `.span` | 0 ns |
| `nonisolated(unsafe) static var` `InlineArray`, `withUnsafePointer` | 0 ns |

The fix was `static let` `Array` literals. The compiler puts them in `__DATA_CONST`, read only, with no copy. After the fix, the same formatter took 421 ns and 82 ns. The data size did not change.

**For PR #2330:** check if its code takes `.span` of its `static let` `InlineArray` tables, or passes them by value. A subscript in the same module is safe.

## Complex markers: Swift and Rust

| Topic | Swift | Rust copy | ICU4X |
|---|---|---|---|
| A marker | an `enum` with no cases | an `enum` with no variants | a unit struct |
| Data of a marker | `extension M: @retroactive BakedDataMarker` in a separate module | `impl BakedDataMarker for M` in the same crate | `impl DataProvider<M> for Baked` in the data crate |
| Why | a module can conform a type of another module | the orphan rule: the data must be in the crate of the trait or of the type, so the crate includes `data.rs` | the data crate has its own type `Baked` |
| A field set names its markers | associated types, `NeverMarker` for unused data | the same | the same (`NeverMarker`) |
| Enum data (month names with 5 cases) | words in a table, decoded by a `switch` | the same | `VarZeroVec` of Rust enums, zero copy |
| Tables | `static let` `Array` literals (not `InlineArray`) | `static` arrays | `static` structs with references |
| Missing marker in cut data | compile error (shown in the small prototype) | compile error (a trait bound) | not tested here |
| Experimental features needed | none (a struct of `Span` values would need `Lifetimes`, so `withTables` passes 5 spans) | none | none |

## Open problems

1. **Embedded Swift with `-O` crashes.** The snapshot `swift-DEVELOPMENT-SNAPSHOT-2026-06-24-a` builds the Bench app, but it stops at once with `EXC_BAD_ACCESS` in `merged one-time initialization function for pool`. The function writes to a table in `__DATA_CONST`, which is read only. `-Osize` works. Three small tests did not show the crash (`explore/embedded-O-crash/`). To show it: `OPT=-O swift/build.sh embedded data/full Bench out/bench-O-embedded`, then run `out/bench-O-embedded/Bench`.
2. **The Chinese table.** The prototype supports the Chinese years 1900 to 2100 only. ICU4X computes the other years.
3. **Normal Swift needs 3 frontend flags** to remove unused markers, as in the small prototype. They fit an app, not a framework.
4. **Not supported:** the `-u-nu-` and `-u-hc-` keywords, time zones, more than one variant subtag, and the hour cycle option. The test does not use them.

## How to repeat the runs

```
cd /Users/draganm4/Projects/dra8an/swift-data-markers-prototype && . ./env.sh && cd prototype-large
tools/run-all.sh                      # builds and runs the checks, the sizes and the speed tests
python3 -I -B tools/compare.py results/icu4x-reference.tsv results/swift-normal-check.tsv
python3 -I -B tools/measure.py data/full/markers.json out/full-normal3/GregorianYMD
```

`README.md` lists all commands, also the ones that make the source data and the ICU4X apps.
