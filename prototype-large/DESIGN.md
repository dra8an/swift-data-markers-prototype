# Design of the large data marker prototype

**Started:** 2026-10-23. **Folder:** `prototype-large/`. The small prototype in `prototype/` stays as it is.

## Goal

Compare Swift with Rust on a real date formatter that uses the data design of ICU4X. Measure four things:

1. **Data size:** the bytes of locale data in an app.
2. **Code size:** the bytes of machine code in an app.
3. **Speed:** the time to make a formatter (load the data), and the time to format one date.
4. **Correct output with complex markers:** markers whose data is an enum, a packed set of patterns, or a map.

## The three implementations

| Name | Language | What it is |
|---|---|---|
| **ICU4X** | Rust | The real crates `icu_datetime` and `icu_calendar` at commit `7473560788`, with their built-in data or with data from `icu4x-datagen`. |
| **Swift** | Swift | This prototype: markers, tables and a formatter in Swift. Built in Embedded Swift and in normal Swift. |
| **Rust copy** | Rust | The same design as the Swift code, line for line: the same tables, the same lookup, the same formatter. It shows the language difference apart from the library difference. |

## Scope

| | Scope |
|---|---|
| Calendars | Gregorian, Buddhist, Japanese, Hebrew, Chinese, Hijri (tabular, the civil epoch) |
| Field sets | `YMD` (year, month, day), `YMDE` (with the weekday), `T` (hour and minute), and `YMD` with `T` |
| Lengths | long, medium, short |
| Year style | `Auto`, as in ICU4X (a 2 digit year, the full year, or the year with the era, by the ambiguity of the year) |
| Numbers | the numbering system of the locale, from the decimal symbols and the digits |
| Locales | the same set as the built-in data of ICU4X |

## The markers

The markers are the markers of ICU4X, with the same names, the same attributes and the same content. 25 markers in all:

| Kind | For each calendar (6 x 3) | Shared |
|---|---|---|
| Names | `DatetimeNamesMonth<Cal>V1`, `DatetimeNamesYear<Cal>V1` | `DatetimeNamesWeekdayV1`, `DatetimeNamesDayperiodV1` |
| Patterns | `DatetimePatternsDate<Cal>V1` | `DatetimePatternsTimeV1`, `DatetimePatternsGlueV1` |
| Calendar data | | `CalendarJapaneseModernV1` (the dates of the eras) |
| Numbers | | `DecimalSymbolsV1`, `DecimalDigitsV1` |

`<Cal>` is `Gregorian`, `Buddhist`, `Japanese`, `Hebrew`, `Chinese` and `Hijri`.

## Why these markers are complex

| Marker | Shape of the data |
|---|---|
| Month names | an enum: `Linear` (a list), `LeapLinear` (a list with leap months, Hebrew and Chinese), `LeapNumeric` (a pattern such as "闰{0}") |
| Year names | an enum: `FixedEras` (a list), `VariableEras` (a map from era code to name, Japanese), `Cyclic` (60 names, Chinese) |
| Date and time patterns | packed patterns: a header of bits, and up to 9 patterns for 3 lengths and 3 variants |
| Decimal symbols | a struct with strings, numbers and the name of a numbering system, which picks the key of the digits |
| Japanese eras | a singleton (no locale): a list of start dates and era codes |

## Decision 1: one source of data for all three

The Swift generator does not read CLDR. It reads the JSON output of `icu4x-datagen` (`--format fs`). So the three implementations use the same data, and the output of each must be the same text. This is the test for decision 7.

## Decision 2: one generator, two outputs

`generator/generate.py` packs the data of each marker into byte tables once. Then it writes these tables as Swift (`InlineArray` constants, as in `prototype/`) and as Rust (`static` arrays) for the Rust copy. So the Swift and the Rust copy hold the same bytes.

## Decision 3: the calendar picks the markers by type

As in `prototype/`: a calendar type names its markers as associated types. A formatter for one calendar (like `FixedCalendarDateTimeFormatter` in ICU4X) uses only the markers of that calendar. A formatter for any calendar (like `DateTimeFormatter` in ICU4X) picks the calendar at run time and so keeps the markers of all 6 calendars. Both are measured.

## Decision 4: data stays in the tables

The small prototype copied the names into `String` values on each lookup. Here a lookup returns a small value (the marker type and the offsets into the tables). The formatter reads the bytes from the tables when it formats, as ICU4X reads from its static data.

## Decision 5: the fallback

