# #2330 and ICU4X: how each one cuts locale data

**Date:** 2026-10-20. **#2330:** head `bfe992339c`. **ICU4X:** the `main` branch on GitHub, read on 2026-10-20 (sources at the end).

## Summary

ICU4X is the internationalization library in Rust from the Unicode Consortium. Like #2330, it ships CLDR data compiled into the program, and it has a tool, `icu4x-datagen`, that makes a smaller data set for the locales an app needs. So #2330 and ICU4X use the same idea:
* **The linker removes the code that an app never calls.** This is automatic in both.
* **A generator tool cuts the locales.** This needs one command in both. No linker can do it, because the app chooses the locale at run time.

The main difference: ICU4X also splits its data by kind (for example month names, or weekday names). The compiler then removes the kinds of data that the app does not use, with no tool. #2330 keeps all its kinds of data in one set of tables, so an app keeps, for example, quarter names that it never reads.

## How icu4x-datagen works

**What it is:** a command line tool. Install it with `cargo install icu4x-datagen`. Example from the tutorial:

```
icu4x-datagen --markers all --locales ja --format baked --pretty --out my_data
```

**1. The input: CLDR and ICU data.**
* `--cldr-tag` downloads the CLDR JSON data from a tag of `github.com/unicode-org/cldr-json`. The default `latest` is "the latest version verified to work with this version of the binary".
* `--cldr-root` uses a local copy instead.
* `--icuexport-tag` and `--icuexport-root` do the same for data that ICU exports (for example Unicode properties).

**2. Which locales: `--locales`.** A list of locale IDs (for example `ja`), or a named set: `full` or `modern` for the CLDR locale sets, `recommended` (the default), or `none`.

**3. Which kinds of data: markers.** ICU4X splits its data into "data markers". A marker is one kind of data, for example the month names of the Gregorian calendar.
* `--markers` takes a list of markers, `all`, or `none`. The tutorial warns that a wrong guess gives an error at run time.
* `--markers-for-bin <binary>` reads an app that is already built, and keeps only the markers that its code uses. Example: `--markers-for-bin target/release/myapp`.

**4. The output: `--format`.**
* `baked`: Rust source code, compiled into the app.
* `blob`: one binary file that the app loads at run time.
* `fs`: a folder tree of files.

**5. Other options.**
* `--deduplication`: `maximal`, `retain-base-languages` or `none`. It sets how data that is the same in several locales is stored once. I did not read the details.
* `--no-internal-fallback`: for `baked` only, it leaves out the fallback code from the generated data.
* `--trie-type` (`small` or `fast`) and `--include-collations` are for other kinds of data.

**How an app uses the output:**
* **Baked data, the easy way:** set `ICU4X_DATA_DIR` when you compile, for example `ICU4X_DATA_DIR=$(pwd)/my_data cargo run`. The generated data then replaces the data that comes with ICU4X.
* **Baked data, by hand:** `include!("../my_data/mod.rs");` and `impl_data_provider!(MyDataProvider);`, then pass that provider to a `try_new_unstable` constructor.
* **Blob data:** load the file at run time, through constructors that end in `_with_buffer_provider` (Cargo feature `serde`). This is the only way here that adds locales without a rebuild.

**The data that comes with ICU4X:** the Cargo feature `compiled_data` is on by default and includes compiled data. The `icu` README says it has "most of the data available in CLDR". The tutorial calls it a "recommended set of locales". The two documents do not say the same thing, and I did not check which one is right.

**What is automatic:** the `icu` README says that "dead-code elimination can optimize away unused compiled data". The tutorial says that for compiled data the compiler removes the unused markers, so `--markers-for-bin` is needed only for blob data.

**Sizes from the tutorial** (a blob for one locale):
* about 5 MB with `--markers all`
* 19 KB after `--markers-for-bin`
* 8 KB after a change in the app to `FixedCalendarDateTimeFormatter<Gregorian>`

About 5 KB of the last one is locale fallback data.

## What a data marker is

A data marker in ICU4X is a Rust type. It is not an enum and not a string. The docs call markers "quasi-const-generic compile-time objects" and say that they "are expected to be unit structs", that is, empty structs. Each marker names one kind of data, for example the month names of one calendar.

A macro declares a marker. This is the example from the docs:

```rust
icu_provider::data_marker!(DummyV1, &'static str);
```

The macro makes the struct `DummyV1` and attaches two things to it. The first is `DataStruct`, the Rust type of the data that the marker returns. In the example it is `&'static str`. For month names it is a struct that holds the names. The second is `INFO`, a constant of type `DataMarkerInfo`. It holds the ID of the marker, its setting for locale fallback, and a flag `is_singleton` for data that does not depend on the locale. The name of a marker must end in `V` and a number, such as `DummyV1`, so that a new layout of the data gets a new marker. A wrong name stops the compile.

The ID of a marker is 8 bytes. The first 4 bytes are always the same magic bytes, `tdmh`. The last 4 bytes are a 32-bit hash of the name of the marker. The readable name is kept only in builds with the `export` feature or with debug assertions.

Every API in ICU4X asks for its data through a marker type. When code asks for the data of a marker, the program refers to the `INFO` of that marker, and so the 8 bytes of its ID go into the program too. If no code in the app asks for a marker, nothing refers to that marker or to its data, and the compiler removes both. This is why ICU4X can drop unused kinds of data with no tool.

## How icu4x-datagen finds the markers

