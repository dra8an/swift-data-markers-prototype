# Foundation's date data architecture (PR #2330)

**Written:** 2026-10-27. **Source:** PR #2330, "Format date patterns in Swift", by Chris Chapman, head `80ebeafa3d` (checked on 2026-10-27, last change 2026-10-21). **Toolchain for my measures:** Apple Swift 6.5 (swiftlang-6.5.0.12.6), arm64 macOS 27.

This document starts from Foundation's own code and data. It does not use ICU4X. It answers the 5 questions of the handoff of 2026-10-27, in their order.

## Summary

1. #2330 moves one step to Swift: it fills a date pattern with names and digits. ICU still selects the pattern (`ICUPatternGenerator`). Parsing, intervals, relative dates and calendar symbols stay on ICU.
2. The data is Gregorian only. It has 8 groups of values for 1,071 locales. The build tool resolves every locale fully and stores identical data once. At run time there is no walk through parent locales for values.
3. For all locales, the tables are 198 KB, and the object file with the lookup code is 225 KB. (The 352 KB in the PR text is the first layout of the PR, see section 4.) For about 40 locales the tables are 28 KB. For `en_US` they are 3.4 KB. The code is about 21 KB in every case.
4. Today the cut is by locale, at build time, with a list (`--locales`). The code does not drive the cut.
5. The largest part is not in #2330: the patterns. ICU still holds them. Their size and shape will decide more than the names do.

## 1. What data each date API reads

### Which APIs use the Swift path

The Swift path is on only when the build sets `FOUNDATION_DATE_FORMAT_SWIFT`. No build file sets it (not `Package.swift`, not CMake).

| API | Pattern from | Filled in by | Data |
|---|---|---|---|
| `Date.FormatStyle.format` | ICU (`ICUPatternGenerator.localizedPattern`) | Swift, with the flag | `_DateFormatData` |
| `Date.VerbatimFormatStyle.format` | the caller | Swift, with the flag | `_DateFormatData` |
| The attributed forms of both | as above | Swift, with the flag | `_DateFormatData` |
| Parsing (`Date.ParseStrategy`, `FormatStyle.parse`) | ICU | ICU | ICU |
| `Date.IntervalFormatStyle` | ICU | ICU | ICU |
| `Date.RelativeFormatStyle`, anchored relative | ICU | ICU | ICU |
| `Calendar.monthSymbols` and the other symbols (`Calendar_ICU.swift:2046`) | none | ICU | ICU |
| The hour cycle of a locale (`Locale_ICU.swift:1158`) | ICU pattern generator | ICU | ICU |

#2330 does not change the files of the ICU rows. Their line numbers come from the worktree `swift-foundation-seven`, not from the PR head.

On Darwin, `Date.FormatStyle` also applies the user's custom date format (`customDateFormat`) to the pattern from ICU. This happens before the Swift step.

### What one pattern field reads

`DatePatternFormatter.swift` walks the pattern once. Each field reads these values:

| Field | Data from the tables | Other input |
|---|---|---|
| `G` | era name, 3 widths | `Calendar` era |
| `M`, `L` (3 to 5 letters) | month name, 2 contexts, 3 widths | `Calendar` month |
| `E`, `e`, `c` (3 to 6 letters) | weekday name, 2 contexts, 4 widths | `Calendar` weekday |
| `Q`, `q` (3 to 5 letters) | quarter name, 2 contexts, 3 widths | month |
| `a`, `b` | AM, PM, noon, 3 widths | hour |
| `O`, `ZZZZ` | `gmtFormat`, `hourFormat` | time zone offset |
| `d` with `numbers=hanidays` | 31 Chinese day numerals | day |
| all numbers | digits of the numbering system, minus sign | `numbers`, `rg` keywords |
| the first field, or text before it | capitalization flags (10 usages) | capitalization context |
| `y`, `Y`, `u`, `D`, `F`, `w`, `W`, `H`, `h`, `k`, `K`, `m`, `s`, `S`, `A`, `g`, `X`, `x`, `Z` (1 to 3, 5), `VV` | none (digits only) | `Calendar`, `TimeZone` |

Not supported: `z`, `v`, `B`, `V` other than `VV`, and `ddd` or longer. They write the letters and `_IS_UNSUPPORTED`. Calendars other than Gregorian and ISO 8601 write `<calendar>_CALENDAR_IS_UNSUPPORTED` for the whole output.

