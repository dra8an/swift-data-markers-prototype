// The core of the large prototype, like icu_provider and icu_locale in ICU4X: markers, locales, the fallback, and the lookup in baked tables.
// See DESIGN.md, decisions 5, 10 and 11.

// MARK: - Markers

/// One kind of locale data. A marker is a type with no values. Its only job is to be a name that the compiler knows.
public protocol DataMarker {
    /// The name of the marker, such as "DatetimeNamesMonthJapaneseV1".
    static var name: StaticString { get }
}

/// A marker whose data is built into the app. The generated data module adds this conformance to each marker.
public protocol BakedDataMarker: DataMarker {
    /// Calls `body` with the 5 tables of the marker: pool, keys, keyValues, valueStarts and words (DESIGN.md, decision 11).
    static func withTables<R>(_ body: (Span<UInt8>, Span<UInt32>, Span<UInt16>, Span<UInt32>, Span<UInt32>) -> R) -> R
}

/// The marker of data that a field set does not use, like NeverMarker in ICU4X. It has no data, so a lookup always fails and refers to no tables.
public enum NeverMarker: BakedDataMarker {
    public static var name: StaticString { "NeverMarker" }
    @usableFromInline static let none8: [UInt8] = []
    @usableFromInline static let none16: [UInt16] = []
    @usableFromInline static let none32: [UInt32] = []
    @inlinable @inline(__always)
    public static func withTables<R>(_ body: (Span<UInt8>, Span<UInt32>, Span<UInt16>, Span<UInt32>, Span<UInt32>) -> R) -> R {
        body(none8.span, none32.span, none16.span, none32.span, none32.span)
    }
}

// MARK: - Values

/// A value in the words table of one marker: the words from `start` to `end`.
public struct DataValue {
    public var start: Int
    public var end: Int

    @inlinable
    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

/// A text in the pool of one marker: `offset << 8 | length`.
public typealias TextRef = UInt32

extension TextRef {
    /// True for a word that is a field of a pattern, not a text (DESIGN.md, decision 11).
    @inlinable public var isField: Bool { self & 0x8000_0000 != 0 }
    @inlinable public var textOffset: Int { Int(self >> 8) }
    @inlinable public var textCount: Int { Int(self & 0xFF) }
}

// MARK: - Output

/// The output of a formatter: UTF-8 bytes. Embedded Swift needs no Unicode tables for this.
public struct TextOutput {
    public var bytes: [UInt8]

    @inlinable
    public init() {
        bytes = []
        bytes.reserveCapacity(64)
    }

    @inlinable
    public mutating func append(_ byte: UInt8) {
        bytes.append(byte)
    }

    /// Appends the text `ref` of `pool`.
    @inlinable
    public mutating func append(_ ref: TextRef, from pool: Span<UInt8>) {
        let offset = ref.textOffset
        for i in offset ..< offset + ref.textCount {
            bytes.append(pool[i])
        }
    }

    @inlinable
    public mutating func append(_ text: StaticString) {
        text.withUTF8Buffer { buffer in
            for b in buffer {
                bytes.append(b)
            }
        }
    }

    @inlinable
    public var string: String { String(decoding: bytes, as: UTF8.self) }
}

// MARK: - Locales

/// A locale: the language, the script and the region, each packed into a UInt32 (pack_subtag in generate.py), and one variant packed into a UInt64. 0 is no subtag.
/// The prototype also keeps the value of the -u-ca- keyword. Other subtags and keywords are not supported.
public struct LocaleID: Equatable {
    public var language: UInt32
    public var script: UInt32
    public var region: UInt32
    public var variant: UInt64
    /// The first 8 bytes of the value of -u-ca-, packed as the subtags. 0 if there is no -u-ca-.
    public var calendar: UInt64

    public static let und = LocaleID(language: 0x0064_6E75, script: 0, region: 0)

    @inlinable
    public init(language: UInt32, script: UInt32, region: UInt32, variant: UInt64 = 0, calendar: UInt64 = 0) {
        self.language = language
        self.script = script
        self.region = region
        self.variant = variant
        self.calendar = calendar
    }

    @inlinable
    public var isUnd: Bool { language == LocaleID.und.language && script == 0 && region == 0 && variant == 0 }

