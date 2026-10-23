# How ICU4X stores, finds and cuts its data: a step by step guide

**Date:** 2026-10-21. **ICU4X:** commit `747356078891d513c1f731320e3d0e1ee9912e33` (the `main` branch on that day). **Local clone:** `/tmp/deep-review/icu4x-src`.

## The example

This guide follows one request from start to end: **the wide month names of the Japanese calendar, in Korean (`ko`).** In Korean these names are `1월`, `2월` and so on, up to `12월`.

The guide has 7 steps:

1. The data file on disk.
2. The marker, which names this kind of data.
3. The attribute, which names the width (wide, abbreviated and so on).
4. How the app asks for the data, and how the data is found.
5. How the tool `icu4x-datagen` finds markers.
6. How the tool cuts the data with `--locales` and `--attribute-filter`.
7. How an app gets only this data, without the full data of ICU4X.

**How I checked each step.** For steps 1 to 6, I read the source of ICU4X. I also decoded the real data file with a Python port of the ICU4X reader code (`icu4x-guide-tools/decode.py`). The port first passes the example in the ICU4X format notes. Then it finds all 1,139 keys of the file and reads each one back.

On 2026-10-23 I also ran everything. I installed Rust 1.99.1 and built `icu4x-datagen` from the same ICU4X commit. Then I ran the command of step 6 with the CLDR data `49.0.0-BETA4` (the version that this commit is tested with), and built two small apps for step 7. The section "Results of the runs" at the end lists what each run showed. The apps, the generated data and the logs are in `icu4x-guide-tools/`.

## Step 1. The data file on disk

### 1.1 One file for each kind of data

The month names of the Japanese calendar are in one file:

```
provider/data/datetime/data/datetime_names_month_japanese_v1.rs.data
```

The file is Rust source code, written by a tool. It is 247,823 bytes long. Every kind of data has a file like this. For example, the month names of the Gregorian calendar are in `datetime_names_month_gregorian_v1.rs.data`, and the weekday names are in `datetime_names_weekday_v1.rs.data`.

### 1.2 What the file contains

The file defines one macro. This is its outline, with the long parts left out:

```rust
macro_rules! __impl_datetime_names_month_japanese_v1 {
    ($ provider : ty) => {
        impl $provider {
            const DATA_DATETIME_NAMES_MONTH_JAPANESE_V1: icu_provider::baked::zerotrie::Data<icu::datetime::provider::names::DatetimeNamesMonthJapaneseV1> = {
                const TRIE: ZeroTrieSimpleAscii<&'static [u8]> = ZeroTrieSimpleAscii { store: b"\xE1zabcdefghij..." };
                const VALUES: &'static [MonthNames] = &[ MonthNames::Numeric, MonthNames::Linear(...), ... ];
                unsafe { Data::from_trie_and_values_unchecked(TRIE, VALUES) }
            };
        }
        impl icu_provider::DataProvider<icu::datetime::provider::names::DatetimeNamesMonthJapaneseV1> for $provider {
            fn load(&self, req: DataRequest) -> Result<DataResponse<...>, DataError> { ... }
        }
    };
}
```

A macro does nothing by itself. When some code calls it with the name of a type, for example `impl_datetime_names_month_japanese_v1!(Baked)`, the macro adds two things to that type:

1. A constant, `DATA_DATETIME_NAMES_MONTH_JAPANESE_V1`, which holds the data.
2. A function, `load`, which finds an entry in that data.

The constant has two parts, `TRIE` and `VALUES`. The comment at the top of the file gives their sizes:

```
/// * 4921B for the lookup data structure (1139 data identifiers)
/// * 75502B[^1] for the actual data (527 unique structs)
```

`TRIE` is a lookup table. It turns a key into a number. `VALUES` is an array of month name lists, and the number from `TRIE` is a position in that array.

### 1.3 VALUES: the month names

`VALUES` has 527 entries. Each entry is a `MonthNames`, which is an enum from `components/datetime/src/provider/names.rs`. The two kinds of entries in this file are:

1. `MonthNames::Numeric`: no names. The month is written as a number.
2. `MonthNames::Linear(...)`: a list of names, one for each month.

The Korean entry is number 95. In the file it is a list of bytes:

```
0C 00 04 00 08 00 0C 00 10 00 14 00 18 00 1C 00 20 00 24 00 29 00 2E 00
31 EC 9B 94 32 EC 9B 94 33 EC 9B 94 ... 31 32 EC 9B 94
```

