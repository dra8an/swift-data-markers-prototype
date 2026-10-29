# Draft design: the kinds of data, their names, and who defines them

> **Archived on 2026-10-28. Superseded by part 2 of [`FOUNDATION-DATA-ARCHITECTURE-PLAN.md`](../FOUNDATION-DATA-ARCHITECTURE-PLAN.md).** The meeting of 2026-10-27 rejected its fine kinds of data. Kept for the record only.

**Status:** a draft proposal for discussion, 2026-10-26. Nothing in it is built. The prototypes copied the 25 names of ICU4X by hand. This page proposes how Foundation could define its own kinds of data instead. The complete catalog that follows these rules is [`MARKER-CATALOG.md`](MARKER-CATALOG.md).

## 1. The questions

1. Who decides which kinds of data exist?
2. How is a kind of data named?
3. Where is the list of all kinds kept?
4. How is the data of each kind made?
5. How does a user choose data, with no technical names?

## 2. How ICU4X does it today

| Question | ICU4X |
|---|---|
| Who decides | The contributor who adds a feature. The ICU4X team reviews the pull request. |
| How the name is made | The contributor chooses it. The only checked rule: it ends with `V` and a number (`DataMarkerId::from_name` in `provider/core/src/marker.rs`). There is no written rule for the words. |
| Where the list is kept | `provider/registry/src/lib.rs`: a list of all 344 kinds, kept by hand. |
| How the data is made | One converter for each kind, in `icu4x-datagen` (`documents/process/writing_a_new_data_struct.md`, sections "Transformer" and "Registry"). |
| How a user chooses | `--markers-for-bin` (automatic), or `--markers` with the names (manual), and `--locales`. |

The weak points are the free names, and the manual name lists for code that chooses at run time (section 6 of `CONCEPT.md`).

## 3. Proposal: one registry file is the only source of truth

All kinds of data are listed in **one file**, the registry, for example `DataKinds.json`. Each entry describes one kind:

| Field | Example | Meaning |
|---|---|---|
| `feature` | `Date` | the feature that uses the data (from a fixed list, section 4) |
| `data` | `Names` | the class of data (from a fixed list) |
| `item` | `Month` | what exactly (from a fixed list for each feature) |
| `calendar` | `Chinese` | only for calendar data, from `Calendar.Identifier` |
| `version` | `1` | the version of the table layout |
| `attributes` | `abbreviated, narrow, wide, standalone…` | the keys inside the data, chosen at run time |
| `source` | the CLDR files and fields that the data comes from | for the converter |
| `option` | `calendar=chinese`, `feature=dates` | the plain words that a user selects it with |

**Nobody types a name.** A tool makes everything from the registry:
* the name, by the rule of section 4,
* the Swift type for the kind (the marker), which today is written by hand in `Markers.swift`,
* the list that the generator uses to make the data,
* the user options (`--features`, `--calendars`), and which kinds each option keeps.

So the name, the type and the user options can never disagree.

## 4. The naming rule

```
<Feature><Data><Item>[<Calendar>]V<version>
```

Each part is one word from a fixed list. A new word needs a review.

| Part | Allowed words (first list) |
|---|---|
| Feature | `Date`, `Time`, `Number`, `List`, `LocaleName`, `Plural`, `Unit`, `RelativeDate`, `Collation` |
| Data | `Names`, `Patterns`, `Symbols`, `Rules`, `Eras` |
| Item | for each feature, for example for `Date`: `Month`, `Weekday`, `Year`, `DayPeriod`, `Date`, `Time`, `Glue` |
| Calendar | the cases of `Calendar.Identifier`: `Gregorian`, `Buddhist`, `Japanese`, `Hebrew`, `Chinese`, `IslamicCivil`, and the others |

| Prototype name (ICU4X) | Name by this rule |
|---|---|
| `DatetimeNamesMonthChineseV1` | `DateNamesMonthChineseV1` |
| `DatetimePatternsDateGregorianV1` | `DatePatternsDateGregorianV1` |
| `DatetimeNamesWeekdayV1` | `DateNamesWeekdayV1` |
| `DecimalSymbolsV1` | `NumberSymbolsDecimalV1` |

A user never needs these names (section 7). They are for the code and the tools.

## 5. Who decides, and by which rules

**Who:** the Foundation team defines all kinds up front, as one catalog for all of Foundation: [`MARKER-CATALOG.md`](MARKER-CATALOG.md), with the registry `docs/catalog/data-kinds.json`. Engineers use the kinds of the catalog. They do not invent names. A later change to the catalog (a new feature, a new calendar) goes through the same rules and a review of the catalog. The fixed word lists change only by that review.

**When to make a new kind, and when to use an attribute:**

| Rule | Then | Why | Example |
|---|---|---|---|
| 1. The data belongs to a separate function of the API | a separate kind | the linker removes it if the app never calls the function | date formatting, list formatting |
| 2. A developer can leave the choice out of the build | a separate kind | a build option can remove it | each calendar |
| 3. The code chooses at run time, inside one function | an attribute | separate kinds would all stay anyway (section 6 of `CONCEPT.md`) | widths of names, `.and` or `.or` of a list |
| 4. The data is always used together | one kind | fewer lookups, smaller lists | the 12 month names of one width |

