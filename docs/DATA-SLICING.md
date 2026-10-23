# PR #2330: a small Embedded Swift app takes only the date data it needs

**Date:** 2026-10-20. **Code:** PR #2330 head `bfe992339c`. **Toolchain:** `swift-DEVELOPMENT-SNAPSHOT-2026-06-24-a`, Embedded Swift, target `arm64-apple-macos`.

## The point

PR #2330 stores the CLDR date data in tables that a build can cut to the locales an app needs. A small Embedded Swift app that uses this data for en_US only carries **2,350 bytes of tables instead of 197,352**, about 84x less. The app code does not change. Only the generated data file changes. The compiler and the linker then keep only the lookup code that the app calls.

## The app

**Source:** `scripts/main.swift` (20 lines). It reads a locale identifier at run time and prints a date line with the names and digits of that locale:

```
en_US: Friday, September 18, 2026 2:05 PM
ar_EG: الجمعة, سبتمبر ١٨, ٢٠٢٦ ٢:٠٥ م
```

The date values are fixed in the app (18, 2026, 2:05), because the point here is the data, not date arithmetic.

**The #2330 APIs that it calls** (all in `Sources/_FoundationInternationalizationData/`):

| Call | File | What it does |
|---|---|---|
| `DataLocaleIdentifier(_:)` | `DataLocaleIdentifier.swift` | Parses the identifier (case, BCP 47, `@` keywords). |
| `DateFormatLocale(_:)` | `DateFormatLookup.swift` | Finds the locale in the tables, with redirects and fallback. |
| `weekday(_:context:width:)` | `DateFormatLookup.swift` | Reads a weekday name. |
| `month(_:context:width:)` | `DateFormatLookup.swift` | Reads a month name. |
| `dayPeriod(_:width:)` | `DateFormatLookup.swift` | Reads "AM" or "PM". |
| `numbers(_:)` and `appendDigit(_:to:)` | `DateFormatLookup.swift` | Writes digits in the numbering system of the locale. |
| `.string` | `DateFormatLookup.swift` | Turns a table entry into a `String`. |

## How the data is cut

**1. Make the tables for the locales the app needs.** The generator of #2330 takes a list of locales:

```
utils/build-date-format-data --locales=en_US --output=DateFormatData-en_US.swift
```

It writes a new `DateFormatData.swift` with the same tables and the same names, but only with en_US and root.

**2. Build the app with that file.** The app source and the lookup code stay the same:

```
swiftc -enable-experimental-feature Embedded -target arm64-apple-macos15 -Osize -wmo -Xlinker -dead_strip \
  -package-name FoundationPkg -enable-experimental-feature Lifetimes -DFOUNDATION_DATE_FORMAT_SWIFT \
  DataLocaleIdentifier.swift DateFormatData-en_US.swift DateFormatLookup.swift main.swift -o app
```

For all locales, the same command uses the `DateFormatData.swift` of the PR. The full scripts are `scripts/build.sh` and `scripts/build-nout.sh`.

## Why the tables cut so well

The tables point to each other, from the locale down to the text:

1. **`localeIDs`** lists the locales in sorted order. **`localeRows`** gives each locale its row.
2. **`rows`** has 29 numbers for each row. Each number points to a block of names in `names`: the wide months, the abbreviated weekdays, the day periods, and so on. Locales with the same names share one block.
3. **`names`** has one 4-byte entry for each string. Text of 3 bytes or less is in the entry itself. Longer text is an offset into `pool`.
4. **`pool`** stores each longer text once.

So the generator keeps the rows of the chosen locales, then only the blocks that those rows point to, then only the text that those blocks use. Nothing else needs to change.

**The size of each table:**

| Table | All locales (bytes) | en_US only (bytes) |
|---|---:|---:|
| `pool` (text) | 97,066 | 782 |
| `names` (string entries) | 71,916 | 544 |
| `rows` (blocks for each locale) | 19,256 | 116 |
| `localeIDs` and `localeRows` | 6,426 | 12 |
| `redirectFrom` and `redirectTo` (aliases, parent locales) | 1,800 | 8 |
| Tables that do not depend on the locale (numbering systems, `hanidays` days, regions, irregular digits, minus signs) | 888 | 888 |
| **Total** | **197,352** | **2,350** |

Only the last row keeps its size, because those tables are the same for every locale.

## What the build put into the app

**Data:** the app with en_US data has 2,784 bytes of constant data. 2,350 bytes of that are the #2330 tables. With all locales, the app has 197,808 bytes.

**Code:** the compiler and the linker keep only the code that `main` reaches:

* **In the app:** `DataLocaleIdentifier.init` and its parsing helpers, `DateFormatLocale.init`, `index(for:)`, `fallbackIndex()`, `string(_:_:_:)`, `numbers(_:)`, `DateFormatNumbers.appendDigit(_:to:)`, and `DateFormatDataString.append(to:)`. The calls `month`, `weekday` and `dayPeriod` are inlined into `main`.
* **Not in the app:** `quarter`, `era`, `gmtFormat`, `hourFormat`, `capitalizes` and `hanidaysDay`, because the app never calls them. The `hanidaysDays` table is not in the app either, because nothing reads it.
* **Size:** the #2330 code and `main` together are about 2.5 KB. The rest of the code is the parts of the Swift standard library that the app uses (strings, arrays, `print`).

**The whole app:**

| | All locales | en_US only |
|---|---:|---:|
| #2330 tables in the source | 197,352 | 2,350 |
| Constant data in the app | 197,808 | 2,784 |
| Code in the app | 35,540 | 35,032 |
| **App total** (all sections) | **233,646** | **38,114** |

These app sizes use byte comparisons in 6 lines of `DateFormatLookup.swift`. With those lines as in the PR, Embedded Swift adds about 42 KB of Unicode tables to both apps. Those tables are not #2330 data. See `RESULTS.md`, section 2.

## What a cut costs

A locale that is not in the cut gets the fallback locale. That is root by default, or the locale that `--fallback` names. With en_US data, `de` prints `Fri, M09 18, 2026 2:05 PM`, with the root names.

## Checks

* With all locales, the Embedded app gives the same output as the normal Swift build for 1,140 locale identifiers (`outputs-all-locales.txt`).
* With en_US data, the en_US output is the same as with all locales.