These bytes are a `VarZeroVec16` (from `utils/zerovec/src/varzerovec/components.rs`). The layout is:

| Bytes | Meaning |
|---|---|
| `0C 00` | The number of names: 12. |
| `04 00`, `08 00`, ..., `2E 00` | Where each name after the first starts in the text: 4, 8, 12, 16, 20, 24, 28, 32, 36, 41, 46. The first name always starts at 0, so it has no entry. |
| `31 EC 9B 94 32 EC 9B 94 ...` | The text, in UTF-8. `31` is `1`, and `EC 9B 94` is `월`. |

So name 1 is bytes 0 to 3 of the text (`1월`), name 2 is bytes 4 to 7 (`2월`), and name 10 is bytes 36 to 40 (`10월`). The code reads a name directly from these bytes, without a copy.

### 1.4 TRIE: from a key to a position in VALUES

**The key.** A key is the locale, then the byte `0x1E`, then the attribute. The attribute names the width (step 3). For wide Korean month names, the key is these 4 bytes:

```
6B 6F 1E 35        ("ko", then 0x1E, then "5")
```

This comes from `provider/core/src/baked/zerotrie.rs`. There, `ID_SEPARATOR` is `0x1E`, and the function `get_index` writes the locale, then the separator, then the attribute.

**The table.** `TRIE` is a `ZeroTrieSimpleAscii`. It is a list of nodes in one array of bytes. The format notes in `utils/zerotrie/src/reader.rs` define 4 kinds of nodes, and the top bits of the first byte of a node give its kind:

| First byte | Kind | What it does |
|---|---|---|
| `0xxxxxxx` | ASCII | Matches one letter of the key. |
| `100xxxxx` | Value | The key ends here, and this is its number. |
| `11xxxxxx` | Branch | The key can go on with one of several bytes. A list of those bytes follows, then a table of where each one goes. |
| `101xxxxx` | Span | Not used in this kind of table. |

A number in a node can take more than one byte. Then the next byte adds 7 more bits, and a fixed amount is added (`utils/zerotrie/src/varint.rs`).

**The lookup of `ko`, `0x1E`, `5`.** This is the real walk through the table, from the decoder:

| Position | Bytes | Meaning |
|---|---|---|
| 0 | `E1 7A` | A branch with 26 edges, the letters `a` to `z`. Its jumps take 2 bytes each. The key starts with `k`, which is edge 10, so the walk jumps to position 2106. |
| 2106 | `E1 6D` | A branch with 13 edges (`abegikmnosuxy`), the second letters of locales that start with `k`. The next byte of the key is `o`, which is edge 8, so the walk jumps to position 2374. |
| 2374 | `C2 1E 6B 15` | A branch with 2 edges: `0x1E` (the key ends its locale here) and `k` (for a longer locale such as `kok`). The next byte of the key is `0x1E`, so the walk takes edge 0. |
| 2378 | `C3 33 34 35 05 0A` | A branch with 3 edges: `3`, `4` and `5`. The next byte of the key is `5`, so the walk takes edge 2, which starts at position 2394. |
| 2394 | `90 4F` | A value node. `0x90` means "value, and one more byte follows". `0x4F` is 79, and the format adds 16, so the value is **95**. |

The key ends at the value node, so the result is 95, and `VALUES[95]` is the list `1월` to `12월`.

### 1.5 What else the table says about Korean

The table has 6 keys for Korean, and all of them lead to the same entry:

| Key | Width | Position in VALUES |
|---|---|---|
| `ko` `0x1E` `3` | abbreviated | 95 |
| `ko` `0x1E` `3s` | abbreviated, standalone | 95 |
| `ko` `0x1E` `4` | narrow | 95 |
| `ko` `0x1E` `4s` | narrow, standalone | 95 |
| `ko` `0x1E` `5` | wide | 95 |
| `ko` `0x1E` `5s` | wide, standalone | 95 |

Korean uses the same names for every width, so the file stores the names once and points to them 6 times. That is why the file has 1,139 keys but only 527 entries.

There is no key `ko` `0x1E` `1` (numeric months). For that request, the `load` function goes to a more general locale (step 4.5). In this file, the most general locale is `und` ("undetermined", also called root), and `und` `0x1E` `1` leads to entry 0, `MonthNames::Numeric`.

The file has 215 locales. A locale with a region is written with a hyphen, for example `ar-DZ` `0x1E` `5`.