Rule 3 is different from ICU4X. For example, ICU4X has 3 kinds for lists (`ListAndV1`, `ListOrV1`, `ListUnitV1`). Foundation's list style is a value at run time, so this rule gives 1 kind, `ListPatternsV1`, with the attributes `and`, `or` and `units`.

**Versions:** a new table layout gets a new version, for example `V2`. The old and the new kind can exist side by side during a change.

## 6. How the data of each kind is made

1. **Source data:** the CLDR data that Foundation uses today, with Apple's changes. The output must match today's Foundation (it does not match ICU4X: section "Compared with today's Foundation" of `prototype-large/RESULTS.md`).
2. **A converter for each kind,** named in the registry entry. It reads the source data and gives the value for each language and attribute. It leaves out a value that is the same as the value of the parent language.
3. **The generator** packs the values into the tables, and keeps only the languages and kinds that the build asks for. This is `generator/generate.py` in the prototype.
4. **The build** compiles the tables into the data module.

A converter written in Swift or Python would remove the need for Rust in the data build.

## 7. How a user chooses data

Users choose in the words of the API. A tool turns the words into kinds, by the `option` field of the registry.

| User setting | Meaning | Kinds kept |
|---|---|---|
| `locales: fr, de` (or the app's `.lproj` folders) | which languages | the entries of `fr`, `de` and their parent languages, in every kind that stays |
| `features: dates, lists` | which features | all kinds of these features |
| `calendars: gregorian, japanese` | which calendars | the calendar kinds of these calendars only |
| nothing | everything | all kinds, all languages |

Code that names its calendar as a type needs no `features` or `calendars` setting, because the linker removes unused kinds by itself.

## 8. The repository layout in swift-foundation

swift-foundation already has this kind of pipeline for one feature, list formatting:
* PR #1999 (Jeremy Schonfeld, 2026-05-29) created the data library `_FoundationInternationalizationData`, and PR #2137 (2026-08-04) made it a Swift library.
* PR #1991 (Christopher Chapman, 2026-08-21) added two tools:
  * `utils/update-list-format-data` reads a CLDR XML checkout (`CLDR_PATH`) and writes the checked-in file `Sources/FoundationInternationalization/Formatting/ListFormatData.json`.
  * `utils/build-list-format-data` turns that JSON into the Swift tables `Sources/_FoundationInternationalizationData/ListFormatData.swift`, with a `--locales` option to keep only some locales.

This design extends that pipeline to every kind of data in the catalog. It does not add a second pipeline.

```
utils/
  data-kinds.json                  the registry: every kind of data, its name, keys, attributes, user setting. In git, reviewed.
  update-locale-data               CLDR checkout -> one JSON file per kind. Extends update-list-format-data.
  update-locale-data-impl.swift
  build-locale-data                JSON -> Swift tables. Options --locales, --features, --calendars. Extends build-list-format-data.
  build-locale-data-impl.swift
  locale-data-schema.swift         the JSON format of each kind. Extends list-format-data-schema.swift.

Sources/
  _FoundationInternationalizationData/       the existing data library
    DataVersion.json               CLDR version, tool version, checksums. Generated, in git.
    Markers.swift                  the marker types, generated from the registry. In git.
    Lookup.swift                   the lookup and the locale fallback, shared by all kinds. Hand-written, like ListFormatLookup.swift today.
    JSON/                          the intermediate data: one file per kind, all locales, for example DateNamesMonthGregorianV1.json. In git.
    Generated/                     the full set of tables, all locales, one Swift file per kind. In git.
      Date/DateNamesMonthGregorianV1+Data.swift
      Number/NumberSymbolsDecimalV1+Data.swift
      List/ListPatternsJoinV1+Data.swift    (today's ListFormatData.swift)
      ...
  FoundationInternationalization/            the code that uses the kinds, for example the date formatter

Tests/
  FoundationInternationalizationTests/LocaleData/   expected outputs, to catch changes when CLDR changes. In git.
```

**Not in the repository:**
* **The CLDR checkout.** The tools read it from `CLDR_PATH`, as `update-list-format-data` does today. `DataVersion.json` records which version was used. The checkout could be Apple's CLDR data.
* **Cut sets for a smaller app.** A build plugin or a package trait runs `build-locale-data` with the settings of the app (section 7), and writes the tables into the build folder, not into the repository.

**How the work flows:**
1. **A CLDR update:** run `update-locale-data`, then `build-locale-data`. Review the changes in the JSON files and in the expected test outputs, then commit.
2. **A normal build:** uses the full set in `Generated/` as it is. No tool runs.
3. **A build for a smaller app:** sets `locales`, `features` and `calendars`. The plugin makes the tables for that build.

**A change from the prototype:** the marker types live in `_FoundationInternationalizationData`, next to their tables. In swift-foundation, `FoundationInternationalization` depends on the data library, not the other way around. With the types and the tables in the same library, the data needs no conformances that another module adds (`@retroactive` in the prototype).

**Open points of the layout:**
* **Size.** The 25 date kinds of the prototype are 3.9 MB of Swift source for about 1 MB of data, and they compile in about 13 seconds. All of Foundation, with collation, time zone names and locale names, could be tens of MB of source. A compact binary form, checked in instead of Swift literals, may be better.
* **Where the JSON lives.** Today `ListFormatData.json` is in `FoundationInternationalization/Formatting/`. One folder for all intermediate data is cleaner, but the package manifest must exclude it from the target.
* **The comment in `update-list-format-data`** still says that the second tool writes "a packed C header". It now writes Swift.

## 9. Removing duplicates

There are two ways to avoid storing the same data many times.

**Way A: sparse data, with a parent walk for every value.** A locale stores only the entries that differ from its parent's. The lookup walks the parent chain (`fr-CA`, `fr`, root) for each value. ICU4X, the prototype, and the list data of PR #1991 (merged) work this way.

**Way B: fully resolved data, with no parent walk for values.** Every locale in the data has a complete row. Identical values are stored once and shared. A formatter resolves the locale identifier **once**: it follows a redirect (a CLDR parent locale, an alias, or a script fallback such as `en_Latn_GB` to `en_GB`), or drops the last subtag, until it finds a locale in the data. After that, every value comes from that locale's row. Chris's open PR #2330 works this way, for the date data (`DateFormatLookup.swift`: "resolved through CLDR inheritance for every locale", and "locales with identical months, for example, share one block") and for the list data (`ListFormatLookup.swift`: "each locale stores its resolved rows").

**Proposal: way B, as in #2330.** It is simpler and faster at run time, and it makes the cut by locale simpler:

| | Way A (prototype, ICU4X) | Way B (#2330, proposal) |
|---|---|---|
| Lookup of a value | a parent walk, for each kind and each attribute | one index into the locale's row |
| Locale resolution | in every lookup | once, when the formatter is made |
| Cut by locale | must also keep each parent locale, because values come from it at run time | keeps only the rows of the listed locales and the values that they use |
| Risk | the walk at run time must match the walk of the generator exactly | the generator does all resolution, so there is nothing to match at run time |
| Cost | entries only where a locale differs | one index for each locale in each kind |

**How way B fits the pieces of this design:**
* Each kind keeps its **own row table** (locale number to value number) and its **own shared values**. #2330 has one row per locale for all its groups of data, which ties the groups together, so the linker cannot remove one group. With one row table per kind, the linker can still remove a kind that the code never reaches.
* All kinds share **one locale list and one redirect table**. The formatter resolves the identifier to a locale number once, and that number works in every kind's row table.
* The cost of full rows is one small index per locale and kind. For example, about 400 locales with 2 byte indexes is about 800 bytes per kind. This is an estimate, not measured.

**The other layers, from Chris's list tools:**

| Layer | Proposal |
|---|---|
| Resolve CLDR inheritance at build time (`↑↑↑` markers, missing parts) | yes, the generator does all of it (way B) |
| Store each text once | one pool for each group of kinds that are always kept together. Each feature keeps its own pool, so a build can still remove a feature that the app never calls. |
| Store each value once | the same groups. Locales with the same values point to one copy. |
| Store each locale name once | one locale list for all kinds. Rows and redirects use locale numbers. |
| Store a whole kind once if another kind has the same data | yes: the calendar points to the existing kind, for example `Buddhist.MonthNames = DateNamesMonthGregorianV1`. The registry records "same as". |
| Do not store what the code can compute | keep as a rule, as the list data does for Spanish "y" to "e", and for Hebrew and Thai |
| A self-check in the generator | check that every locale's row equals the CLDR resolution of that locale |

**The largest gain measured: whole kinds that are the same.** In the prototype data, the Buddhist and Japanese month names are identical to the Gregorian month names in all 1,139 entries: 148,048 bytes, 15% of all date data (1,020,314 bytes). The Hijri month names share only 9 of 289 entries, and the Hebrew ones none. ICU4X gets part of this gain by accident: LLVM merges equal constants, which is the likely reason why its any calendar data was smaller (`prototype-large/RESULTS.md`, section 2).

**Sharing across calendars** costs nothing behind Foundation's value API, because that API keeps all calendars anyway (`CONCEPT.md`, section 4). A cut by calendar is a build step, and the generator makes the shared values again for the calendars that stay.

**Not measured:** the size of way B against way A for the prototype data, and the gains of the shared pools.

## 10. Open questions for the team

1. Is one registry file acceptable as the source of truth for the Swift types?
2. Who owns the word lists?
3. Should the names follow ICU4X, for easier comparison, or this rule?
4. Where would the source data and the converters live?
5. How do package traits or a build plugin pass the user setting to the generator?
