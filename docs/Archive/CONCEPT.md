# The idea, in plain words

> **Archived on 2026-10-28. Superseded by [`FOUNDATION-DATA-ARCHITECTURE-PLAN.md`](../FOUNDATION-DATA-ARCHITECTURE-PLAN.md).** This page comes from the phase that copied ICU4X. Kept for the record only.

This page explains the idea with no special words. The words that ICU4X uses come at the end.

## 1. The problem

To format a date, a program needs data for each language: month names, weekday names, the order of day, month and year, and more. For 400 languages and 6 calendars, this is about 1 MB.

Most apps need only a small part of it. An app that shows dates only in Japanese, only in the Gregorian calendar, still carries the data of every language and every calendar.

## 2. The idea

**Split the data into pieces, by what it is used for.** One piece holds "the month names of the Gregorian calendar". Another piece holds "the month names of the Chinese calendar". The date formatter of the prototype uses 25 pieces.

**Inside each piece, keep one entry for each language.**

| Piece | Entries |
|---|---|
| Month names, Gregorian calendar | `en`, `fr`, `de`, `ja`, … (all languages) |
| Month names, Chinese calendar | `en`, `fr`, `de`, `ja`, … |
| Date patterns, Gregorian calendar | `en`, `fr`, `de`, `ja`, … |
| Weekday names (all calendars) | `en`, `fr`, `de`, `ja`, … |
| … 21 more pieces | |

Then the data can get smaller in two separate ways:
1. **Fewer pieces.** The build removes the pieces that the app's code never uses. Nobody has to make a list.
2. **Fewer languages.** A tool keeps only the languages that the developer lists. The tool also keeps the languages that a missing language falls back to, for example `fr` for `fr-CA`.

## 3. One example, measured

An app formats Gregorian dates in Japanese. All sizes are from the prototype, in normal Swift.

| Step | Data in the app |
|---|---:|
| All pieces, all languages (a build that removes nothing) | 1,042,468 bytes |
| Only the 5 pieces that the app's code uses (automatic, with 3 linker flags) | 268,678 bytes |
| Only those 5 pieces, only Japanese (the developer gives `ja`) | 12,278 bytes |

The text that the app prints is the same in all three steps.

## 4. What the developer does

**Case 1: the code names the calendar.** For example, `FixedCalendarFormatter<Gregorian, YMD>`. Then:
* The developer gives one list of languages, for example `ja`.
* The build finds the pieces by itself.

**Case 2: the code chooses the calendar at run time.** For example, `Calendar(identifier: someValue)`, as in Foundation. Then:
* The build cannot know which calendar will run, so it keeps the pieces of every calendar. The output is still correct.
* To make the data small, the developer must say which calendars and features the app uses, in plain words, for example "Gregorian and Japanese calendars, list formatting". A tool would turn that into pieces. This tool is not built yet.

In neither case does the developer need to know how the pieces are named.

## 5. How the pieces are named

The prototype uses the names of ICU4X, so that it can read the ICU4X data. A name is a few English words joined together, from general to specific, and a version at the end:

`DatetimeNamesMonthChineseV1` = Datetime, Names, Month, Chinese, version 1 = "for date formatting: the names of the months, of the Chinese calendar".

ICU4X has no written rule for these words. The only fixed rule is the version at the end. So the names are not a good thing to show to users. If Foundation used this idea, it could define its own names with a fixed rule, and keep them inside its tools. [`DESIGN-DATA-KINDS.md`](DESIGN-DATA-KINDS.md) is a draft design for this: who defines the kinds of data, the naming rule, one registry file, and the user settings.

## 6. What it means for Foundation