## Step 2. The marker

### 2.1 The declaration

The file in step 1 belongs to the marker `DatetimeNamesMonthJapaneseV1`. It is declared in `components/datetime/src/provider/names.rs`:

```rust
icu_provider::data_marker!(
    /// `DatetimeNamesMonthJapaneseV1`
    /// ...
    DatetimeNamesMonthJapaneseV1,
    MonthNames<'static>,
    #[cfg(feature = "datagen")]
    attributes_domain = "datetime_month_length"
);
```

The declaration gives three things: the name `DatetimeNamesMonthJapaneseV1`, the type of the data `MonthNames<'static>` (the enum of step 1.3), and the attribute domain `datetime_month_length` (step 3).

### 2.2 What the macro makes

The macro `data_marker!` is in `provider/core/src/marker.rs`. It makes three things:

1. **An empty struct** called `DatetimeNamesMonthJapaneseV1`. It holds no data. Its only job is to be a name that the compiler knows.
2. **`DataStruct`**, the type of the data of this marker: `MonthNames<'static>`.
3. **`INFO`**, a constant of type `DataMarkerInfo` with these fields:

| Field | Value for this marker | Meaning |
|---|---|---|
| `id` | `74 64 6d 68 d9 c0 92 11` | The ID (step 2.3). |
| `is_singleton` | `false` | The data depends on the locale. |
| `has_checksum` | `false` | No checksum. |
| `fallback_config` | the default | How to find a more general locale (step 4.5). |
| `attributes_domain` | `"datetime_month_length"` | The family of attributes (step 3). This field exists only in builds with the `export` feature, such as the data tool. A normal app does not have it. |

### 2.3 The ID

The ID is 8 bytes. The first 4 bytes are always `74 64 6d 68`, the letters `tdmh`. The last 4 bytes are a 32-bit hash of the name, with the function `fxhash_32` in `provider/core/src/marker.rs`. For this marker:

```
name:  "DatetimeNamesMonthJapaneseV1"
ID:    74 64 6d 68  d9 c0 92 11
       t  d  m  h   └ hash of the name ┘
```

I computed the hash with a Python copy of `fxhash_32`. The copy gives the same results as the tests in `marker.rs`, for example `[212, 77, 158, 241]` for the name `"BarV1"`. The tool itself confirms the result: an error message of `icu4x-datagen` printed this marker as `hash: [116, 100, 109, 104, 217, 192, 146, 17]`, which is `74 64 6d 68 d9 c0 92 11`. For comparison, the Gregorian marker `DatetimeNamesMonthGregorianV1` has the ID `74 64 6d 68 11 34 ee 22`.

The name must end in `V` and a number. A new layout of the data gets a new number, and so a new ID.

### 2.4 How the marker and the file meet

The struct of step 2.2 and the file of step 1 meet in three places:

1. The file implements `DataProvider<DatetimeNamesMonthJapaneseV1>` for the type that calls its macro (step 1.2). So the marker type decides which file answers a request.
2. `components/datetime/src/provider/mod.rs` declares the type `Baked` and calls the macro: `impl_datetime_names_month_japanese_v1!(Baked)`. So `Baked` holds the data, and it answers requests for this marker.
3. That code is active only with the Cargo feature `compiled_data`, which is on by default. It takes the macros from the crate `icu_datetime_data`, which includes `data/mod.rs`, which includes the `.rs.data` files.

## Step 3. The attribute: the width

One marker holds all widths of the month names. The attribute in the key says which width. The values are in `components/datetime/src/provider/semantic_skeletons.rs`:

| Attribute | Width | Context |
|---|---|---|
| `1` | numeric | |
| `3` | abbreviated | format |
| `4` | narrow | format |
| `5` | wide | format |
| `6` | short | format |
| `3s`, `4s`, `5s`, `6s` | the same widths | standalone |

"Format" names are used inside a date ("18 September"). "Standalone" names are used alone, for example in a calendar heading.

**A warning about the comment on the marker.** It says that the attribute is "the number of characters in the equivalent CLDR field syntax name". That is not true for all values. The CLDR pattern for wide is `MMMM` (4 letters), but its attribute is `5`. The CLDR pattern for narrow is `MMMMM` (5 letters), but its attribute is `4`. The list of values in the same comment is correct.