### What is fixed at build time, and what at run time

| Build time | Run time (values) |
|---|---|
| the flag `FOUNDATION_DATE_FORMAT_SWIFT` | the locale identifier, with `numbers` and `rg` |
| the list of locales (`--locales`) | the calendar identifier |
| the fallback locale (`--fallback`) | the pattern (from ICU, or from the caller) |
| the groups and the calendar (Gregorian), fixed in the tool | the time zone, first weekday, capitalization context |

All the run time inputs are values. Any pattern can need any group. So the linker cannot remove one group, even with full LTO. This agrees with fact 3 of the handoff.

## 2. How the data is made

### The pipeline

```
CLDR 48 XML
  └ utils/update-date-format-data (CLDR_PATH)        stage 1
      → DateFormatData.json, 1,154,551 bytes
  └ utils/build-date-format-data [--locales] [--fallback]   stage 2
      → DateFormatData.swift, 953,116 bytes, 9,019 lines
```

Both stages compile 3 files into one tool: the schema (`date-format-data-schema.swift`), the shared CLDR fallback (`cldr-locale-fallback.swift`) and their own `-impl.swift`. The list data tools use the same fallback file.

### Stage 1: from CLDR to resolved blocks

* **Locales.** A hand list (`icuLocaleIDs`) copies the `<localeIds>` of Apple ICU's `cldr-to-icu/config.xml`. The tool expands it as `cldr-to-icu` does. The result is 1,071 locales, with root.
* **Aliases.** A hand list of 61 aliases, such as `iw` to `he` and `zh_HK` to `zh_Hant_HK`. It comes from the `%%ALIAS` entries of Apple ICU.
* **Parents.** The CLDR `<parentLocales>` block without a `component`, else the locale without its last subtag, else root.
* **Values.** The tool skips `draft="unconfirmed"` and `"provisional"`, `alt` values, and the `↑↑↑` and `∅∅∅` markers, as ICU's data build does.
* **Root aliases.** When no locale in the chain has a name, the tool applies the width and context aliases of root (for example stand-alone abbreviated months use the format ones). Then it searches again from the original locale.
* **Numbers.** `native`, `traditional` and `finance` fall back as ICU's `NumberingSystem` does. A numbering system without its own minus sign uses the Latin one.
* **Checks.** The tool compares 14 known values (for example `de_AT` January is "Jänner"). It stops if one is wrong.

The result is fully resolved: every locale has a value for every slot. Then the tool stores each distinct block of a group once:

| Group | Slots | Distinct blocks (1,071 locales) |
|---|---:|---:|
| `numbers` | 7 | 54 |
| `months` | 72 | 284 |
| `weekdays` | 56 | 292 |
| `quarters` | 24 | 224 |
| `eras` | 6 | 231 |
| `dayPeriods` | 9 | 219 |
| `gmt` | 2 | 42 |
| `capitalization` | 10 | 7 |

Only 332 locales have a different combination of the 8 blocks.

### Stage 2: from JSON to Swift tables ("layout E")

* **Strings.** Each string is a 4 byte entry: 1 length byte and 3 bytes. Text of 3 UTF-8 bytes or fewer sits in those bytes. Longer text sits in one shared pool, and the 3 bytes hold its offset. A string inside a longer string shares its bytes ("Sept" inside "September").
* **Sub-blocks.** The tool splits each block into one sub-block per context and width (for example the abbreviated format months). It stores identical sub-blocks once.
* **Rows.** Each locale has a row of 29 sub-block starts. The tool stores identical rows once.
* **Order.** Sub-blocks and pool text are in the order that locales first use them. So the data of one locale sits together.
* **Redirects.** The tool keeps an alias or a parent only if it changes the result for the cut. It adds redirects for ICU's script fallback (for example `en_Latn_GB` to `en_GB`). It then checks that every probe identifier gets the same data as ICU would. If not, it stops.
* **Output.** All tables are `internal static let` values of type `InlineArray`.

So the data is deduplicated at 4 levels: block, sub-block, row and text.

## 3. How the data is read at run time

