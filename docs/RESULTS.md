# Foundation in Embedded Swift: a measurement (2026-10-20)

**Question:** can a program in Embedded Swift use the date formatting of PR #2330, and how big is it?

**Code:** PR #2330 head `bfe992339c` (2026-10-20; the head moved 21 commits past the one we reviewed, `ddf23b0dad`). swift-collections 1.6.0 (local).

**Toolchain:** `swift-DEVELOPMENT-SNAPSHOT-2026-06-24-a` (Swift 6.5-dev). The toolchain of Xcode 8 has no Embedded standard library. Target `arm64-apple-macos`. The scripts are in `scripts/`. The work folder was `/tmp/deep-review/embedded-20261020/`.

## Summary

* **The #2330 date data and its lookup code build and run in Embedded Swift.** The output is the same as the normal build for all 1,140 locale identifiers that we tried (`outputs-all-locales.txt`).
* **Size, Embedded, en_US only: 38 KB in total** (35 KB of code, mostly the standard library, and 2.8 KB of data). With all locales, the data is 198 KB.
* **Six `String` comparisons cost 42 KB.** In Embedded Swift, `String ==` and `String` slicing pull in the Unicode normalization tables (`libswiftUnicodeDataTables.a`). Byte comparisons give the same output and remove them.
* **FoundationEssentials does not build in Embedded mode yet.** After we turned off `os` and `ProgressManager` in a copy, 2,092 errors remain in 102 of 287 files: `Codable` (JSON, property lists, `RecurrenceRule`), `BigString`, `Predicate`, `POSIXErrorCode`, `errno`, `Mutex`.
* **The date pattern formatter cannot be tried yet.** It is in FoundationInternationalization, which has no Embedded guards, and it needs FoundationEssentials.

## 1. The #2330 data module in Embedded Swift

**Program:** `scripts/main.swift`. It reads a locale from the environment variable `LOCALE` at run time, so the linker cannot drop the other locales. Then it prints 2026-09-18 14:05 as "weekday, month day, year h:mm am/pm" with the data of #2330. It uses `DataLocaleIdentifier`, `DateFormatLocale`, the names of weekdays, months and day periods, and `numbers(_:)` for the digits.

**Build:** `swiftc -Osize -wmo`, linked with `-dead_strip`. Embedded builds add `-enable-experimental-feature Embedded`.

**Sizes:** the sum of all sections, in bytes. The file is larger, because macOS rounds segments up to 16 KB pages and adds symbol tables.

| Build | Code | Data | Total | File |
|---|---:|---:|---:|---:|
| Hello world, Embedded | 212 | 0 | 237 | 33,784 |
| en_US only, Embedded, byte comparisons | 35,032 | 2,784 | **38,114** | 105,568 |
| en_US only, Embedded, as in the PR | 44,644 | 34,324 | 80,510 | 152,024 |
| All locales, Embedded, byte comparisons | 35,540 | 197,808 | 233,646 | 304,144 |
| All locales, Embedded, as in the PR | 45,156 | 229,348 | 276,030 | 350,504 |
| en_US only, normal Swift | 18,656 | 4,708 | 26,327 | 96,088 |
| All locales, normal Swift | 19,104 | 199,716 | 221,783 | 294,632 |

The normal builds link the standard library as a shared library, so their code column does not include it. The Embedded builds include all of the standard library code that the program uses.

**"As in the PR" and "byte comparisons":** both rows run the same program with the same data. "As in the PR" is the code of #2330 as it is. "Byte comparisons" is a copy in which 6 lines of `DateFormatLookup.swift` compare the UTF-8 bytes of a string instead of using `String ==`. Section 2 explains why this changes the size, and why I tried it.

**The two "normal Swift" rows** are the same program, built as normal Swift instead of Embedded Swift. They are the baseline for the Embedded rows:
* **Between them,** only the data changes: 4,708 bytes for en_US against 199,716 for all locales. So all locales cost about 195 KB. The code stays about the same (18,656 against 19,104), because the lookup code does not depend on the number of locales.
* **Against the Embedded rows,** the data costs the same, about 195 KB for all locales. But Embedded has more code (35 KB against 19 KB), because it carries the standard library code that it uses. A normal program gets that code from the shared library of the OS.
* **Normal Swift never pays for `String ==`,** because the Unicode tables are in the shared library of the OS. So the 42 KB problem shows only in Embedded Swift.
* **The data of normal Swift** (4,708 bytes for en_US) is larger than the Embedded data (2,784), because normal Swift also stores type information (metadata) that Embedded Swift leaves out.

**What the 35 KB of code is** (en_US, byte comparisons): 14.5 KB of `String` and `Character` code, 13.5 KB of other standard library and runtime code, 5.9 KB of collections, and 2.5 KB of the #2330 code and `main`. Much of the `String` code comes from the string interpolation and `print` in the test program, not from #2330.

**The en_US data** came from `utils/build-date-format-data --locales=en_US`: 2 locales (en_US and root) and 2,338 bytes of tables.

## 2. Why the Unicode tables come in

**Why `String ==` costs size.** In Swift, `==` on `String` does not compare bytes. It compares the text after Unicode normalization. For example, "é" as one character is equal to "e" followed by a combining accent. For that, Swift needs normalization code and tables. In normal Swift they are in the shared `libswiftCore` of the OS, so an app does not pay for them. Embedded Swift has no shared library, so they go into the program itself, from `libswiftUnicodeDataTables.a`.