**The domain.** `attributes_domain = "datetime_month_length"` names this family of attributes. The month markers of the other calendars (Gregorian, Hebrew and so on) use the same domain. So one filter on this domain applies to the month names of every calendar (step 6.3).

## Step 4. How the app asks for the data, and how it is found

### 4.1 The app code

```rust
let mut names = FixedCalendarDateTimeNames::<Japanese>::try_new(locale!("ko").into())?;
names.load_month_names(&provider, MonthNameLength::Wide)?;
```

`FixedCalendarDateTimeNames` is in `components/datetime/src/pattern/names.rs`. The app gives three things:

1. The calendar, as a type: `Japanese`.
2. The locale, as a value: `ko`.
3. The width, as a value: `MonthNameLength::Wide`.

### 4.2 The calendar type gives the marker

`components/datetime/src/scaffold/calendar.rs` connects each calendar to its markers:

```rust
impl CldrCalendar for cal::Japanese {
    type YearNamesV1 = DatetimeNamesYearJapaneseV1;
    type MonthNamesV1 = DatetimeNamesMonthJapaneseV1;
    ...
}
```

`load_month_names` asks for `C::MonthNamesV1`. With `C = Japanese`, that is `DatetimeNamesMonthJapaneseV1`. The compiler makes this choice. Nothing happens at run time.

### 4.3 The width value gives the attribute

`MonthNameLength::Wide.to_attributes()` returns the attribute `5` (step 3).

### 4.4 The request

The inner `load_month_names` builds the request from the locale and the attribute:

```rust
let attributes = length.to_attributes();                                   // "5"
let locale = provider.bound_marker().make_locale(prefs.locale_preferences); // ko
let req = DataRequest {
    id: DataIdentifierBorrowed::for_marker_attributes_and_locale(attributes, &locale),
    ..Default::default()
};
```

Then it calls `load` on the provider, for the marker of step 4.2.

### 4.5 The provider finds the entry

The `load` function from the file of step 1 does this:

1. It asks the table for the key `ko` `0x1E` `5`, as in step 1.4. The result is 95.
2. It returns `VALUES[95]`, the list `1월` to `12월`.

If the key is not in the table, `load` tries more general locales. It uses `LocaleFallbacker`, with the `fallback_config` of the marker. For example, a request for `ko` `0x1E` `1` finds no key, so `load` tries `und` `0x1E` `1` and returns entry 0, `MonthNames::Numeric`. If no locale has data, `load` returns the error `IdentifierNotFound`.

### 4.6 Why the ID is in the app

The error of step 4.5 passes the `INFO` of the marker along:

```rust
return Err(icu_provider::DataErrorKind::IdentifierNotFound.with_req(<DatetimeNamesMonthJapaneseV1 as DataMarker>::INFO, req));
```

So every app that contains this `load` function also contains the 8 bytes of the ID, `74 64 6d 68 d9 c0 92 11`. Step 5.2 uses this.

### 4.7 Why an unused marker is not in the app

The app in step 4.1 names one marker type, through `Japanese`. The compiler includes the `load` function and the data constant of that marker, because the code calls them. It does not include the markers that no code names, for example the Hebrew month names. The ICU4X tutorial says this for compiled data: "the compiler will remove unused markers" (`tutorials/data-management.md`, line 255).

The compiler cannot remove locales or widths in this way. The locale `ko` and the width `Wide` are values, chosen at run time, and the code finds them in the table at run time. So the app keeps the whole table of this marker: 215 locales and every width, about 80 KB (4,921 + 75,502 bytes, from step 1.2). To keep less, the data must be cut before the build (step 6).

## Step 5. How icu4x-datagen finds markers

The tool can be told the markers in two ways. Both end with the `INFO` of each marker.

### 5.1 By name: `--markers`

```
icu4x-datagen --markers DatetimeNamesMonthJapaneseV1 ...
```

The function `marker_lookup()` in `provider/icu4x-datagen/src/main.rs` builds a map from a name to the `INFO` of every marker that the tool knows. Each marker is in the map twice: with its full Rust path, and with its short name. The tool looks up each name that you give:

| Name | Result |
|---|---|
| in the map | the `INFO` of that marker |
| a marker that needs the Cargo feature `unstable` | the error `Marker ... requires unstable Cargo feature` |
| not in the map | the error `Unknown marker` |
| `all` | every marker |
| `none` | no marker |

### 5.2 From a built app: `--markers-for-bin`

```
icu4x-datagen --markers-for-bin target/release/myapp ...
```