1. `DataLocaleIdentifier` reads the identifier once. It makes the case canonical (`zh_Hant_TW`), and it reads `numbers`, `rg`, `-u-nu-` and `-u-rg-`.
2. `DateFormatLocale.index(for:)` does a binary search in `localeIDs`. If it does not find the identifier, it follows a redirect, else it drops the last subtag. If the language has no data, it uses the fallback locale, else root.
3. The locale keeps the start of its row. Each value is 2 table reads: `rows[row + group + subBlock]`, then `names[start + slot]`.
4. The entry gives the text, inline or from the pool.
5. For numbers, the code finds the numbering system from the language, script and region (or the `rg` region). It computes each digit from the UTF-8 of zero, so it stores no digit tables for most systems.
6. `FormatterCache` keeps one `DatePatternFormatter` for each `DateFormatInfo`.

**The `.span` copy (fact 1 of the handoff).** #2330 at this head avoids it on purpose. The lookup reads the large tables with subscripts. A comment at `DateFormatLookup.swift:86` says why, and `withUTF8` at line 56 copies short pool text into a 16 byte buffer. So this point is closed for #2330.

## 4. The constraints

### Size

I compiled the 3 data files (`DateFormatData.swift`, `DateFormatLookup.swift`, `DataLocaleIdentifier.swift`) into one object with `swiftc -O -wmo`, and read it with `size -m`.

| Cut | Locales | Tables (tool) | `__TEXT,__const` | `__TEXT,__text` | Object total | Swift source |
|---|---:|---:|---:|---:|---:|---:|
| all | 1,071 | 197,340 | 198,384 | 20,972 | 224,992 | 953,116 |
| about 40 (my list, see below) | 41 | 27,211 | 28,264 | 20,844 | 54,752 | 129,510 |
| `de`, `fr`, `ja`, `zh`, `es` | 6 | 5,013 | 6,056 | 21,048 | 32,752 | 25,475 |
| `en_US` | 2 | 2,338 | 3,384 | 20,328 | 29,360 | 13,187 |

All values are bytes. Root is always in the cut. The full cut gives the same file as the one in the PR, byte for byte.

* My list of 40 locales is a guess at the Apple list: `ar ca cs da de el en en_AU en_GB en_IN es es_419 fi fr fr_CA he hi hr hu id it ja ko ms nb nl pl pt pt_PT ro ru sk sv th tr uk vi zh zh_Hant zh_Hant_HK`. T is checking the real list.
* Each extra locale adds about 0.6 KB of tables.
* With 1 to 5 locales, the code (21 KB) is larger than the data.

**The PR text gives older sizes.** The PR text gives 352,272 bytes in total for all locales. That is the first layout of the PR, not the head. Chris wrote the PR text on 2026-10-14 and never edited it. The table file changed in 2 commits only: `9dda818323` (2026-10-14, the first commit) and `ddf23b0dad` ("Pack the date-format data more efficiently", 2026-10-15). I compiled the files of both versions in the same way:

| | PR text | `9dda818323` (first layout) | `80ebeafa3d` (head, layout E) |
|---|---:|---:|---:|
| `__TEXT,__const` | 326,048 | 326,064 | 198,384 |
| `__DATA,__const` | 880 | 880 | 1,016 |
| `__TEXT,__text` | 20,592 | 20,484 | 20,972 |
| Object total | 352,272 | 352,208 | 224,992 |

The first layout matches the PR text to within about 100 bytes. The small rest is probably the toolchain. The first layout had 46,065 string entries and a pool of 113,871 bytes. Layout E has 17,979 entries and a pool of 97,066 bytes, because it stores identical sub-blocks once. So "about 350 KB" from the meeting is the old size. At the head, all locales take about 225 KB.