| | Result |
|---|---|
| Does Foundation's API have to change? | No. The idea works behind an API like `Calendar(identifier:)` and `Date.FormatStyle`, with the same output. Tested. |
| Does the build remove unused calendars by itself? | No, not with that API (case 2). It still removes features that the app never calls, such as list formatting. This follows from how the linker works, but it is not tested yet. |
| Where does it help? | Builds that put Foundation into the app: Embedded Swift, WASM, static Linux apps. On Apple platforms, all apps share one Foundation, so the gain there is small. |
| Is the output the same as today's Foundation? | No, in about half of the cases. The prototype copies ICU4X, which uses other patterns and public CLDR data. A real version would make its pieces from Foundation's own data. |

## 7. How this builds on what Foundation has today

Foundation already uses this idea for one feature. In PR #1991, Christopher Chapman added Swift data for list formatting:
* `utils/update-list-format-data` reads CLDR and writes `ListFormatData.json`. `utils/build-list-format-data` turns it into Swift tables in `Sources/_FoundationInternationalizationData/ListFormatData.swift`.
* The data is split into **6 pieces**: "and" and "or", each in 3 widths (`slotAndWide`, `slotOrShort`, …).
* **Each piece has one entry for each language**, found by a binary search.
* A missing language **falls back** to its CLDR parent, then to the language without its region, then to the root (`ListFormatLookup.swift`).
* `build-list-format-data --locales` **keeps only some languages.**

Chris's open PR #2330 goes one step further, for the list data and for its new date data: every language has a complete entry, built from the CLDR parents by the tool, and identical entries are stored once. The app then resolves the language only once, not for every value. `DESIGN-DATA-KINDS.md`, section 9, proposes this way for all features.

So the list data is already "pieces with one entry for each language", but with no marker types. This idea does not replace that work. It takes the same approach to every feature:

| | List data today (#1991) | This idea |
|---|---|---|
| Features | list formatting only | every feature that uses locale data |
| Marker types | none: one `switch` picks one of the 6 tables at run time | one type per piece. This helps only when the code picks the piece by type. `ListFormatStyle` takes the list type and the width as values at run time, so for lists the types would remove nothing. |
| Format of the tables | made for list patterns | one format for all pieces |
| Lookup and fallback | made for lists (`ListFormatLookup.swift`) | one lookup and one fallback for all pieces |
| Cut by language | `--locales`, in the list tool | `--locales`, once for all features |
| Cut by feature or calendar | not needed: lists are one feature | features that the app never calls are removed by the build; calendars by a setting |
| Evidence | Foundation tests | the prototype: a date formatter with 25 pieces, the same output as ICU4X on 327,888 cases, sizes and speed |

Two lessons from the prototype apply to the list data too:
* The list tables are `static let` `InlineArray` values, and the lookup takes their `.span`. In the prototype, `.span` on a `static let` `InlineArray` copied the whole table each time. The list tables are small (about 1 KB each), so the cost is small there. It grows with the size of the table. This was not measured for the list data.
* In a build that puts Foundation into the app, normal Swift keeps all data unless the build uses 3 linker flags. Embedded Swift needs none.

## 8. What it cannot do

* It cannot remove languages by itself. The language is chosen at run time, so the developer must give the list. ICU4X has the same limit.
* A language that was removed gives no error. It falls back to the root data, which is not in the user's language.
* With a calendar chosen at run time, it cannot remove calendars by itself (section 4, case 2).

## 9. The words that ICU4X uses

| ICU4X word | On this page |
|---|---|
| marker | a piece |
| locale | a language (with an optional script and region, such as `zh-Hant-TW`) |
| attribute | a second key inside a piece, for example the width of the month names: short, abbreviated or wide |
| `--markers-for-bin` | the ICU4X tool that finds the pieces in a built app |
| `icu4x-datagen` | the ICU4X tool that makes the data and removes languages |

ICU4X explains its design in [Principles of data architecture](https://github.com/unicode-org/icu4x/blob/747356078891d513c1f731320e3d0e1ee9912e33/documents/process/data_architecture.md) and the [data management tutorial](https://github.com/unicode-org/icu4x/blob/747356078891d513c1f731320e3d0e1ee9912e33/tutorials/data-management.md).