The function `markers_for_bin` in `components/icu/src/datagen.rs` does three things:

1. It builds a map from the 4-byte hash of each marker that it knows to the `INFO` of that marker.
2. It reads the file of the app as bytes, and finds each place where the 4 bytes `tdmh` occur.
3. It takes the 4 bytes after each `tdmh` and looks them up in the map. A match is a marker that the app uses. Bytes with no match are not markers, and the tool skips them.

For the app of step 4.1, it would find `74 64 6d 68 d9 c0 92 11`, because of step 4.6. So it would find `DatetimeNamesMonthJapaneseV1`. This works only because of step 4.7: the IDs of the markers that the app does not use are not in the app.

`--markers-for-bin` finds markers, not locales or widths, because those are values (step 4.7).

**The real run** on the two apps of step 7:

| App | `tdmh` tags in the app | Markers that the tool found |
|---|---:|---|
| A (built-in data, `try_new`) | 4 | `DatetimeNamesMonthJapaneseV1`, `DecimalSymbolsV1`, `DecimalDigitsV1` |
| B (own provider, `new_without_number_formatting`) | 2 | `DatetimeNamesMonthJapaneseV1` |

The ID of the Japanese month marker is in each app twice, so app A has 4 tags but 3 markers. App A also has the 2 number formatting markers, because `try_new` loads a number formatter. App B does not, because `new_without_number_formatting` does not.

## Step 6. How the tool cuts the data

### 6.1 The command

```
icu4x-datagen --markers DatetimeNamesMonthJapaneseV1 \
              --locales ko \
              --attribute-filter datetime_month_length=/5/ \
              --format baked --out my_data
```

### 6.2 `--locales`: which locales

`--locales ko` keeps the data for Korean. The option also accepts the named sets `full`, `modern`, `recommended` (the default) and `none`. The tool also keeps the more general locales that a lookup can fall back to, such as `und`. How much it keeps of them depends on `--deduplication` (`maximal`, `retain-base-languages` or `none`). I did not read the details of these modes.

### 6.3 `--attribute-filter`: which widths

The option is `domain=/regex/`. The tool parses it in `provider/icu4x-datagen/src/main.rs`:

1. It splits the text at `=`. The left part is the domain: `datetime_month_length`.
2. A `-` before the regex means "exclude what matches". There is none here.
3. It puts the regex between `^(?:` and `)$`, so it must match the whole attribute. `/5/` becomes `^(?:5)$`. It matches `5`, but not `5s`. To keep both, use `/5|5s/`.
4. If you give several filters for one domain, an attribute must pass all of them.

Then the export code applies the filter (`provider/export/src/export_impl.rs`):

```rust
if !marker.attributes_domain.is_empty()
    && let Some(filter) = attributes_filters.get(marker.attributes_domain)
{
    supported_map.retain(|_, ids| {
        ids.retain(|id| filter(&id.marker_attributes));
        !ids.is_empty()
    });
}
```

In words: for each marker, the code reads `attributes_domain` from its `INFO`. If there is a filter for that domain, it keeps only the keys whose attribute passes the filter, and it removes a locale that has no key left. This is why `attributes_domain` exists only in builds with the `export` feature: only the data tool needs it.

### 6.4 The output

`--format baked` writes Rust files in the same form as step 1: one `.rs.data` file for each marker, and a `mod.rs` that includes them and defines the macros `make_provider!` and `impl_data_provider!` (`provider/baked/src/export.rs`). `--format blob` writes one binary file instead, which an app loads at run time.

By default, the generated code names its types through the crate `icu`, for example `icu::datetime::provider::names::DatetimeNamesMonthJapaneseV1`. The option `--use-separate-crates` uses the crates of each part instead, such as `icu_datetime::...`. The exporter's documentation says that this is "required when you are not using the `icu` crate, *and* you're building custom data providers".

### 6.5 The real output of the command

I ran the command of step 6.1, with two changes. I added `--cldr-root` with a local copy of the CLDR data, because the tool's own download did not get through the sandbox proxy. I left out `--pretty`, because it needs the `rustfmt` component, which the minimal Rust install does not have.

The trace log (`--verbose`) shows the filter and the deduplication at work:

```
Generating marker/locale: DatetimeNamesMonthJapaneseV1/ko/5
Deduplicating ko-CN/5 (inherits from ko)
Deduplicating ko-KP/5 (inherits from ko)
```

