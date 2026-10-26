# swift-data-markers-prototype

Can Swift use the data design of [ICU4X](https://github.com/unicode-org/icu4x), so that an app keeps only the locale data that it uses? This repository answers the question with two prototypes, and measures Swift against Rust and against ICU4X itself.

In ICU4X, each kind of locale data (for example "the month names of the Japanese calendar") is its own type, a **marker**. Code that never uses a marker never refers to its data, so the linker removes that data from the app. A tool can also cut the data to a list of locales before the build.

Two ICU4X documents explain this design:
* [Principles of data architecture](https://github.com/unicode-org/icu4x/blob/747356078891d513c1f731320e3d0e1ee9912e33/documents/process/data_architecture.md): what markers, locales and attributes are, how each one slices the data, and why a choice at run time links in all the data.
* [Data management tutorial](https://github.com/unicode-org/icu4x/blob/747356078891d513c1f731320e3d0e1ee9912e33/tutorials/data-management.md): how an app generates its data, finds its markers with `--markers-for-bin`, and cuts the data by locale.

Both links point to the ICU4X commit that the prototypes use.

## The answers

| Question | Answer |
|---|---|
| Does the design work in Swift? | **Yes.** A marker is an `enum` with no cases, and a separate data module gives each marker its tables. |
| Does the linker remove unused markers? | **Embedded Swift: yes**, with no extra flags. **Normal Swift: only with 3 flags** together: `-Xfrontend -internalize-at-link -Xfrontend -conditional-runtime-records -lto=llvm-full`. |
| Is the output correct? | **Yes.** A date formatter for 6 calendars gives the same text as ICU4X on 327,888 of 327,888 test cases. |
| Data size | About the same as ICU4X: the tables are 1.11x the size of the ICU4X data. |
| Code size | Smaller than ICU4X: 19,736 bytes against 77,416 bytes for a Gregorian date formatter (normal Swift with the 3 flags). |
| Speed | A little faster than ICU4X: 82 ns against 98 ns to format a date (`-O` and the 3 flags). A Rust copy of the same Swift design is 1.3x to 2x faster than the Swift. |
| Does it work behind an API like Foundation's? | **Yes**, with the same output. But a value API (`Calendar(identifier:)`, a format style) keeps the data of every calendar. Only a cut at build time makes the data small. |

The details are in [`prototype/PROTOTYPE-RESULTS.md`](prototype/PROTOTYPE-RESULTS.md) (the small prototype) and [`prototype-large/RESULTS.md`](prototype-large/RESULTS.md) (the large prototype).

## The two prototypes

| | Small prototype (`prototype/`) | Large prototype (`prototype-large/`) |
|---|---|---|
| Question | Does the linker remove unused markers? | Swift against Rust and ICU4X: correctness, data size, code size, speed |
| Scope | 4 markers: month and weekday names, 2 calendars | A date formatter: 6 calendars, 4 field sets, 25 ICU4X markers |
| Data | Made from CLDR by a Python script | Made from the JSON output of `icu4x-datagen`, so all implementations use the same data |
| Implementations | Swift | Swift (normal and Embedded), a Rust copy of the Swift design, and ICU4X |
| Start with | `prototype/PROTOTYPE-RESULTS.md` | `prototype-large/RESULTS.md`, then `prototype-large/README.md` |

## How it works

The example is an app that formats 2026-10-23 in the Chinese calendar, in French, with the medium length. It prints `14 9yuè bing-wu`. The code is in `prototype-large/`.

**1. The source data.** `icu4x-datagen` reads CLDR and writes one small JSON file for each marker, attribute and locale. For example, `datetime/names/month/chinese/v1/3/fr.json` holds the abbreviated French names of the Chinese months. There is no file for a locale whose data is the same as its parent's.

**2. The generator picks what to keep.** `generator/generate.py` keeps the markers of `--markers` and the locales of `--locales`. For each locale, it also keeps the locales that a lookup falls back to, with the rules of ICU4X: for `fr`, that is `fr` and `und` (the root).

**3. The generator packs each marker into 5 tables.** One pool holds every text once (for example `9yuè`). Sorted keys (locale, separator, attribute) lead to the values. Values are 32 bit words: a kind, counts, and references to the texts. The generator also parses the patterns: `d MMM U` becomes 5 items.

**4. The generator writes Swift code.** Each marker gets an extension with its tables: `extension DatetimeNamesMonthChineseV1: BakedDataMarker { static let pool: [UInt8] = [...] ... }`. A second file declares the calendars and field sets whose markers are all in the data: `extension Chinese: BakedCalendar {}`.

**5. The build.** The app writes `FixedCalendarFormatter<Chinese, YMD>(locale: "fr", length: .medium)`. The type `Chinese` names its markers, so this code refers only to the Chinese tables and the decimal tables. The linker removes the other tables. If the data has no Chinese tables, the app does not compile.

**6. Making the formatter, at run time.** It finds the date pattern for the key `fr` + `ym0d`, and picks `d MMM U`. Then, for each field, it loads the names. The month names come from `fr`. The cyclic year names are not in `fr`, so the lookup falls back to `und`. The formatter keeps only positions in the tables, and copies no text.

**7. Formatting, at run time.** The Chinese calendar gives day 14 of month 9 of cyclic year 43. The pattern writes `14`, a space, `9yuè`, a space, and `bing-wu`.

The API of the formatter is written by hand and is the same in every build. The generator makes only data, and the declarations that the data is there.

## How to slice the data

Run the commands in `prototype-large/`, after `. ../env.sh`.

```
# All markers, all locales
python3 -I -B generator/generate.py --fs icu4x-data/fs-recommended --fallback icu4x-data/fs-fallback --out data/full

# Only French, German and Japanese (and the locales that they fall back to)
python3 -I -B generator/generate.py --fs icu4x-data/fs-recommended --fallback icu4x-data/fs-fallback --locales fr,de,ja --out data/cut-fr-de-ja

# Only the Chinese calendar, for French: 3,849 bytes of tables, against about 73 KB for all locales
python3 -I -B generator/generate.py --fs icu4x-data/fs-recommended --fallback icu4x-data/fs-fallback \
  --markers DatetimeNamesMonthChineseV1,DatetimeNamesYearChineseV1,DatetimePatternsDateChineseV1,DecimalSymbolsV1,DecimalDigitsV1 \
  --locales fr --out data/cut-fr-chinese
```

| Option | Keeps |
|---|---|
| `--markers A,B` | only these markers |
| `--locales fr,de` | these locales, and every locale that a lookup for them can try. For example, `fr-CA` keeps `fr-CA`, `fr` and `und`. |
| `--attributes 3,5` | only these widths and lengths |
| `--replace` | allows writing over an earlier run in the same folder |

For an app with the typed API, the marker list can come from the app itself: `tools/build-cut.sh` builds the app with all data, reads the markers that the linker kept, and builds again with only those markers. This is what `--markers-for-bin` does in ICU4X.

Know these limits:
* **The build cannot cut locales by itself.** The locale is a value at run time. The developer must give `--locales`. ICU4X has the same limit.
* **A locale that was cut gives no error.** It falls back to the root data, so the text is not in the language of the user.
* **A value API keeps every calendar.** Code that picks the calendar from a value must refer to all calendars. With a value API, the developer must give the marker list too.
* **Cut attributes with care.** With a value API, the styles pick the widths at run time.

`prototype-large/RESULTS.md`, section "Limits of the automatic cut, and ways around them", explains these limits, and lists 6 ideas to get around them.

## What is in the repository

| Folder | Content |
|---|---|
| `prototype/` | The small prototype |
| `prototype-large/` | The large prototype. Its `README.md` lists its folders and all its commands. |
| `icu4x-experiments/` | Two small ICU4X apps and the `icu4x-datagen` runs that the background notes use |
| `docs/` | Background notes: how the date data of swift-foundation PR #2330 slices, how it compares with ICU4X, and a step by step guide to the ICU4X data (`ICU4X-DATA-GUIDE.md`) |
| `env.sh` | Sets the paths of the tools. Run `. ./env.sh` first. |
| `NOTES.md` | Internal notes of the people who made the prototypes |

## Rebuild after a fresh clone

The repository has the sources, the generated tables, the results and the logs. A rebuild also needs these parts, which are not in the repository:

| Part | Where it goes | Source |
|---|---|---|
| Rust 1.99.1 | `tools/rust/` | `rustup-init` from `https://static.rust-lang.org/rustup/dist/aarch64-apple-darwin/rustup-init`, run with `RUSTUP_HOME` and `CARGO_HOME` from `env.sh`, and `-y --no-modify-path --profile minimal --default-toolchain stable` |
| ICU4X | `tools/icu4x-src/` | `github.com/unicode-org/icu4x` at commit `747356078891d513c1f731320e3d0e1ee9912e33` |
| `icu4x-datagen` | `tools/bin/` | `cargo build --release -p icu4x-datagen` in `tools/icu4x-src`, once with and once without `--features unstable` |
| CLDR 49.0.0-BETA4 | `data/cldr-49.0.0-BETA4/` | `cldr-49.0.0-BETA4-json-full.zip` from the releases of `github.com/unicode-org/cldr-json`, unpacked into `full/` |
| tzdata 2026e | `data/tzdata-2026e/` | `https://www.iana.org/time-zones/repository/releases/tzdata2026e.tar.gz`, unpacked into `root/` |
| Embedded Swift | `/Library/Developer/Toolchains/` | the snapshot `swift-DEVELOPMENT-SNAPSHOT-2026-06-24-a` from swift.org |
| Normal Swift | | Swift 6.5, the default toolchain of Xcode |
| The JSON data of the large prototype | `prototype-large/icu4x-data/` | the two `icu4x-datagen` commands in `prototype-large/README.md` |

The builds of the large prototype are in `prototype-large/tools/run-all.sh`.

**Paths.** `env.sh`, the shell scripts and the `Cargo.toml` files use the absolute path `/Users/draganm4/Projects/dra8an/swift-data-markers-prototype`. In a clone at another path, change `PROTO` in `env.sh`, the paths at the top of the scripts, and the `path =` entries in the `Cargo.toml` files.

**Platform.** The prototypes were built and measured on an Apple silicon Mac with macOS 27. The Embedded Swift builds use the target `arm64-apple-macos15`.

## Licenses

* The generated tables (`prototype/data/`, `prototype-large/data/`, `icu4x-experiments/runs/`) contain CLDR data, under the [Unicode License v3](https://www.unicode.org/license.txt).
* `icu4x-experiments/guide-tools/decode.py` is a port of ICU4X code. The apps in `icu4x-experiments/apps/` and `prototype-large/icu4x-apps/` use ICU4X. ICU4X is under the Unicode License v3 too.
* tzdata is in the public domain.
