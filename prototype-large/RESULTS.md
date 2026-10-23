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

## A value API in the style of Foundation

Foundation must keep its API: the calendar, the format and the locale are values chosen at run time, not types. So a second test put the typed formatter behind a value API (`swift/Sources/DateFormatting/`): `Calendar(identifier: .chinese)` and `DateFormatStyle(date:time:locale:calendar:)`, with `date` as `.numeric`, `.abbreviated`, `.long` or `.complete`, and `time` as `.omitted` or `.shortened`. The module imports the data, as Foundation would contain its data. It switches on the values, and uses `FixedCalendarFormatter` inside. Its functions are not inlinable. Added on 2026-10-23, after the first results.

| Question | Result |
|---|---|
| Correct output | The same text as ICU4X on **247,104 of 247,104** cases that the styles can express (`ValueCheck`, `tools/compare.py --keyed`). 8,316 more cases are outside the Chinese table. |
| Markers in an app | **All 25**, in every build: Embedded, Embedded with LTO, normal Swift with and without the 3 flags. This is also true if the calendar is the constant `.chinese` (`ValueChinese`), because the switch refers to all 6 calendars. |
| Data with all locales | 1,008,104 to 1,044,360 bytes, against 268,678 bytes for one typed calendar |
| Data cut for `fr` (all markers) | 40,088 bytes (normal Swift, 3 flags). The app still works. A cut locale falls back to `und`. |
| Code | 51,428 bytes (3 flags) and 296,020 bytes (Embedded) for `ValueChinese`. Embedded Swift specializes all 24 combinations of calendar and field set. |

Speed, in ns for one operation (`results/bench-value-summary.tsv`):

| Test | Typed, 3 flags, `-O` | Value API, 3 flags, `-O` | Typed, Embedded, `-Osize` | Value API, Embedded, `-Osize` |
|---|---:|---:|---:|---:|
| new, Gregorian YMD | 421 | 423 | 551 | 570 |
| new, Japanese YMDT | 591 | 651 | 754 | 815 |
| format, Gregorian YMD, `en` | 82 | 91 | 154 | 227 |
| format, Gregorian YMDT, `en` | 113 | 128 | 238 | 327 |
| format, Japanese YMDT, `ja` | 116 | 138 | 235 | 315 |
| format, Hebrew YMD, `he` | 106 | 118 | 173 | 231 |
| format, Chinese YMD, `zh` | 79 | 97 | 119 | 125 |
| format, Gregorian YMD, `ar-EG` | 84 | 95 | 168 | 242 |
| `style.format`, a new formatter each time | | 462 | | 705 |

What this means:
* The data design works behind a value API, with the same output.
* The automatic cut by marker is lost: a value API keeps the data of every calendar and field set that it can reach. Only a cut at build time (`--markers`, `--locales`) makes the data smaller.
* If the build cuts the markers of a calendar, the value API module does not compile, because it names all 6 calendars. To make such a cut give an error at run time instead, the generator would have to write empty tables for the cut markers. This is not built.

## Limits of the automatic cut, and ways around them

Written on 2026-10-23, after a talk with Dragan. Nothing in this section is built, except where it says "tested".

### What the build can remove by itself

| Kind of data | Removed automatically? | Why |
|---|---|---|
| Markers, with a typed API (`FixedCalendarFormatter<Chinese, YMD>`) | **Yes** (Embedded Swift, or normal Swift with the 3 flags). Tested. | The calendar and the field set are types. The code refers only to their tables, and the linker removes the rest. |
| Markers, with a value API (`Calendar(identifier:)`, `DateFormatStyle`) | **No.** Tested. | See below. |
| Locales | **No**, with any API. Tested in ICU4X too. | All locales of a marker are in one table. The lookup happens at run time. |
| Attributes (widths, lengths) | **No.** | The code picks them at run time from the pattern and the style. |

### Why a value API keeps all calendars

The linker starts at `main` and keeps all code and data that any reachable code refers to. It does not know which code runs.

A value API must turn a run time value into a calendar. Any code that does this must be ready for every calendar, so it refers to the tables of every calendar: a `switch`, a dictionary of functions, an array of formatters, or `any CalendarSystem`. The switch is only where the problem shows. The cause is the run time value. The same is true for the date and time styles, so the value API also keeps all field sets.

A constant such as `Calendar(identifier: .chinese)` did not help in the test, even with LTO. The switch is in a function of another module that is not inlinable. ICU4X has the same limit: its any calendar formatter kept 43 markers.

Foundation must keep its value API (Dragan, 2026-10-23), so this limit applies to Foundation.

### Ways around it

1. **Cut at build time with the generator (works now, tested).** The developer gives `--markers`, `--locales` and `--attributes`. The marker list can come from the built app (`tools/build-cut.sh`), but only for a typed API. For a value API, the developer must give it.
2. **A build setting, such as a package trait.** For example, a trait for each calendar. A calendar that the trait leaves out is not in the switch, so its code and its data are not in the build.
3. **The app registers its calendars.** For example `DateFormatting.register(Chinese.self)`. The value API reaches only registered calendars, so only their data stays. A calendar that is not registered gives an error at run time.
4. **An inlinable value API.** The app's compiler could then remove the dead cases of the switch, but only if the calendar is a constant in the code. If the calendar comes from the user's settings, every case can run, so this cannot help.
5. **The locale as a type** (`FixedCalendarFormatter<Chinese, YMD, French>`, with one symbol for each locale of each marker). The linker could then remove unused locales. This needs a typed API, so it does not fit Foundation. ICU4X does not have it either.
6. **The locale list of the app.** An Apple app lists its locales in its `.lproj` folders or in `CFBundleLocalizations`. A SwiftPM build plugin could pass this list to `--locales`, and the marker list of way 1, with no manual step.

### Slicing with the generator: what to know

The generator slices correctly, with any API:
* `--markers` keeps only those markers. With the typed API, the data module then declares only the calendars and field sets whose markers are all there.
* `--locales` keeps each listed locale and every locale that its lookup can try (the fallback of ICU4X: for example `fr-CA`, `fr`, `und`).
* `--attributes` keeps only the listed widths and lengths.

Four cautions:
1. **A value API and a cut calendar.** The value API names all 6 calendars, so the build fails if the data has no markers for one of them. To make the build work and give an error at run time instead, the generator would have to write empty tables for the cut markers (not built). Ways 2 and 3 above avoid this.
2. **A cut locale gives no error.** It falls back to `und`, for example `2026 M09 14` for `ja` in the `fr` data. The text is correct root data, but not in the language of the user. The locale list must have every locale that the app can get.
3. **Attributes with a value API.** The styles pick the widths at run time, so a cut by attribute can remove a width that the app needs. Then the formatter cannot be made (`nil`). Cut attributes only if the app uses fixed styles.
4. **The marker list for a value API.** `tools/build-cut.sh` reads the markers from the built app. With a value API, it finds all 25, so the list must come from the developer.

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
