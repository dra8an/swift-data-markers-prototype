# A plan for Foundation's locale data (an alternative to ICU4X data markers)

**Started:** 2026-10-27. **Status:** part 1 (the inventory) is done. Part 2 (the model) is a draft that Dragan agreed on 2026-10-28. Parts 3 and 4 are not started.

**Sources:**
* swift-foundation `main` at `bfbded0f70` (2026-10-27), a snapshot in `/tmp/deep-review/sf-main-bfbded0f70/`
* the Darwin Foundation checkout at `1e2ed46155` (2026-10-05), `/Users/draganm4/Projects/github-pie/Foundation/`
* swift-foundation-icu at `e8538d2593` (2026-05-27), the ICU data that swift-foundation ships outside Darwin
* the study of the #2330 date data: `FOUNDATION-DATE-DATA-ARCHITECTURE.md`

This plan starts from Foundation's own code and data. It compares with ICU4X only at the end (part 4).

## The parts of the plan

1. **The inventory:** every place where Foundation reads locale data or ICU data, and what that data costs today.
2. **The model:** the kinds of data, the optional cuts, and the answers to the concerns of the team.
3. **The architecture in detail:** the pipeline, the layout, the build selection, and Darwin with Embedded.
4. **The comparison with ICU4X markers.**

## The documents

Start here. This plan is the only entry point. Add new results to it, not to a new document.

| Status | Document | What it is |
|---|---|---|
| Current | `FOUNDATION-DATA-ARCHITECTURE-PLAN.md` | this plan |
| Current | `FOUNDATION-DATE-DATA-ARCHITECTURE.md` | the study of the date data in PR #2330 (head `80ebeafa3d`), an input to this plan |
| Background, correct for its date | `DATA-SLICING.md` | #2330 data in an Embedded Swift app, at head `bfe992339c` (2026-10-20) |
| Background, correct for its date | `RESULTS.md` | #2330 date formatting in Embedded Swift, and its size (2026-10-20) |
| Background, for part 4 | `ICU4X-COMPARISON.md` | how #2330 compares with ICU4X (2026-10-20) |
| Background, for part 4 | `ICU4X-DATA-GUIDE.md` | one request through the ICU4X data, step by step (2026-10-21) |
| Internal | `NOTES.md` | notes on git, the sandbox and provenance |
| Scripts and raw data | `scripts/` | `icu-data-inventory/` for part 1, `pr2330-date-data/` for the date study, and older build scripts |
| Archived on 2026-10-28 | `Archive/` | `CONCEPT.md`, `DEV_GUIDE.md`, `DESIGN-DATA-KINDS.md`, `MARKER-CATALOG.md` and `catalog/`: the phase that copied ICU4X. The team rejected its fine kinds on 2026-10-27. Do not use them. |

The results of the two prototypes (2026-10-23) are in `prototype-large/RESULTS.md`, outside `docs/`.

# Part 1: the inventory

## 1.1 Where the features are

* `FoundationEssentials` has no ICU. It is the only module that Embedded Swift builds (188 files have Embedded guards, against 1 in `FoundationInternationalization`).
* `FoundationInternationalization` has all the localized features. It depends on `_FoundationICU` (the `swift-foundation-icu` package) and on `_FoundationInternationalizationData` (the Swift tables, today only the list data).
* On Darwin, the Foundation framework uses the same Swift files, and CoreFoundation and the Objective-C classes call ICU too.

## 1.2 The features, one by one

"Swift today" means code on `main` that works with no ICU. "Axes" are the inputs that select the data.