So the tool made only the width `5`. It also left out `ko-CN` and `ko-KP`, because their data is the same as `ko` ("maximal" deduplication, the default).

The output is two files:

| File | Size | Content |
|---|---:|---|
| `datetime_names_month_japanese_v1.rs.data` | 4,602 bytes | the macro of step 1.2, with 2 keys and 2 entries. The header says "45B for the lookup data structure (2 data identifiers)" and "199B for the actual data (2 unique structs)". |
| `mod.rs` | 1,199 bytes | includes the file above, and defines `make_provider!` and `impl_data_provider!`. `impl_data_provider!` calls only `impl_datetime_names_month_japanese_v1!`. |

The full file for all locales is 247,823 bytes. The lookup table is now 13 bytes:

```
C2 6B 75 04 | 6F 1E 35 80 | 6E 64 1E 35 81
branch k, u | o 0x1E 5 → 0 | n d 0x1E 5 → 1
```

| Key | Position | Names |
|---|---|---|
| `ko` `0x1E` `5` | 0 | `1월` to `12월` |
| `und` `0x1E` `5` | 1 | `M01` to `M12` (the root names) |

The tool kept `und` so that the fallback of step 4.5 still ends somewhere. App B of step 7.3, built with this data, shows how the two keys answer every locale:

| Locale asked for | Output for September | Why |
|---|---|---|
| `ko` | `9월` | the key `ko` `0x1E` `5` |
| `ko-KP`, `ko-CN` | `9월` | no key of their own. The fallback goes to `ko`. |
| `ja`, `en`, `und` | `M09` | no Korean data. The fallback goes to `und`. |

## Step 7. How an app gets only this data

There are three ways. They differ in how much the app carries, and in how much work they need.

### 7.1 The default: all data, and the compiler removes unused markers

The crate `icu_datetime` turns on `compiled_data` by default (`components/datetime/Cargo.toml`). That feature brings in the crate `icu_datetime_data` with the data of every marker, locale and width. The app of step 4.1 uses `include_month_names` instead of `load_month_names`, and passes no provider:

```rust
names.include_month_names(MonthNameLength::Wide)?;
```

Result: the app keeps only the Japanese month marker (step 4.7), but with all 215 locales and every width.

### 7.2 Replace the built-in data: `ICU4X_DATA_DIR`

The crate `icu_datetime_data` checks this variable when it is compiled (`provider/data/datetime/build.rs` and `src/lib.rs`):

```rust
#[cfg(icu4x_custom_data)]
include!(concat!(core::env!("ICU4X_DATA_DIR"), "/mod.rs"));
#[cfg(not(icu4x_custom_data))]
include!("../data/mod.rs");
```

So if `ICU4X_DATA_DIR` is set, the crate uses the generated `mod.rs` instead of its own data.

**Important:** every ICU4X data crate has this code, not only `icu_datetime_data`. So `ICU4X_DATA_DIR` replaces the data of every ICU4X component that the app compiles. Each component calls the `impl_...!` macro of every one of its markers, without any condition. The generated `mod.rs` defines macros only for the markers that the tool exported. So the generated data must contain every marker of every ICU4X component in the app, or the build fails.

I tested this. App A (step 7.1) with `ICU4X_DATA_DIR` set to the output of step 6.5 does not compile. The first crate that fails is not `icu_datetime` but `icu_locale_fallback`:

```
error: cannot find macro `impl_locale_parents_v1` in this scope
error: cannot find macro `impl_locale_likely_subtags_language_v1` in this scope
error: could not compile `icu_locale_fallback` (lib) due to 4 previous errors
```

App A compiles 6 ICU4X data crates: `icu_calendar_data`, `icu_datetime_data`, `icu_decimal_data`, `icu_locale_fallback_data`, `icu_plurals_data` and `icu_time_data`. Together they have 80 markers. The tutorial matches this: it uses `--markers all` with `ICU4X_DATA_DIR`. So the working form is:

```
icu4x-datagen --markers all --locales ko --attribute-filter datetime_month_length=/5/ --format baked --out my_data
ICU4X_DATA_DIR=$(pwd)/my_data cargo build --release
```

Some of these markers need the Cargo feature `unstable` in the tool, and the time zone markers need the IANA time zone database. So the working command for app A, with the 80 markers of its 6 data crates, was:

