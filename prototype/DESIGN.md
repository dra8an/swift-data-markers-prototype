# Design of the Swift data marker prototype

## Goal

Show that Swift can use the data design of ICU4X: each kind of locale data is its own type (a "marker"), and an app keeps only the data of the markers that its code uses. Test it in Embedded Swift and in normal Swift.

## Scope

| | Prototype |
|---|---|
| Kinds of data | month names, weekday names |
| Calendars | Gregorian, Japanese |
| Markers | `MonthNamesGregorianV1`, `MonthNamesJapaneseV1`, `WeekdayNamesGregorianV1`, `WeekdayNamesJapaneseV1` |
| Locales in the full data | `en`, `en-GB`, `ja`, `ko`, `ko-KP`, `und` |
| Source | CLDR 49.0.0-BETA4 JSON (`$CLDR_ROOT`) |

## Modules

The prototype has three modules. They match the parts of ICU4X:

| Module | Like in ICU4X | Content |
|---|---|---|
| `DataMarkers` | `icu_provider` | The protocols `DataMarker`, `BakedDataMarker` and `DataProvider`, the marker ID, the key, the fallback, and the lookup in baked tables. |
| `DateNames` | `icu_datetime` | The 4 marker types, the calendar protocol, and the API `MonthNames<C>` and `WeekdayNames<C>`. |
| `DateNamesData` | `icu_datetime_data` | The generated tables. Each marker gets an extension that conforms it to `BakedDataMarker`. |

An app imports `DateNames`. If it also imports `DateNamesData`, it can use the built-in data, like `compiled_data` in ICU4X. If not, it passes its own provider.

## Decision 1: a marker owns its data

In Rust, one provider type implements `DataProvider<M>` once for each marker. Swift cannot do this, because a type can conform to a protocol only once. So the baked data belongs to the marker type itself:

```swift
public protocol BakedDataMarker: DataMarker {
    static func bakedLookup(_ key: DataKey) -> DataStruct?
}
extension MonthNamesJapaneseV1: BakedDataMarker { ... }   // in DateNamesData, generated
```

Code that uses `MonthNamesJapaneseV1` refers to its data. Code that does not use it refers to nothing.

A custom provider is a separate value for each marker:

```swift
public protocol DataProvider {
    associatedtype Marker: DataMarker
    func load(_ key: DataKey) -> Marker.DataStruct?
}
```

## Decision 2: the calendar picks the markers by type

```swift
public protocol CalendarSystem {
    associatedtype MonthNamesMarker: DataMarker where MonthNamesMarker.DataStruct == NameList
    associatedtype WeekdayNamesMarker: DataMarker where WeekdayNamesMarker.DataStruct == NameList
}
public enum Japanese: CalendarSystem {
    public typealias MonthNamesMarker = MonthNamesJapaneseV1
    public typealias WeekdayNamesMarker = WeekdayNamesJapaneseV1
}
```

`MonthNames<Japanese>` uses `MonthNamesJapaneseV1`, chosen by the compiler.

## Decision 3: the key

A key is the locale, then the byte `0x1E`, then the attribute, as in ICU4X. The attributes are the same as in ICU4X:

| Attribute | Width |
|---|---|
| `3`, `4`, `5`, `6` | abbreviated, narrow, wide, short (format names) |
| `3s`, `4s`, `5s`, `6s` | the same, standalone names |

`6` (short) exists only for weekdays.

## Decision 4: the fallback

If a key is not in the table, the lookup removes the last subtag of the locale (`ko-KP` to `ko`), and then tries `und`. This is simpler than ICU4X, which also uses likely subtags and parent locales. It is enough for the prototype.

## Decision 5: entries stored once

The generator stores each list of names once. A key whose list is the same as the list of its fallback locale is left out, like "maximal" deduplication in ICU4X.

## Decision 6: the tables

Each marker has its own tables, as `static let` constants of type `InlineArray`, as #2330 does. These compile into read-only data at `-O`.

| Table | Type | Content |
|---|---|---|
| `pool` | `InlineArray<N, UInt8>` | The marker tag (8 bytes, decision 7), then the UTF-8 text of all keys and names, each text once. |
| `keys` | `InlineArray<K, UInt32>` | The keys, sorted by bytes. Each entry is `offset << 8 | length` into `pool`. |
| `keyLists` | `InlineArray<K, UInt16>` | For each key, the number of its list. |
| `listStarts` | `InlineArray<L + 1, UInt16>` | Where each list starts in `names`. |
| `names` | `InlineArray<M, UInt32>` | The names, each as `offset << 8 | length` into `pool`. |

The lookup compares bytes, never `String` values, so Embedded Swift does not need its Unicode tables (`RESULTS.md`, section 2).

## Decision 7: the marker tag

The first 8 bytes of every `pool` are the tag `dmk1` and a 32-bit FNV-1a hash of the marker name. The tag is part of the data, so it is in an app exactly when the data of that marker is. The marker finder (step 6) searches an app for `dmk1`, reads the next 4 bytes, and maps the hash back to a name through `markers.json`, which the generator writes.

ICU4X puts its tag in the `INFO` of the marker, which the load code refers to. Here the tag sits in the data, which is simpler. But it finds only markers whose baked data is in the app.

## Decision 8: the generator

`generator/generate.py` (Python 3.9, standard library only) reads CLDR and writes one Swift file for each marker into an output folder. Options, as in `icu4x-datagen`:

| Option | Meaning |
|---|---|
| `--markers A,B` | only these markers (default: all 4) |
| `--locales ko,en` | only these locales, plus `und` (default: all 6) |
| `--attributes 5,5s` | only these attributes (default: all) |
| `--out DIR` | the output folder |

## Decision 9: the builds

The apps are built with `swiftc` directly, not with SwiftPM, so that every flag is visible. Each module is compiled to a `.o` file and a `.swiftmodule`. Then the app is linked with `-dead_strip`.

| Mode | Toolchain |
|---|---|
| Embedded Swift | `swift-DEVELOPMENT-SNAPSHOT-2026-06-24-a`, target `arm64-apple-macos15` |
| Normal Swift | the toolchain of Xcode 8 (Swift 6.5) |

## The question to measure

In Embedded Swift, an unused marker should leave nothing in the app. In normal Swift, the record of each protocol conformance (`__swift5_proto`) might keep the extension of every marker, and so its data, even when no code uses it. Step 5 measures this. Then it tests the compiler flag `-conditional-runtime-records`.