| # | Feature | Public API (examples) | ICU today (swift-foundation) | Data (CLDR or other) | Swift today | Axes |
|---|---|---|---|---|---|---|
| 1 | Locale identity | `Locale.Components`, `Locale.Language`, canonical identifier, `identifier(.bcp47)` | `uloc`, `ualoc`, `uregion`, `uscript` | likely subtags, aliases, region containment, LCID | canonical identifier tables (`Locale_CanonicalIdentifierTables.swift`, 26 KB of source) | identifier |
| 2 | Locale preferences | `firstWeekday`, weekend, `hourCycle`, `measurementSystem`, quotation marks, `numberingSystems`, `currency`, collations | `ucal` week data, `ulocdata`, `udatpg` hour cycle, `unumsys`, `ucurr`, `ucol` keywords | week data, measurement data, delimiters, currency per region | no | locale, region |
| 3 | Display names | `localizedString(forLanguageCode:)`, region, script, currency, calendar, keyword values | `uloc_getDisplay*`, `ucurr_getName` | language, region, script, currency names | no | locale, item |
| 4 | Calendar arithmetic | `Calendar` for 27 identifiers | `ucal` (321 calls, `Calendar_ICU.swift`) | the rules of each calendar (code), Japanese eras | Gregorian, Hebrew, Chinese on `main`. 7 more in PR #2324 | calendar |
| 5 | Calendar symbols | `monthSymbols`, `weekdaySymbols`, `eraSymbols` and the others | `udat_getSymbols` | month, weekday, era, quarter, AM and PM names | no | locale, calendar |
| 6 | Time zone rules | `TimeZone(identifier:)`, offsets, transitions | `ucal` time zone calls, `zoneinfo64` through `ures` | tz rules (from ICU's data) | only fixed offsets (`TimeZone_GMT`) | time zone |
| 7 | Time zone names | `localizedName(for:locale:)` | `ucal_getTimeZoneDisplayName`, `uatimezone` | zone names, metazones | no | locale, time zone |
| 8 | Date format | `Date.FormatStyle`, `VerbatimFormatStyle`, attributed forms | `udatpg` (pattern), `udat` (fill) | patterns and skeletons, names, digits | the fill step in PR #2330 (open, behind a flag). ISO 8601 and HTTP in Essentials | locale, calendar, pattern, numbering system |
| 9 | Date parse | `Date.ParseStrategy`, `FormatStyle.parse` | `udat_parseCalendar` | as for 8 | no | as for 8 |
| 10 | Date intervals | `Date.IntervalFormatStyle` | `udtitvfmt` | interval patterns | no | locale, calendar |
| 11 | Relative dates | `Date.RelativeFormatStyle`, anchored relative | `ureldatefmt`, `unum` | relative time patterns | no | locale, unit |
| 12 | Durations | `Duration.TimeFormatStyle`, `UnitsFormatStyle` | `uatmufmt`, `unumf` | unit patterns, time patterns | no | locale, unit |
| 13 | Number format | `IntegerFormatStyle`, `FloatingPointFormatStyle`, `Decimal.FormatStyle`, currency, percent | `unumf` (skeletons), `unum` | number symbols and patterns, currency data, compact forms, plural rules | no | locale, numbering system, currency |
| 14 | Number parse | the parse strategies | `unum_parse*` | as for 13 | no | as for 13 |
| 15 | Byte counts | `ByteCountFormatStyle` | `unumf`, `ulocdata` exemplar sets | unit patterns | no | locale |
| 16 | Lists | `ListFormatStyle` | `ulistfmt` only with `FOUNDATION_LIST_FORMAT_ICU` | list patterns | **yes** (#1991, the default) | locale |
| 17 | Measurements | `Measurement.FormatStyle` | none: a stub in swift-foundation. `uameasfmt` for units by usage | unit patterns, preferences by region | no | locale, unit, usage |
| 18 | Case mapping | `String.uppercased(with:)`, `lowercased(with:)`, `capitalized(with:)` | `ucasemap` | Unicode case data, language rules | no | language |
| 19 | Collation | `compare(_:options:range:locale:)`, `localizedStandardCompare`, `SortDescriptor`, `String.Comparator` | `ucol` | collation tables per language | no | locale, collation type |
| 20 | String encodings | `String(data:encoding:)`, `data(using:)` for legacy encodings | `ucnv` | converter tables | the Unicode encodings, without ICU | encoding |
| 21 | URLs | IDNA host names, the look-alike check | `uidna`, `uscript`, `ublock`, `u_*` properties | UTS 46 data, Unicode properties | no | none (global) |
| 22 | Bidi class | internal | `u_charDirection` | Unicode properties | no | none (global) |

### Darwin only

The Darwin checkout calls these ICU services too. swift-foundation does not use them.

| Feature | Files | ICU |
|---|---|---|
| Regular expressions, predicate `MATCHES` | `NSRegularExpression.m`, `NSMatchingPredicateOperator.m` | `uregex`, `utext` |
| String transforms | `CFStringTransform.c` | `utrans` |
| Hyphenation | `CFStringHyphenation.c` | `ubrk` |
| Bidi | `CFBidi.c` | `ubidi` |
| Locale aware search | `CFString.c` | `usearch` |
| Plural rules for localized strings, units | `NSStringFormatInterface.m`, `NSUnitFormatter.m` | `uplrules` |
| The old formatters | `CFDateFormatter.c`, `CFNumberFormatter.c`, `NSDateComponentsFormatter.m`, `NSDateIntervalFormatter.m`, `CFRelativeDateTimeFormatter.c`, `CFListFormatter.c`, `NSUnitFormatter.m`, `NSPersonNameComponentsFormatter.m` | `udat`, `unum`, `udtitvfmt`, `ureldatefmt`, `ulistfmt`, `uameasfmt`, `uset` |
| String encodings | `CFICUConverters.c` | `ucnv` |

## 1.3 What the ICU data costs today

swift-foundation ships ICU 76 data outside Darwin as one C array (`icu_packaged_main_data.*.inc.h`, 4 parts, 210 MB of source). The array is **33,976,096 bytes**. These are binary bytes in the library, not source text. A built object of `icu_packaged_data.cpp` (in `swift-foundation-seven/.build/index-build/`) has exactly 33,976,096 bytes of `__TEXT,__const`, in the symbol `_icudt76_dat`. All sizes in this part are binary bytes, unless they say "source". I read its table of contents (4,855 items):

| Category | Bytes | Items | Used by (features above) |
|---|---:|---:|---|
| Converters (`*.cnv`) | 5,668,800 | 197 | 20 |
| Collation (`coll/`) | 4,276,704 | 176 | 19 |
| Locale files (`*.res` per locale) | 2,872,704 | 1,097 | 2, 5, 8 to 16 |
| Break iteration (`brkitr/`), of which `cjdict.dict` is 2,007,344 | 3,843,008 | 39 | none in swift-foundation. Darwin hyphenation |
| Time zone names (`zone/`) | 3,293,376 | 626 | 7 |
| Units (`unit/`) | 2,958,176 | 613 | 11, 12, 15, 17 |
| Currencies (`curr/`) | 2,933,136 | 706 | 3, 13 |
| Language names (`lang/`) | 2,914,464 | 621 | 3 |
| Supplemental files (top level `*.res` that are not locales) | 1,195,648 | 20 | 1, 2, 4, 6, 13 and others |
| Region names (`region/`) | 1,228,304 | 622 | 3 |
| Transforms (`translit/`) | 1,111,904 | 3 | none in swift-foundation |
| Spellout rules (`rbnf/`) | 634,160 | 114 | none found in swift-foundation |
| Unicode names, layout, emoji (`*.icu`) | 428,672 | 4 | 21 and others |
| Normalization (`*.nrm`), of which UTS 46 is 60,944 | 223,104 | 4 | 21 |
| String prep (`*.spp`) | 197,472 | 12 | none found |
| Confusables (`confusables.cfu`) | 45,936 | 1 | none found |
| The table of contents of the array | 150,528 | | |

The supplemental files include `likelySubtags.res` (257,616), `supplementalData.res` (246,320), `zoneinfo64.res` (148,608, the tz rules), `langInfo.res` (144,192), `metaZones.res` (42,928), `plurals.res` (35,584), `units.res` (22,624), `windowsZones.res` (22,064) and `dayPeriods.res` (19,968).

The Unicode character properties are separate. They are compiled into code (`uchar_props_data.h`, 741 KB of source), not into the data array.

**For comparison:** the #2330 date names are 198 KB for 1,071 locales (Gregorian only), and the list data is about 31 KB.

## 1.4 What the inventory shows (input for the talk)

1. **Most of the 34 MB is not per locale.** Converters, collation, break dictionaries, transforms and Unicode data make about 15.8 MB. Different axes select them: the encoding, the language of the collation, the script.
2. **Some ICU data has no user in swift-foundation, but less than a count of direct calls suggests.** ICU loads some parts itself. See 1.5.
3. **The axes are not only the locale.** The inventory shows these axes: locale, calendar, time zone, numbering system, currency, unit, collation type, encoding, and the pattern or skeleton.
   * **What a locale cut makes smaller:** about 20.5 MB of the 34 MB, not only the 2.9 MB of the main locale files. ICU stores 6 more kinds of data with one file per locale: collation 4.3 MB, time zone names 3.3 MB, units 3.0 MB, currencies 2.9 MB, language names 2.9 MB and region names 1.2 MB. Without collation, it is about 16.2 MB. The locale is not a kind of data of its own. It is a cut inside each kind (see part 2).
4. **Almost every axis is a run time value in the API.** `Locale`, `Calendar.Identifier`, `TimeZone` and the format style fields are values. So a build can only know an axis if the build names it in a list, as `--locales` does for lists and dates today.
5. **Some features are code, not data.** Calendar arithmetic and the tz rules need algorithms or tables that do not depend on the locale.
6. **Only one feature is fully in Swift today: lists.** Dates follow in #2330. Most features still call ICU.

## 1.5 Which data parts are unused (checked 2026-10-28)

A part with no direct call can still be in use, because ICU loads it inside another service. I checked ICU's source (`swift-foundation-icu`) for these indirect uses:
* `smpdtfmt.cpp`, `reldatefmt.cpp` and `reldtfmt.cpp` create break iterators, to capitalize dates and relative dates.
* `capitalized(with:)` calls `ucasemap_utf8ToTitle` with no break iterator, so ICU uses a word break iterator. Word breaks in Chinese, Japanese, Thai, Lao, Khmer and Burmese text load the break dictionaries.
* `smpdtfmt.cpp` and `numfmt.cpp` use spellout rules for algorithmic numbering systems, such as `hebr` and `hanidays`.
* I resolved the 11 legacy encodings of `ICU+StringConverter.swift` with the system ICU. They use 9 converter files, 211,936 bytes in total. ISO-2022-JP reuses the Shift_JIS table.

**Not used by swift-foundation:**

| Part | Size | Note |
|---|---:|---|
| Converters that no `String.Encoding` reaches | about 5.46 MB of 5.67 MB | Foundation reaches 9 files (0.21 MB) and the alias table (0.06 MB) |
| Transforms | 1.11 MB | |
| Unicode names (`unames.icu`) | 0.34 MB | |
| NFKC normalization (`nfkc`, `nfkc_cf`, `nfkc_scf`) | 0.16 MB | only `uts46.nrm` is in use, for IDNA |
| String prep | 0.20 MB | Foundation uses UTS 46, not the old IDNA |
| Confusables | 0.05 MB | |
| **Total** | **about 7.3 MB** | |

**Used only in some cases:**
* Spellout rules (0.63 MB): only the few rule sets of the algorithmic numbering systems.
* Break iteration (3.84 MB): the rules (0.83 MB) for capitalization. The dictionaries (3.0 MB) only when someone capitalizes text in the scripts above.

**What Darwin uses in addition:**
* Transforms (`CFStringTransform.c`), and with them Unicode names (the `Any-Name` transform) and NFKC.
* Break iteration for hyphenation (`CFStringHyphenation.c`).
* More converters: CoreFoundation builds the converter names from its encoding database at run time (`CFICUConverters.c`). I did not count them.
* Regular expressions, bidi and locale aware search. They need code and the Unicode and collation data, not other data files.
* Neither swift-foundation nor Darwin calls string prep or confusables.

## 1.6 A short summary of the ICU data (plain text)

```
ICU data in swift-foundation outside Darwin (ICU 76): 34.0 MB

Converters                                          5.7 MB
Collation                                           4.3 MB
Break iteration                                     3.8 MB
Time zone names                                     3.3 MB
Units                                               3.0 MB
Currencies                                          2.9 MB
Language names                                      2.9 MB
Locale files (dates, numbers and the other kinds)   2.9 MB
Others                                              5.2 MB

Others (5.2 MB):
Region names                                        1.2 MB
Supplemental files (likely subtags, week and
  calendar data, plural rules, tz rules, metazones) 1.2 MB
Transforms                                          1.1 MB
Spellout rules                                      0.6 MB
Normalization, string prep, confusables             0.5 MB
Unicode names, layout, emoji                        0.4 MB
Table of contents                                   0.15 MB

Not used by swift-foundation (about 7.3 MB):
Converters that no String.Encoding reaches          5.46 MB
Transforms                                          1.11 MB
Unicode names                                       0.34 MB
String prep                                         0.20 MB
NFKC normalization                                  0.16 MB
Confusables                                         0.05 MB
```

**Where the calendar, date and number data is.** It is in the row "Locale files", not in "Others". Each of the 1,097 locale files has the names for all calendars, the date and time patterns, the skeletons, the intervals, the number symbols and patterns, the lists and the relative time patterns. Calendar arithmetic is mostly code. Its data is small: era start dates and week rules in `supplementalData.res`. Date and number formatting also read other rows: time zone names (`z`, `v`) in "Time zone names", currency names and symbols in "Currencies", and plural rules in the supplemental files.

## 1.7 How the research was done

| Step | Method | Files (in `docs/scripts/icu-data-inventory/`) |
|---|---|---|
| The ICU calls of swift-foundation | A text search for ICU function names (`u…_…(` and `u_…(`) in `Sources/` of `main` `bfbded0f70`, grouped by family and file | `icu-call-map.sh`, `swift-foundation-icu-call-map.tsv` |
| The ICU calls of Darwin | The same search in the Darwin checkout `1e2ed46155`, without ICU's own source in `.build/`, tests, benchmarks and fuzzing | `darwin-icu-calls.txt`, `darwin-icu-family-files.tsv` |
| The features | I read the file list of `FoundationInternationalization` and `FoundationEssentials`, and the call sites of each family | none |
| Embedded | I counted the files with Embedded guards per module | none |
| The ICU data size | I converted the 4 parts of `icu_packaged_main_data.*.inc.h` to bytes, and read the table of contents of ICU's common data format | `toc.py`, `items.tsv` |
| The converters that Foundation reaches | I resolved the 11 encoding names of `ICU+StringConverter.swift` with the system ICU (`libicucore`), and looked up the file sizes in `items.tsv` | `cnv.c` |
| The indirect uses inside ICU | I read ICU's source in swift-foundation-icu | `README.md` lists the files and lines |

The README in that folder tells how to run each step again.

## Open points of the inventory

* I counted ICU calls by name. A call through a wrapper with another name can be missing. The ICU wrappers in `Sources/FoundationInternationalization/ICU/` are in the count.
* The split of the 2.9 MB of locale files into dates, numbers and the other kinds is not done yet. ICU's `.res` format needs a reader for that.
* The Darwin counts come from a checkout of 2026-10-05.
* The 34 MB is ICU 76 data. Apple platforms use Apple's own ICU build, with other data and a size that I did not measure.
* I did not count the converters that CoreFoundation reaches.

# Part 2: the model (a draft, agreed on 2026-10-28)

## 2.1 The two levels

**Level 1: the kinds of data.** Each kind is one feature of Foundation, with its own tables. By default, a kind holds all its data: all locales, all its keys.

**Level 2: the cuts.** Each cut is optional. A build can cut a kind by locale, by its own key, or by both. The locale is not a kind of its own. It is a cut inside each kind.

| Kind | Size today (ICU) | Can cut by locale | Can cut by its own key |
|---|---:|---|---|
| Dates (names, patterns, intervals, relative time) | part of 2.9 MB | yes | calendar |
| Numbers (symbols, patterns, compact forms) | part of 2.9 MB | yes | numbering system |
| Lists | part of 2.9 MB | yes | none |
| Units and durations | 3.0 MB | yes | unit |
| Currencies | 2.9 MB | yes | currency code |
| Time zone names | 3.3 MB | yes | zone |
| Language and region names | 4.1 MB | yes | language code, region code |
| Collation | 4.3 MB | yes | collation type |
| Break iteration | 3.8 MB | yes, through the script | script |
| Converters | 5.7 MB | no | encoding |
| Time zone rules | 0.15 MB | no | zone |
| Core locale data (parents, aliases, likely subtags, week data, plural rules) | about 1.2 MB | no, always kept | none |

"Can cut by locale: no" means that the data is the same for every locale, so a locale cut cannot make it smaller. Example: the Shift_JIS converter is the same table in every locale.

**Break iteration is cut through the script.** ICU selects the dictionary by the script of the text, not by the locale of the call. So a locale cut keeps the dictionaries of the scripts of the selected languages. Text in another script still breaks, with the rules only, and the breaks are worse.

| Language | Break data | Size |
|---|---|---:|
| Chinese, Japanese | `cjdict.dict` and the CJ line rules | 2.0 MB and 0.47 MB |
| Khmer | `khmerdict.dict` | 0.45 MB |
| Burmese | `burmesedict.dict` | 0.25 MB |
| Lao | `laodict.dict` | 0.16 MB |
| Thai | `thaidict.dict` | 0.13 MB |
| All languages | the base rules (line, word, sentence, character, title) | about 0.35 MB |
| Some languages | small tailorings (de, ja, pt, es, en, fr and others) | under 3 KB each |

Example: an app with only Thai keeps about 0.5 MB of break data, not 3.8 MB.

## 2.2 The build selection

One small configuration:
* the kinds that are on
* one locale list for all kinds, with an optional different list for one kind (for example, collation for fewer locales)
* optional lists for the own keys (for example, the calendars `gregorian` and `iso8601`)

## 2.3 The concerns of the team, and the answers of the model

The concerns come from the meeting of 2026-10-27 and from the talk of 2026-10-28.

1. **Who names the markers?** No one invents names. We name the kinds, about 12, after Foundation's features. All other values use standard identifiers: BCP 47 for locales, CLDR identifiers for calendars and units, IANA names for encodings and time zones, ISO 4217 for currencies.
2. **Is the slicing too fine?** No. The model never cuts inside one kind for one locale (for example, months apart from weekdays). In the #2330 data, one locale of dates is 3.4 KB, and a pattern at run time can need any part of it.
3. **Do we lose the sharing of identical data?** No. The generator first selects the data, then stores identical data once inside the selected set, as layout E in #2330 does today. Chris's dense format stays.
4. **Do we get megabytes of generated source?** No. A kind is one set of tables, not one type per marker. The source grows only with the selected data. The full date data of #2330 is 953 KB of source for 198 KB of binary, and it compiles in about 3 seconds.
5. **How large is the data?** ICU ships 34 MB today. About 7.3 MB has no user in swift-foundation, so the generator does not make it. The cuts make the rest smaller. Measured so far for dates only: all locales 198 KB, about 40 locales 28 KB, one locale 3.4 KB.
6. **How does missing data fail?** At build time, the generator refuses a selection that it cannot make correct, with a clear message. (Today #2330 stops with a trap, with no message in an optimized build.) At run time, each kind has a defined fallback, and a debug build can log each fallback:

   | Kind | If the value is not in the build |
   |---|---|
   | All locale data | the parent locales, then the fallback locale, then root |
   | Converters | `nil`, which `String(data:encoding:)` already returns |
   | Collation | root order |
   | Time zone names | the GMT form, such as "GMT+2" |
   | Break iteration | the rules only, without the dictionary |
   | Calendar | not decided yet |

7. **How are dependencies resolved?** The generator adds what a selection needs, and it reports what it added: for a locale, its parent locales, root, its aliases and the redirects. For a language, its default calendar, its default numbering system and the dictionary of its script. The core locale data, always.
8. **Why not rely on the linker, as ICU4X does?** Foundation's API takes values: `Locale`, `Calendar.Identifier`, `TimeZone` and the format styles. With values, the linker cannot know what is unused (the prototype of 2026-10-23 showed this). So the cut happens at build time, from the lists.
9. **One pipeline, or two for Darwin and Embedded?** One pipeline and the same tables, with different selections: Darwin the full selection, Embedded a small one. The data must not depend on ICU, so that it can work without `FoundationInternationalization` and its ICU. The tables go in `__TEXT,__const` as `InlineArray` (clean pages, no relocations), and the code reads them with subscripts (no `.span` copy).
10. **Scripts, or Swift macros?** Scripts, as in #1991 and #2330. The inputs (CLDR XML, tzdata, Unicode data) are large, and a macro gains nothing from them. One shared fallback logic already exists: `utils/cldr-locale-fallback.swift`.

## 2.4 Still open

1. The fallback for a calendar that is not in the build.
2. Does Darwin move to this data, or does it keep ICU?
3. Where does the selection live: a file in the package, build settings, or a SwiftPM plugin?
4. The split of the 2.9 MB of locale files into dates, numbers, lists and the other kinds. This needs a reader for ICU's `.res` format.

## Where the material is

* **Kept in this repo:** the scripts, the raw lists and their READMEs in `docs/scripts/icu-data-inventory/` (this plan) and `docs/scripts/pr2330-date-data/` (the date study).
* **Only in `/tmp` (macOS cleans it after about 3 days, the scripts make it again):**
  * swift-foundation `main`: `/tmp/deep-review/sf-main-bfbded0f70/`
  * the ICU data as bytes: `/tmp/deep-review/icudata/icudt.dat`
  * the PR #2330 files and builds: `/tmp/deep-review/pr2330-80ebeafa/`
