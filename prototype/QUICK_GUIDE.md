# Quick guide: the data marker design in Rust (ICU4X) and in Swift (this prototype)

**Date:** 2026-10-23. **Rust:** ICU4X at commit `7473560788` (`ICU4X-DATA-GUIDE.md`). **Swift:** this prototype (`DESIGN.md`, `PROTOTYPE-RESULTS.md`).

## Data structures

| | Rust (ICU4X) | Swift (prototype) |
|---|---|---|
| Marker | unit struct made by `data_marker!` | `enum` with no cases, conforming to `DataMarker` |
| Type of the data | `type DataStruct` (for example `MonthNames<'static>`) | `associatedtype DataStruct` (`NameList`) |
| Marker ID | `INFO.id`: `tdmh` and the FxHash32 of the name | the tag `dmk1` and the FNV-1a 32 of the name, as the first 8 bytes of `pool` |
| Calendar to marker | `CldrCalendar::MonthNamesV1` | `CalendarSystem.MonthNamesMarker` |
| Width | attribute string (`"5"`, `"5s"`) | the same strings |
| Key | locale, `0x1E`, attribute | the same |
| Lookup table | `ZeroTrieSimpleAscii`, a byte trie | sorted array of keys (`InlineArray<K, UInt32>`, offset and length into `pool`) |
| Values | `&'static [MonthNames]`, zero-copy `VarZeroVec` | `InlineArray` tables of offsets into one UTF-8 `pool` |
| Result of a lookup | a reference into static data, no copy | `NameList` with new `String` values (a copy) |

## Compiling and linking

| | Rust (ICU4X) | Swift (prototype) |
|---|---|---|
| Built-in data on or off | Cargo feature `compiled_data` | import the module `DateNamesData` or not |
| Data joined to a marker | `impl DataProvider<M> for Baked`, once for each marker | `extension M: BakedDataMarker`, so each marker owns its data. A Swift type can conform to a protocol only once. |
| Custom data | `include!` the generated code, plus `impl_data_provider!` | a `DataProvider` value for one marker |
| Swap the built-in data | `ICU4X_DATA_DIR` with `include!` at compile time | the build compiles another data folder. Swift has no `include!`. |
| Generic code | specialized for each type (monomorphization) | `@inlinable`, specialized in the app. Embedded Swift always specializes. |
| Unused markers removed | automatically, by dead code removal | Embedded Swift: automatically. Normal Swift: only with `-internalize-at-link`, `-conditional-runtime-records` and `-lto=llvm-full` together. |
| Missing data for a marker | error at run time | error at compile time |

## Algorithms

| | Rust (ICU4X) | Swift (prototype) |
|---|---|---|
| Lookup | a walk through the trie, one byte at a time | binary search, comparing bytes |
| Fallback | `LocaleFallbacker`: likely subtags and parent locales, then `und` | remove the last subtag, then `und` |
| Entries stored once | `--deduplication` (default `maximal`) | a key whose list equals its fallback's list is left out. Each list and each text is stored once. |

## Tools

| | Rust (ICU4X) | Swift (prototype) |
|---|---|---|
| Generator | `icu4x-datagen`, in Rust, reads CLDR JSON | `generator/generate.py`, in Python, reads the same CLDR JSON |
| Options | `--markers`, `--locales`, `--attribute-filter` (a regex) | `--markers`, `--locales`, `--attributes` (a list) |
| Find markers in an app | `--markers-for-bin`: searches for `tdmh` | `tools/find_markers.py`: searches for `dmk1` |
