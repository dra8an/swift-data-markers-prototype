# Results of the Swift data marker prototype

**Date:** 2026-10-23. **Folder:** `/Users/draganm4/Projects/dra8an/swift-data-markers-prototype/prototype/`. **Design:** `DESIGN.md` in the same folder.

## The answer

**Yes. Swift can use the data design of ICU4X.** Each kind of locale data is its own type, a marker. The calendar picks its markers by type. An app keeps only the data of the markers that its code uses.

| Mode | Unused markers removed automatically? |
|---|---|
| **Embedded Swift** | **Yes**, with no extra flags. |
| **Normal Swift** | **Only with 3 compiler flags** together: `-Xfrontend -internalize-at-link`, `-Xfrontend -conditional-runtime-records` and `-lto=llvm-full`. Without them, the app keeps every marker. |

The locales and widths are cut by the generator, as in ICU4X. The marker finder reads a built app and gives the generator the list of markers to keep, as `--markers-for-bin` does in ICU4X.

## What was built

| Part | Files | Content |
|---|---|---|
| Core module `DataMarkers` | `Sources/DataMarkers/DataMarkers.swift` | The protocols `DataMarker`, `BakedDataMarker` and `DataProvider`, the key, the fallback, and the lookup in the tables |
| Component module `DateNames` | `Sources/DateNames/DateNames.swift` | 4 markers, the calendars `Gregorian` and `Japanese`, and the API `MonthNames<C>` and `WeekdayNames<C>` |
| Data module `DateNamesData` | `data/<set>/*.swift`, generated | One file for each marker. It conforms the marker to `BakedDataMarker` and holds its tables. |
| Generator | `generator/generate.py` | Reads CLDR 49.0.0-BETA4. Options `--markers`, `--locales` (or `all`) and `--attributes`. |
| Marker finder | `tools/find_markers.py` | Lists the markers whose data is in a built app. |
| Measurement | `tools/measure.py` | Sizes, the marker tags, and the table symbols of a built app |
| Apps | `apps/` | `OnlyJapaneseMonths` (app 1), `AllMarkers` (app 2, the control), `OwnProvider` (app 3) |
| Builds | `build.sh`, `build-matrix.sh` | `swiftc` for each module, then the link with `-dead_strip` |

The data sets:

| Set | Locales | Tables of each marker |
|---|---|---|
| `data/full` | `en`, `en-GB`, `ja`, `ko`, `ko-KP`, `und` | 810 to 946 bytes |
| `data/all-locales` | every CLDR locale that has both calendars | 77,706 bytes (weekdays) and 102,392 bytes (months) |
| `data/cut-ko-wide` | `ko` and `und`, wide names, only `MonthNamesJapaneseV1` | 218 bytes |

## The measurements

All sizes are in bytes: the sum of the sections of the app, without `__LINKEDIT`. "Data" is the `__const` sections. Normal Swift links the standard library as a shared library, so its sizes do not include it. Embedded Swift includes all the standard library code that the app uses.

### 1. Embedded Swift: automatic

| App, with the all-locales data | Code | Data | Total | Markers in the app |
|---|---:|---:|---:|---|
| App 1: only the Japanese month names | 22,152 | 102,936 | 125,429 | `MonthNamesJapaneseV1` |
| App 2: all 4 markers | 23,480 | 360,864 | 384,717 | all 4 |
| App 3: its own provider, no built-in data used | 22,528 | 800 | 23,649 | none |

App 1 keeps one marker of about 102 KB and drops the other three (about 258 KB). App 3 links the whole data module, and none of it stays.

### 2. Normal Swift: all markers stay, unless 3 flags are used

App 1, all-locales data:

| Flags | Code | Data | Total | Markers in the app |
|---|---:|---:|---:|---|
| none | 8,884 | 361,972 | 374,973 | all 4 |
| `-conditional-runtime-records` | 8,884 | 361,972 | 374,973 | all 4 |
| `-internalize-at-link` | 6,108 | 361,716 | 371,757 | all 4 |
| `-internalize-at-link`, `-conditional-runtime-records` | 6,108 | 361,716 | 371,757 | all 4 |
| `-lto=llvm-full` | 7,724 | 334,596 | 346,445 | all 4 |
| `-conditional-runtime-records`, `-lto=llvm-full` | 7,724 | 334,596 | 346,445 | all 4 |
| `-internalize-at-link`, `-lto=llvm-full` | 4,592 | 334,324 | 342,865 | all 4 |
| **all three** | **2,924** | **102,507** | **106,215** | **`MonthNamesJapaneseV1`** |

App 2 (the control) with all three flags keeps all 4 markers (337,803 bytes), which is correct, because it uses them.

**The cause.** In normal Swift, the compiler marks the public symbols of a module `[no dead strip]`. In the data module that includes each `bakedLookup` function, each protocol conformance descriptor and each witness table. The linker may not remove such a symbol, so each `bakedLookup` keeps its tables. `ld -why_live` shows the chain: `static MonthNamesGregorianV1.pool` is kept by `static MonthNamesGregorianV1.bakedLookup(_:)`, and nothing keeps `bakedLookup`, because it is a root. In Embedded Swift, the same symbols have no `[no dead strip]` mark.