With `--markers`, you give the names of the markers. The tool keeps a table of every marker that it knows. The function `marker_lookup()` in `provider/icu4x-datagen/src/main.rs` builds this table as a map from a name to the `INFO` of the marker. Each marker is in the map twice, with its full Rust path and with its short name. The tool looks up each name that you give. A name that is not in the map stops the tool with the error `Unknown marker`. A name of a marker that needs the Cargo feature `unstable` stops the tool with an error that says so. The value `all` takes every marker, and the value `none` takes no marker.

With `--markers-for-bin`, the tool finds the markers in an app that is already built. The function `markers_for_bin` in `components/icu/src/datagen.rs` does this in three steps. First, it builds a map from the 4-byte hash of every marker that it knows to the `INFO` of that marker. Second, it reads the file of the app as bytes, and finds each place where the magic bytes `tdmh` occur. Third, it takes the 4 bytes after each of these places and looks them up in the map. A match is a marker that the app uses. Bytes that have no match are not markers, and the tool skips them.

This works because of the previous section. Only the IDs of the markers that the app asks for are in the built app, because the compiler removed the others. So the tool learns from the app itself which kinds of data it needs. The tutorial shows the effect on a blob for one locale: 5 MB with `--markers all`, and 19 KB with `--markers-for-bin`.

## Markers and #2330

#2330 has no markers. Its kinds of data are the values of one enum, `DateFormatDataGroup`: `numbers`, `months`, `weekdays`, `quarters`, `eras`, `dayPeriods`, `gmt` and `capitalization`. A value of this enum is only a position in the same shared tables, and the code chooses it at run time. So when an app reads only month names, the code still refers to the whole `names` and `pool` tables, and the linker keeps them whole. This is why the en_US app keeps quarter and era names that it never reads. In ICU4X, the same app would refer only to the marker for month names, and the other kinds of data would not be in the app.

## How #2330 compares

| | #2330 | ICU4X |
|---|---|---|
| **Tool** | 2 scripts: `utils/update-date-format-data` (CLDR to `DateFormatData.json`) and `utils/build-date-format-data` (JSON to `DateFormatData.swift`) | 1 tool: `icu4x-datagen` |
| **CLDR input** | a local CLDR 48 checkout (`CLDR_PATH`) | CLDR JSON, downloaded by tag or local |
| **Intermediate file** | `DateFormatData.json`, committed to the repository | none |
| **Cut by locale** | `--locales=en_US,es_US` and `--fallback=` | `--locales`, with lists or named sets (`full`, `modern`, `recommended`) |
| **Cut by kind of data** | no: all kinds share one set of tables | yes: one marker for each kind, removed automatically when not used, or chosen with `--markers` or `--markers-for-bin` |
| **Output** | Swift source, compiled into the app | Rust source (`baked`), a file loaded at run time (`blob`), or a folder (`fs`) |
| **Data that comes with the library** | all 1,071 locales | the default set (see above) |
| **Locales added at run time** | no | yes, with `blob` |
| **Data stored once** | locales share blocks of names, and each long text is stored once in `pool` | `--deduplication` |
| **Fallback** | built into the tables (redirects and parent locales), then `--fallback` or root | fallback code in the baked data (`--no-internal-fallback` removes it) |
| **Scope** | date names, digits, day periods, GMT format, capitalization, and list patterns | all ICU4X components |

## What is automatic in each

**1. Unused code: automatic in both.** In the #2330 app, the functions that the app never calls (`quarter`, `era`, `gmtFormat`, `hourFormat`, `capitalizes`, `hanidaysDay`) are not in the app (see `DATA-SLICING.md`).

**2. Unused kinds of data: automatic only in ICU4X.**
* **ICU4X** keeps each marker apart, so the compiler removes the markers that no code uses.
* **#2330** keeps all 8 kinds of data in the same tables: numbers, months, weekdays, quarters, eras, day periods, GMT format and capitalization. A table is either in the app or not. So the en_US app keeps quarter and era names that it never reads. One small table, `hanidaysDays`, is separate, and the linker removed it.

**3. Unused locales: one generator command in both.** No compiler can remove a locale when the app chooses the locale at run time. A test with #2330 shows that the compiler does not do it even when the locale is fixed: the app with all the data and `"en_US"` written into the source still has 197,808 bytes of data, the same as with the locale read at run time. With `build-date-format-data --locales=en_US` it has 2,784 bytes.

## Ideas that #2330 could take from ICU4X

* **One table for each kind of data,** so the linker removes the kinds that an app does not use. The cost is more tables, and less sharing between them.
* **Named locale sets,** such as `modern`, next to the lists in `--locales`.
* **A way to choose kinds of data,** like `--markers`.

## What I did not check

* How the baked code of ICU4X looks inside: if each marker is one static, and how a locale is found at run time.
* The exact locales in the default compiled data of ICU4X.
* The details of `--deduplication`.
* The size of an ICU4X app. I did not build one. All ICU4X numbers above are from its tutorial.

## Sources

* ICU4X tutorial: `github.com/unicode-org/icu4x/blob/main/tutorials/data-management.md`
* `icu4x-datagen` options: `github.com/unicode-org/icu4x/blob/main/provider/icu4x-datagen/src/main.rs`
* Data markers: `github.com/unicode-org/icu4x/blob/main/provider/core/src/marker.rs`
* `markers_for_bin`: `components/icu/src/datagen.rs`, at commit `747356078891d513c1f731320e3d0e1ee9912e33`
* `compiled_data` and dead-code elimination: `github.com/unicode-org/icu4x/blob/main/components/icu/README.md`
* #2330 numbers: `DATA-SLICING.md` and `RESULTS.md` in this folder.