**How I found it.** I did not plan this comparison. The first Embedded build of the program did not link, because the normalization symbols were missing. So I asked the linker which code needs them. Then I changed only that code, to see if the program can do without them, and what they cost.

**The link error without the library:** `__swift_stdlib_getNormData`, `__swift_stdlib_getComposition`, `__swift_stdlib_getDecompositionEntry` and `__swift_stdlib_nfd_decompositions` are undefined.

**What uses them:** `ld -why_live` points at two functions in `DateFormatLookup.swift`:
* `DateFormatLocale.numbers(_:)`: `keyword == "hanidays"`, `keyword == "default"` and the other keyword checks, and `switch keyword { case "native": ... }`.
* `Keywords.regionalBaseName(_:)`: `result == baseName`, and `String(baseName[..<end])`.

**The test:** in a copy, I replaced these 6 places with byte comparisons (`utf8.elementsEqual`) and with `String(decoding: utf8[..<end], as: UTF8.self)`. The diff is in `scripts/bytecmp-DateFormatLookup.diff`. The program then links without `libswiftUnicodeDataTables.a`, and it is 42 KB smaller with en_US data. Its output is the same for all 1,140 identifiers.

**Why byte comparisons are correct here.** The values in these 6 places are locale keywords (such as `native`, `finance`, `hanidays`) and parts of locale identifiers (such as `en_GB`). They are plain ASCII, and Unicode normalization never changes ASCII text. So a byte comparison gives the same answer as `String ==`.

**What it costs:** about 42 KB. That is about 9.6 KB of code and 31.5 KB of tables. With en_US data, this is more than the rest of the program (38 KB).

**Note for the author:** the rest of the lookup code already works on bytes. These 6 places are the only ones that need Unicode for a device build.

## 3. FoundationEssentials in Embedded mode

The repository has no Embedded build. Package.swift, CMake and CI have no setting for it. #2272 says: "This PR does NOT change the actual Package.swift to build Foundation in embedded mode." So I built it by hand with `swiftc` (`scripts/mod.sh`, `scripts/essentials.sh`), with the settings of Package.swift.

1. **swift-collections:** `InternalCollectionsUtilities`, `ContainersPreview`, `DequeModule`, `OrderedCollections` and `_RopeModule` all build in Embedded mode with no errors.
2. **The `os` module:** in Embedded mode on Darwin, `import os` fails. The `XPC` headers that it includes need Objective-C, and Embedded mode turns Objective-C off. `-DOS_OBJECT_USE_OBJC=0` does not help, and macOS SDKs 26.4 and 27.0 give the same result. 18 files import `os` or `os.log`. I put these imports behind `!hasFeature(Embedded)` in a copy.
3. **`ProgressManager`** imports `Observation`, which Embedded Swift does not have. I turned off its 10 files in the copy.
4. **After that: 2,092 errors in 102 of 287 files** (`fe-embedded-errors.txt`, and the guards in `scripts/fe-embedded-guards.diff`):

| Folder | Errors | Files | Main cause |
|---|---:|---:|---|
| AttributedString | 594 | 18 | `BigString` is not found: swift-collections 1.6.0 excludes it in Embedded (`#if compiler(>=6.2) && !$Embedded`) |
| PropertyList | 571 | 11 | `Codable`, `CodingKey`, `DecodingError` are not available in Embedded Swift |
| Predicate | 251 | 23 | |
| JSON | 237 | 3 | `Codable` |
| Error | 109 | 2 | `POSIXErrorCode` is not found |
| top level | 103 | 6 | |
| NotificationCenter | 54 | 6 | |
| FileManager | 48 | 8 | |
| Data | 33 | 2 | `errno` is not found |
| Calendar | 26 | 4 | `Codable` in `RecurrenceRule.swift`, `Mutex` is not found in `Calendar_Cache.swift` |
| URL, Formatting, Decimal, String, ProcessInfo, CharacterSet | 60 | 16 | |

**Calendar:** apart from `RecurrenceRule` and `Mutex`, the calendar code compiles in this build. But #2323 turned off `Calendar_Chinese.swift`, `Calendar_Hebrew.swift` and `Calendar_Astronomy.swift` for Embedded, so those calendars are not in an Embedded build.

**`AttributedString`:** #2325 enabled it for Embedded. With our local swift-collections 1.6.0, `BigString` does not exist in Embedded, so it does not build here. The PR pins swift-collections 1.1.6 for remote builds. I did not check which version #2325 was tested with.

## 4. The date pattern formatter

I could not try it. `DatePatternFormatter` is in FoundationInternationalization, and that module has 0 files with Embedded guards. It needs `Calendar`, `Locale`, `TimeZone` and `AttributedString` from FoundationEssentials, and FoundationEssentials does not build yet.

## Side results for the #2330 review (head `bfe992339c`)

* **Fixed:** `EN_gb` gives British English, and `th-TH-u-nu-thai` gives Thai digits (F2, F3).
* **Not fixed:** es_MX still writes `pm` (F1).
* **Not fixed:** with en_US-only data, `en_GB` and `de` get root names (`Fri, M09 18`) (F10 for dates).

## Limits of this measurement

* One toolchain (a snapshot from June 2026), and one target (`arm64-apple-macos`). A real device target such as `armv7em-none-none-eabi` or `wasm32-unknown-none-wasm` has no Darwin headers, so the `os` problem does not occur there. But it needs a C library for `_FoundationCShims`, and none is installed here.
* The size of the code depends on the test program. A program that formats without string interpolation and `print` would be smaller.
* I did not run the tests of swift-foundation in Embedded mode.