The same as `prototype/` (remove the last subtag, then `und`), plus the parent locales of CLDR, written by the generator as a table. `icu4x-datagen` runs with `--deduplication maximal`, and the fallback must find the same data as the fallback of ICU4X. The test of decision 7 shows if it does not.

## Decision 6: calendar arithmetic

The prototype is about data, but the speed test includes the conversion of a date. So each implementation converts an ISO date to the calendar:

| Calendar | Swift and the Rust copy |
|---|---|
| Gregorian, Buddhist | arithmetic |
| Japanese | Gregorian, plus the era dates of `CalendarJapaneseModernV1` |
| Hebrew | arithmetic |
| Hijri (tabular) | arithmetic |
| Chinese | a table of years from 1900 to 2100, made with `icu_calendar` by a small Rust tool. Outside these years the formatter returns nil. |

## Decision 7: the correctness test

A Rust tool formats a fixed list of dates with ICU4X for every locale, calendar, field set and length, and writes the results to a file. The Swift app and the Rust copy format the same list. A script compares the three files. Every difference is a bug, or a limit that the results must list.

## Decision 8: the apps

| App | Uses | Like in ICU4X |
|---|---|---|
| `GregorianYMD` | Gregorian, `YMD`, medium | `FixedCalendarDateTimeFormatter<Gregorian, YMD>` |
| `JapaneseYMDT` | Japanese, `YMD` with `T`, long | `FixedCalendarDateTimeFormatter<Japanese, YMDT>` |
| `AnyCalendar` | the calendar of the locale, picked at run time, `YMD` with `T` | `DateTimeFormatter<YMDT>` |
| `Check` | everything, for decision 7 | the Rust tool of decision 7 |
| `Bench` | everything, for the speed test | |

Each app exists in the three implementations. Each is built with the data of all locales and with data cut for one locale.

## Decision 9: the measurements

* **Size:** `size -m` of the app, as in `prototype/tools/measure.py`: code (`__text`), data (`__const`), and the total without `__LINKEDIT`. Also the bytes of each marker, from the symbols.
* **Speed:** a bench app times two things for a list of locales: (1) make the formatter, (2) format one date. Each is a loop of many runs with the monotonic clock, after a warm up. The result is the median of 5 runs.
* **Builds:** Swift with `-Osize` (as in `prototype/`) and with `-O`. Rust with `opt-level = "s"` and `opt-level = 3`, and `lto = true`, `codegen-units = 1`, `panic = "abort"`.

## Decision 10: field sets and calendars name their markers

As ICU4X does with its field sets, each field set (`YMD`, `YMDE`, `T`, `YMDT`) names its markers as associated types. A field set that does not use a kind of data names `NeverMarker`, which has no tables. So the formatter for `YMD` refers to no weekday, day period, time or glue data, and the linker can remove it.

The generated data module conforms a calendar to `BakedCalendar` and a field set to `BakedFieldSet` only if all their markers are in the data. If an app uses a calendar or a field set whose data was cut away, it does not compile.

## Decision 11: one table layout for all markers

Each marker has 5 tables:

| Table | Content |
|---|---|
| `pool` | The tag of the marker (`dmk1` and a hash, as in `prototype/`), then the UTF-8 text of all keys and values, each text once |
| `keys` | The keys (locale, `0x1E`, attribute), sorted by bytes, as `offset << 8 | length` into `pool` |
| `keyValues` | For each key, the number of its value |
| `valueStarts` | Where each value starts in `words` |
| `words` | The values, as 32 bit words: a kind, counts, numbers, and texts as `offset << 8 | length` |

A pattern is a count and items. An item is a text, or a field with bit 31 set: the symbol letter and the field length. The generator parses the patterns, as ICU4X does. The fallback tables (likely subtags and parent locales) are in the core module, as the compiled fallback data of ICU4X is in `icu_locale`.

All tables are `static let` `Array` literals, not `InlineArray`. `.span` on a `static let` `InlineArray` copies the whole array (`RESULTS.md`, "The copy of InlineArray").

## Folders

| Folder | Content |
|---|---|
| `explore/` | scratch runs of `icu4x-datagen` for the design |
| `icu4x-data/` | the JSON data from `icu4x-datagen`, the source for the generator |
| `generator/` | `generate.py` |
| `swift/` | the Swift modules and apps |
| `rust-copy/` | the Rust copy |
| `icu4x-apps/` | the Rust apps that use ICU4X |
| `data/` | the generated tables, one folder for each data set |
| `out/` | the build output |
| `results/` | the measurements and the comparison files |