    /// Parses a BCP 47 locale such as "zh-Hant-TW" or "th-u-ca-buddhist". Returns nil for a locale that the prototype does not support.
    public init?(_ text: String) {
        var subtags: [[UInt8]] = [[]]
        for b in text.utf8 {
            if b == 0x2D || b == 0x5F {
                subtags.append([])
            } else {
                subtags[subtags.count - 1].append(b)
            }
        }
        guard let first = subtags.first, first.count >= 2 && first.count <= 3 else { return nil }
        language = LocaleID.pack(first, lowercase: true)
        script = 0
        region = 0
        variant = 0
        calendar = 0
        var i = 1
        while i < subtags.count {
            let s = subtags[i]
            if s.count == 1 {
                break
            }
            if s.count == 4 && LocaleID.allLetters(s) && script == 0 && region == 0 && variant == 0 {
                script = LocaleID.pack(s, lowercase: true, titlecase: true)
            } else if ((s.count == 2 && LocaleID.allLetters(s)) || (s.count == 3 && LocaleID.allDigits(s))) && variant == 0 {
                region = LocaleID.pack(s, uppercase: true)
            } else if (s.count >= 5 && s.count <= 8) || (s.count == 4 && s[0] >= 0x30 && s[0] <= 0x39), variant == 0 {
                for (n, raw) in s.enumerated() {
                    variant |= UInt64(raw >= 0x41 && raw <= 0x5A ? raw | 0x20 : raw) << (8 * UInt64(n))
                }
            } else {
                return nil
            }
            i += 1
        }
        // The -u- extension: only "ca" is read.
        if i < subtags.count && subtags[i] == [0x75] {
            i += 1
            while i + 1 < subtags.count {
                if subtags[i] == [0x63, 0x61] {
                    var value: UInt64 = 0
                    for (n, b) in subtags[i + 1].prefix(8).enumerated() {
                        value |= UInt64(b) << (8 * UInt64(n))
                    }
                    calendar = value
                    break
                }
                i += 1
            }
        }
        if language == LocaleID.und.language && script == 0 && region == 0 {
            language = LocaleID.und.language
        }
    }

    static func allLetters(_ s: [UInt8]) -> Bool { s.allSatisfy { ($0 | 0x20) >= 0x61 && ($0 | 0x20) <= 0x7A } }
    static func allDigits(_ s: [UInt8]) -> Bool { s.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } }

    static func pack(_ s: [UInt8], lowercase: Bool = false, uppercase: Bool = false, titlecase: Bool = false) -> UInt32 {
        var value: UInt32 = 0
        for (n, raw) in s.enumerated() {
            var b = raw
            if b >= 0x41 && b <= 0x5A && (lowercase && !(titlecase && n == 0)) { b |= 0x20 }
            if b >= 0x61 && b <= 0x7A && (uppercase || (titlecase && n == 0)) { b &= ~0x20 }
            value |= UInt32(b) << (8 * UInt32(n))
        }
        return value
    }
}

// MARK: - Keys

/// The bytes of a key: the locale, the byte 0x1E, then the attribute (DESIGN.md, decision 11). No heap memory.
public struct DataKey {
    public var bytes: InlineArray<32, UInt8>
    public var count: Int

    @inlinable
    public init(_ locale: LocaleID, attribute: StaticString) {
        bytes = InlineArray(repeating: 0)
        count = 0
        appendSubtag(locale.language)
        if locale.script != 0 {
            append(0x2D)
            appendSubtag(locale.script)
        }
        if locale.region != 0 {
            append(0x2D)
            appendSubtag(locale.region)
        }
        if locale.variant != 0 {
            append(0x2D)
            var v = locale.variant
            while v != 0 {
                append(UInt8(v & 0xFF))
                v >>= 8
            }
        }
        append(0x1E)
        attribute.withUTF8Buffer { buffer in
            for b in buffer {
                append(b)
            }
        }
    }

    @inlinable
    mutating func append(_ b: UInt8) {
        bytes[count] = b
        count += 1
    }

    @inlinable
    mutating func appendSubtag(_ subtag: UInt32) {
        var s = subtag
        while s != 0 {
            append(UInt8(s & 0xFF))
            s >>= 8
        }
    }

    /// Compares the text `ref` of `pool` with this key, byte by byte. Returns -1, 0 or 1.
    @inlinable
    func compare(_ ref: TextRef, in pool: Span<UInt8>) -> Int {
        let offset = ref.textOffset
        let length = ref.textCount
        var i = 0
        while i < length && i < count {
            let a = pool[offset + i]
            let b = bytes[i]
            if a != b {
                return a < b ? -1 : 1
            }
            i += 1
        }
        return length == count ? 0 : (length < count ? -1 : 1)
    }
}

// MARK: - The fallback of ICU4X, with language priority

/// Walks the locales that a lookup tries, as LocaleFallbackIterator in ICU4X (components/locale_fallback/src/algorithms.rs).
public struct LocaleFallbackIterator {
    public var current: LocaleID
    @usableFromInline var maxScript: UInt32
    @usableFromInline var backupVariant: UInt64 = 0