```
icu4x-datagen --cldr-root <CLDR 49.0.0-BETA4> --tzdb-root <tzdata 2026e> \
              --markers <the 80 markers> --locales ko \
              --attribute-filter datetime_month_length=/5/ --format baked --out my_data
ICU4X_DATA_DIR=$(pwd)/my_data cargo build --release
```

The tool was built with `--features unstable`. The list of the 80 markers is in `icu4x-guide-tools/generated/app-a-markers.txt`. It comes from the names of the `.rs.data` files in the `data/mod.rs` of each data crate.

**I built app A this way.** The code of app A did not change. It prints `9월`, and the build output of all 6 data crates has `icu4x_custom_data`, so all of them used the generated data:

| App A | Code | Constant data | Total |
|---|---:|---:|---:|
| with the built-in data (7.1) | 306,300 | 120,096 | 487,363 |
| with `ICU4X_DATA_DIR`, 80 markers, `ko` only (7.2) | 305,916 | 30,856 | 397,639 |

Result: every marker, but only for Korean, and only wide format month names. The compiler then removes the unused markers, as in 7.1. The app is almost as small as app B of step 7.3 (392,359 bytes), and its code is the same as the default app.

### 7.3 Your own provider: no built-in data at all

1. In `Cargo.toml`, turn off the default features of `icu_datetime`, so `compiled_data` and the crate `icu_datetime_data` are not used.
2. Generate data for only the one marker, with the command of step 6.1.
3. Put the generated code into your own type, as the tutorial shows (`tutorials/data-management.md`):

```rust
struct MyProvider;
include!("../my_data/mod.rs");
impl_data_provider!(MyProvider);
```

4. Pass that provider to the function that loads the data:

```rust
let mut names = FixedCalendarDateTimeNames::<Japanese>::try_new(locale!("ko").into())?;
names.load_month_names(&MyProvider, MonthNameLength::Wide)?;
```

This works with one marker because `load_month_names` needs only `P: DataProvider<C::MonthNamesV1>` (step 4.2), and `MyProvider` implements exactly that one marker.

Result: the app has no data except the Korean wide format month names of the Japanese calendar, and the code that reads them.

**I built and ran this app** (app B, in `icu4x-guide-tools/app-b/`). It prints `9월` for 2026-09-18 with the pattern `MMMM`. Its `Cargo.toml` turns off the default features of `icu_datetime`, and its `main.rs` has these lines:

```rust
struct MyProvider;
include!(env!("APP_B_DATA"));          // the mod.rs of step 6.5, generated with --use-separate-crates
impl_data_provider!(MyProvider);

let mut names = FixedCalendarDateTimeNames::<Japanese>::new_without_number_formatting(locale.into());
names.load_month_names(&MyProvider, MonthNameLength::Wide)?;
```

Three details that the build showed:

1. `try_new` needs `compiled_data`. Without it, the constructor is `new_without_number_formatting`. It loads no data at all, and the pattern `MMMM` needs no number formatter.
2. The default field set of `FixedCalendarDateTimeNames` covers a date and a time, so `format` needs a `DateTime`, not only a `Date`.
3. `Japanese::new()` needs the `compiled_data` of `icu_calendar`, for the start dates of the Japanese eras. That is a separate small crate, `icu_calendar_data`, and app B keeps it. Only the datetime data is turned off.

**Sizes, release build, symbols removed** (sum of all sections, `size -m`):

| App | Code | Constant data | Total |
|---|---:|---:|---:|
| A: the built-in data of `icu_datetime` (7.1) | 306,300 | 120,096 | 487,363 |
| B: its own provider with the data of step 6.5 (7.3) | 301,948 | 29,560 | 392,359 |

App B has 90,536 bytes less constant data. That is mostly the Japanese month marker for all 215 locales (about 80 KB, step 1.2). The rest is the number formatting data that app A loads in `try_new`.

**Two details for this way:**

1. If your app does not depend on the crate `icu`, generate the data with `--use-separate-crates` (step 6.4).
2. The generated `load` function falls back with `icu_locale_fallback::LocaleFallbacker::new()`, which uses the built-in fallback data of `icu_locale_fallback`. The option `--no-internal-fallback` leaves that code out. Then a request must match a key exactly. I did not check which of the two is smaller.

### 7.4 Run the cut from the app's own build

`icu4x-datagen` is a thin wrapper around the library `icu_provider_export`. The same calls work from a build script (`build.rs`), so the cut can run during `cargo build`. The functions are in `provider/export/src/lib.rs`: `ExportDriver::new`, `with_markers`, `with_marker_attributes_filter` and `export`. In a build script, a marker is named by its type, for example `DatetimeNamesMonthJapaneseV1::INFO`, so the compiler checks the name.