The three flags remove this mark from three places:
* **`-internalize-at-link`:** public functions are no longer roots.
* **`-conditional-runtime-records`:** the conformance records live only when something uses the conformance.
* **`-lto=llvm-full`:** lets the link see across the modules and remove the rest.

**One detail of the LTO builds.** In some LTO builds, a few Gregorian tables have no symbol of their own, but their marker tag is still in the app. The Gregorian and Japanese tables of keys have the same content, so LLVM likely merged them into one.

### 3. Cut data: one generator command

The marker finder on the Embedded build of app 1 gives `MonthNamesJapaneseV1`. On normal Swift with the three flags it gives the same. On normal Swift without the flags it gives all 4 markers, because all 4 are in that binary. So the finder is right only when the build removes unused markers, as in ICU4X.

```
python3 -I generator/generate.py --cldr $CLDR_ROOT --markers MonthNamesJapaneseV1 --locales ko --attributes 5 --out data/cut-ko-wide
```

The output has 2 keys, `ko` `0x1E` `5` and `und` `0x1E` `5`, and 218 bytes of tables. That is the same shape as the output of `icu4x-datagen` for the same request (`ICU4X-DATA-GUIDE.md`, step 6.5).

| App 1 with the cut data | Code | Data | Total |
|---|---:|---:|---:|
| Embedded Swift | 21,996 | 756 | 23,093 |
| Normal Swift, all three flags | 2,684 | 299 | 3,680 |

The output is the same in both modes:

| Locale | Output | Why |
|---|---|---|
| `ko` | `9월` | the key `ko` `0x1E` `5` |
| `ko-KP` | `9월` | the fallback to `ko` |
| `ja`, `en` | `M09` | the fallback to `und` |

**A missing marker fails at compile time.** App 2 does not compile with the cut data:

```
error: initializer 'init(locale:width:)' requires that 'Gregorian.MonthNamesMarker' (aka 'MonthNamesGregorianV1') conform to 'BakedDataMarker'
```

In ICU4X, a wrong list for `--markers` shows up only at run time.

## How Swift compares with ICU4X

| ICU4X | This prototype | Same or different |
|---|---|---|
| A marker is a unit struct with `DataStruct` and `INFO` | an `enum` with no cases, conforming to `DataMarker` with `DataStruct` and `name` | same |
| The calendar picks its markers (`C::MonthNamesV1`) | `associatedtype MonthNamesMarker` | same |
| One provider type implements `DataProvider<M>` for every marker | not possible: a Swift type can conform to a protocol only once. Each marker owns its data (`BakedDataMarker`), and a custom provider serves one marker. | different design, same effect |
| `compiled_data` on or off | import `DateNamesData` or not | same |
| `ICU4X_DATA_DIR` swaps the data | the build compiles a different data folder | Swift has no `include!`. The build decides. |
| The ID is a hash computed at compile time | the generator writes the hash into the data | Swift has no general compile-time evaluation |
| `--markers-for-bin` searches for the ID in `INFO` | `find_markers.py` searches for the tag in the data | same idea. Both work only if unused markers are removed. |
| A wrong marker list fails at run time | fails at compile time | better in Swift |
| Unused markers are removed by the compiler | Embedded: yes. Normal Swift: only with 3 flags. | the main difference |

## Limits of this prototype

1. **The flags of normal Swift are frontend flags** (`-Xfrontend`), and `-internalize-at-link` assumes that the whole program is in one link. That fits an app, not a shared library or framework. A system framework such as Foundation must keep its public symbols, so this does not apply to it.
2. **The Embedded toolchain is a snapshot** (`swift-DEVELOPMENT-SNAPSHOT-2026-06-24-a`), and the target is `arm64-apple-macos15`. A real device target was not tried.
3. **The builds use `swiftc` directly, not SwiftPM.** SwiftPM could choose the data folder with a package trait or a build plugin. That was not tried.
4. **The fallback is simpler than in ICU4X.** It removes the last subtag, then uses `und`. It has no likely subtags or parent locales.
5. **`NameList` makes `String` values on each lookup.** ICU4X returns views into the data, with no copies.
6. **Only 2 kinds of data and 2 calendars.**

## What it means for #2330

#2330 stores its 8 kinds of date data (`DateFormatDataGroup`) in shared tables, so the linker cannot remove a kind that an app does not use (`ICU4X-COMPARISON.md`). This prototype shows that one table set for each kind, owned by a marker type, works in Swift. In Embedded Swift it works with no extra flags.

## How to repeat the runs

```
cd /Users/draganm4/Projects/dra8an/swift-data-markers-prototype && . ./env.sh && cd prototype
python3 -I generator/generate.py --cldr $CLDR_ROOT --out data/full
python3 -I generator/generate.py --cldr $CLDR_ROOT --locales all --out data/all-locales
./build-matrix.sh
./build.sh normal data/all-locales OnlyJapaneseMonths out/<new folder> -Xfrontend -internalize-at-link -Xfrontend -conditional-runtime-records -lto=llvm-full
python3 -I tools/measure.py data/all-locales/markers.json out/*/OnlyJapaneseMonths
python3 -I tools/find_markers.py data/all-locales/markers.json out/embedded-all-locales-OnlyJapaneseMonths/OnlyJapaneseMonths
```

The generator does not write into a folder that is not empty. Use a new folder each time.