    /// The first locale is the locale without a script that its language and region imply.
    public init(_ locale: LocaleID) {
        var loc = locale
        loc.calendar = 0
        var defaultScript: UInt32 = 0
        if loc.script != 0 || loc.region != 0 {
            if loc.region != 0, let s = Fallback.scriptFor(language: loc.language, region: loc.region) {
                defaultScript = s
            } else if let (s, _) = Fallback.likely(language: loc.language) {
                defaultScript = s
            }
            if loc.script == defaultScript {
                loc.script = 0
            }
        }
        maxScript = loc.script != 0 ? loc.script : defaultScript
        current = loc
    }

    /// Moves to the next locale. Do not call it after und.
    /// The variant goes first, and comes back after the parent or the region goes (step_language in ICU4X).
    public mutating func step() {
        if current.variant != 0 {
            backupVariant = current.variant
            current.variant = 0
            return
        }
        if let parent = Fallback.parent(of: current) {
            current = parent
            current.variant = backupVariant
            backupVariant = 0
            return
        }
        if current.region != 0 {
            let implied = Fallback.likely(language: current.language)?.0 ?? 0
            current.script = implied != maxScript ? maxScript : 0
            current.region = 0
            current.variant = backupVariant
            backupVariant = 0
            return
        }
        current = LocaleID.und
    }
}

/// The searches in the fallback tables (FallbackTables.swift, generated).
enum Fallback {
    static func likely(language: UInt32) -> (UInt32, UInt32)? {
        let keys = FallbackTables.languageKeys.span
        var low = 0
        var high = keys.count
        while low < high {
            let middle = (low + high) / 2
            let k = keys[middle]
            if k == language {
                return (FallbackTables.languageScripts[middle], FallbackTables.languageRegions[middle])
            }
            if k < language { low = middle + 1 } else { high = middle }
        }
        return nil
    }

    static func scriptFor(language: UInt32, region: UInt32) -> UInt32? {
        let keys = FallbackTables.languageRegionKeys.span
        var low = 0
        var high = keys.count / 2
        while low < high {
            let middle = (low + high) / 2
            let a = keys[2 * middle]
            let b = keys[2 * middle + 1]
            if a == language && b == region {
                return FallbackTables.languageRegionScripts[middle]
            }
            if a < language || (a == language && b < region) { low = middle + 1 } else { high = middle }
        }
        return nil
    }

    static func parent(of locale: LocaleID) -> LocaleID? {
        let keys = FallbackTables.parentKeys.span
        let values = FallbackTables.parentValues.span
        let wanted = (locale.language, locale.script, locale.region)
        var low = 0
        var high = keys.count / 3
        while low < high {
            let middle = (low + high) / 2
            let k = (keys[3 * middle], keys[3 * middle + 1], keys[3 * middle + 2])
            if k == wanted {
                return LocaleID(language: values[3 * middle], script: values[3 * middle + 1], region: values[3 * middle + 2])
            }
            if k < wanted { low = middle + 1 } else { high = middle }
        }
        return nil
    }
}

// MARK: - The lookup

/// Finds the value of exactly this key in the tables of M, by binary search. No fallback.
@inlinable
public func lookupExact<M: BakedDataMarker>(_ marker: M.Type, _ key: DataKey) -> DataValue? {
    M.withTables { pool, keys, keyValues, valueStarts, _ in
        var low = 0
        var high = keys.count
        while low < high {
            let middle = (low + high) / 2
            let order = key.compare(keys[middle], in: pool)
            if order == 0 {
                let v = Int(keyValues[middle])
                return DataValue(start: Int(valueStarts[v]), end: Int(valueStarts[v + 1]))
            }
            if order < 0 { low = middle + 1 } else { high = middle }
        }
        return nil
    }
}

/// Finds the value for the locale and the attribute, with the fallback of ICU4X. The attribute stays the same.
@inlinable
public func lookup<M: BakedDataMarker>(_ marker: M.Type, _ locale: LocaleID, attribute: StaticString) -> DataValue? {
    var iterator = LocaleFallbackIterator(locale)
    while true {
        if let value = lookupExact(M.self, DataKey(iterator.current, attribute: attribute)) {
            return value
        }
        if iterator.current.isUnd {
            return nil
        }
        iterator.step()
    }
}

/// Finds a value with no locale: a singleton (locale und, no attribute) or a value keyed only by its attribute.
@inlinable
public func lookupSingleton<M: BakedDataMarker>(_ marker: M.Type, attribute: StaticString = "") -> DataValue? {
    lookupExact(M.self, DataKey(LocaleID.und, attribute: attribute))
}

/// Finds a value of locale und whose attribute is the text `attribute` of `pool`, such as the digits of a numbering system.
@inlinable
public func lookupSingleton<M: BakedDataMarker>(_ marker: M.Type, attribute: TextRef, in pool: Span<UInt8>) -> DataValue? {
    var key = DataKey(LocaleID.und, attribute: "")
    let offset = attribute.textOffset
    for i in offset ..< offset + attribute.textCount {
        key.append(pool[i])
    }
    return lookupExact(M.self, key)
}