## Summary: who chooses what

| What | How the app chooses it | Who removes the rest | Step |
|---|---|---|---|
| The kind of data (month names) | a type (the marker) | the compiler, automatically. `--markers-for-bin` reads the result. | 4.7, 5.2 |
| The calendar (Japanese) | a type (`FixedCalendarDateTimeNames<Japanese>`) | the same | 4.2 |
| The locale (`ko`) | a value at run time | the tool: `--locales` | 6.2 |
| The width (wide) | a value at run time (`MonthNameLength::Wide`) | the tool: `--attribute-filter` | 6.3 |

## Results of the runs

All runs were on 2026-10-23, with Rust 1.99.1 and `icu4x-datagen` built from commit `7473560788`, with the CLDR data `49.0.0-BETA4`.

| Claim of the guide | Run | Result |
|---|---|---|
| The ID of the marker is `74 64 6d 68 d9 c0 92 11` (2.3) | an error message of the tool | the tool printed `[116, 100, 109, 104, 217, 192, 146, 17]`, the same bytes |
| A marker that needs `unstable` stops the tool (5.1) | `--markers` with 80 names | `Marker "DatetimePatternsRangeTimeV1" requires unstable Cargo feature` |
| `--markers-for-bin` finds the markers of an app (5.2) | apps A and B | see the table in step 5.2 |
| The filter keeps only width `5` (6.3) | `--verbose` trace | `Generating marker/locale: DatetimeNamesMonthJapaneseV1/ko/5` |
| The output for `ko`, wide (6.5) | the command of step 6.1 | 2 keys, `ko` and `und`, in 13 bytes |
| `ICU4X_DATA_DIR` with one marker fails (7.2) | app A with that data | fails in `icu_locale_fallback`: `cannot find macro impl_locale_parents_v1` |
| `ICU4X_DATA_DIR` with all markers of the app works (7.2) | app A with the 80 markers for `ko` | prints `9월`, 89,240 bytes less data than with the built-in data |
| An app with its own provider and one marker works (7.3) | app B | prints `9월`, 90,536 bytes less data than app A |

**Three practical notes from the runs:**

1. The tool's own download of CLDR and of the time zone database did not get through the sandbox proxy (`ConnectProxyFailed`). The fix was to download both files by hand and pass `--cldr-root` and `--tzdb-root`.
2. `--pretty` failed with "No such file or directory", because it runs `rustfmt`, and the minimal Rust install does not have it.
3. The tool does not write into an output folder that is not empty (`DirectoryNotEmpty`).

## What is not verified

1. **What the three `--deduplication` modes do exactly.** The runs used only the default, `maximal`.
2. **The size effect of `--no-internal-fallback`.** In app B, `icu_calendar` brings the built-in fallback data anyway, so this test needs a different app.

## Sources

All paths are in the ICU4X repository at commit `7473560788`:

| Step | File |
|---|---|
| 1 | `provider/data/datetime/data/datetime_names_month_japanese_v1.rs.data`, `provider/core/src/baked/zerotrie.rs`, `utils/zerotrie/src/reader.rs`, `utils/zerotrie/src/varint.rs`, `utils/zerovec/src/varzerovec/components.rs` |
| 2 | `components/datetime/src/provider/names.rs`, `provider/core/src/marker.rs`, `components/datetime/src/provider/mod.rs` |
| 3 | `components/datetime/src/provider/semantic_skeletons.rs` |
| 4 | `components/datetime/src/pattern/names.rs`, `components/datetime/src/scaffold/calendar.rs` |
| 5 | `provider/icu4x-datagen/src/main.rs`, `components/icu/src/datagen.rs` |
| 6 | `provider/icu4x-datagen/src/main.rs`, `provider/export/src/export_impl.rs`, `provider/baked/src/export.rs` |
| 7 | `components/datetime/Cargo.toml`, `provider/data/datetime/build.rs`, `provider/data/datetime/src/lib.rs`, `provider/export/src/lib.rs`, `tutorials/data-management.md` |

The decoder: `icu4x-guide-tools/decode.py`. To decode a key yourself:

```
python3 -I decode.py <path>/datetime_names_month_japanese_v1.rs.data ko/5 ko/1 und/1
```
