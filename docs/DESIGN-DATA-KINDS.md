# Draft design: the kinds of data, their names, and who defines them

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

## 8. Open questions for the team

1. Is one registry file acceptable as the source of truth for the Swift types?
2. Who owns the word lists?
3. Should the names follow ICU4X, for easier comparison, or this rule?
4. Where would the source data and the converters live?
5. How do package traits or a build plugin pass the user setting to the generator?