Chris gave the new size in a PR comment on 2026-10-15 ([comment 6201582272](https://github.com/swiftlang/swift-foundation/pull/2330#issuecomment-6201582272)): "the data and lookup code for all locales went from 352,272 to 225,536 bytes", with 198,336 bytes of `__TEXT,__const`. My measure (224,992 and 198,384) agrees. So about 198 KB of tables is the expected size. His "about 35 KB" for `en_US`, `es_US` and root (35,856 bytes, [comment 6181793794](https://github.com/swiftlang/swift-foundation/pull/2330#issuecomment-6181793794)) is also from the first layout.

### The share of each group (all locales)

| Group | Share of the data |
|---|---:|
| `months` | 43% |
| `weekdays` | 28% |
| `quarters` | 15% |
| `eras` | 8% |
| `dayPeriods` | 5% |
| `numbers`, `gmt`, `capitalization` | 2% |

This is an estimate: the sub-block entries and the long text of each group, before the pool shares text across groups.

### Memory

* The tables are in `__TEXT,__const`. These pages are read only and clean.
* `__DATA,__const` is 1,016 bytes, and `__DATA,__bss` is 1,536 bytes. These do not grow with the locales.
* So the tables need no relocations at launch. A `static let` `Array` would need them (fact 1 of the handoff).

### Source size and compile time

The full table file (953 KB of source) compiled in about 3 seconds here. At this size, source size is not a constraint. Chris's concern is about formats that make much more source.

### Darwin and Embedded

* Darwin and Embedded use the same source and the same tables. There is one pipeline.
* No build file sets the flag. So CI does not build or test the Swift path. (Our review of 2026-10-15 found this too.)
* I did not build the data with Embedded Swift for this document.

### Failure behavior

| Case | Result |
|---|---|
| A locale that is not in the cut | silent fallback, to the `--fallback` locale or root |
| A calendar other than Gregorian or ISO 8601 | the whole output is `<calendar>_CALENDAR_IS_UNSUPPORTED` |
| A field that is not supported | the field is its letters and `_IS_UNSUPPORTED` |
| A cut that cannot give ICU's result | the build tool stops |

**Example of the last case.** `--locales=zh_Hans` without `zh` stops the tool: "zh_AA needs a redirect for every region" (`cldr-locale-fallback.swift:324`). With `zh` added, the cut works. The tool built with `-O` stops with exit code 133 and prints no message. Only a debug build prints the message.

## 5. The right unit for a cut (a first view, for discussion)

**What the code and data tell us:**

* **Locale.** This is the unit today. The data grows about 0.6 KB per locale. The row deduplication works well (1,071 locales, 332 rows).
* **Group (months, weekdays and so on).** All 8 groups of a locale sit in one row. The pattern is a run time value, so a build cannot know which groups it needs. One locale is 3.4 KB in total, so a cut by group saves at most a few KB per locale. A cut finer than a locale is not worth it here. This agrees with the meeting of 2026-10-27.
* **Calendar.** Only Gregorian is in the data now. Foundation has 27 calendar identifiers. Each new calendar adds mostly months and eras, the largest groups. Many calendars use the Gregorian month names (fact 6 of the handoff), so the generator can store them once. `Calendar.Identifier` is a run time value, so a build must name its calendars in a list, as it names its locales.
* **Feature.** The date data and the list data are already separate tables with separate tools. So a cut by feature exists in practice.

**A proposal for discussion:** a cut by feature, calendar and locale, each chosen at build time with a list. Do not cut single fields.

**The bigger question that #2330 does not answer:** the pattern data. ICU selects the pattern from a skeleton, with its own data for date formats, time formats, combined formats and skeletons. This data is not in Swift yet. Its size and its shape will decide the architecture more than the names do. T's statistics on unique date patterns feed into this.

## 6. Open points

1. Closed on 2026-10-27: the size in the PR text is from the first layout (section 4). The PR text is out of date. Chris can update it.
2. The trap for a `zh_Hans` cut without `zh`. Is it intended that the tool refuses such a cut? The tool built with `-O` gives no message.
3. A build with Embedded Swift is not done.
4. This document does not compare with ICU4X.

## Where the material is

* **Kept in this repo:** `docs/scripts/pr2330-date-data/`. It has the script for the locale cuts (`make-cuts.sh`) and its log, the compile and size script (`compile-and-size.sh`) and its log, the group share estimate (`group-share.py`), and a README with the steps and the commands for the first layout.
* **Only in `/tmp` (macOS cleans it after about 3 days, the scripts make it again):**
  * the PR files at `80ebeafa3d`, the cuts and the objects: `/tmp/deep-review/pr2330-80ebeafa/` (folders `cut/` and `obj/`)
  * the first layout and its object: `/tmp/deep-review/pr2330-80ebeafa/old-9dda818323/`
* This document is part of the larger plan: `docs/FOUNDATION-DATA-ARCHITECTURE-PLAN.md`.
