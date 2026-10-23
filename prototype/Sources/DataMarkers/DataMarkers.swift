// The core of the prototype, like icu_provider in ICU4X: markers, keys, providers, the fallback, and the lookup in baked tables.

/// One kind of locale data. A marker is a type with no values. Its only job is to be a name that the compiler knows.
public protocol DataMarker {
    /// The type of the data of this marker.
    associatedtype DataStruct
    /// The name of the marker, such as "MonthNamesJapaneseV1".
    static var name: StaticString { get }
}

/// A marker whose data is built into the app. The generated module DateNamesData adds this conformance to each marker.
public protocol BakedDataMarker: DataMarker {
    /// Finds the data for exactly this key, with no fallback.
    static func bakedLookup(_ key: DataKey) -> DataStruct?
}

/// A source of data for one marker, for apps that bring their own data.
/// Swift lets a type conform to a protocol only once, so a provider serves exactly one marker.
public protocol DataProvider {
    associatedtype Marker: DataMarker
    /// Finds the data for exactly this key, with no fallback.
    func load(_ key: DataKey) -> Marker.DataStruct?
}

/// A request: the locale, the byte 0x1E, then the attribute, such as "ko", 0x1E, "5".
public struct DataKey {
    public static let separator: UInt8 = 0x1E
    public var bytes: [UInt8]

    @inlinable
    public init(locale: String, attribute: String) {
        bytes = Array(locale.utf8)
        bytes.append(DataKey.separator)
        bytes.append(contentsOf: attribute.utf8)
    }

    @inlinable
    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// The next key to try: the locale without its last subtag ("ko-KP" to "ko"), then "und". Nil after "und".
    @inlinable
    public func fallback() -> DataKey? {
        guard let separatorIndex = bytes.firstIndex(of: DataKey.separator) else { return nil }
        let locale = bytes[..<separatorIndex]
        let attribute = bytes[separatorIndex...]
        let und: [UInt8] = [0x75, 0x6E, 0x64]
        if locale.elementsEqual(und) {
            return nil
        }
        if let hyphen = locale.lastIndex(of: 0x2D) {
            return DataKey(bytes: Array(locale[..<hyphen]) + attribute)
        }
        return DataKey(bytes: und + attribute)
    }
}

/// Tries the key, then each fallback key, until load finds data.
@inlinable
public func loadWithFallback<Data>(_ key: DataKey, _ load: (DataKey) -> Data?) -> Data? {
    var current: DataKey? = key
    while let key = current {
        if let data = load(key) {
            return data
        }
        current = key.fallback()
    }
    return nil
}

/// A list of names, such as the 12 month names of one locale and width.
public struct NameList {
    public var names: [String]

    @inlinable
    public init(names: [String]) {
        self.names = names
    }
}

/// The lookup in the generated tables. See DESIGN.md, decision 6.
public enum BakedTables {
    /// Reads the text at `entry` (offset << 8 | length) in the pool.
    @inlinable
    static func text(_ entry: UInt32, in pool: Span<UInt8>) -> String {
        let offset = Int(entry >> 8)
        let count = Int(entry & 0xFF)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)
        for i in offset ..< offset + count {
            bytes.append(pool[i])
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Compares the text at `entry` with `key`, byte by byte. Returns -1, 0 or 1.
    @inlinable
    static func compare(_ entry: UInt32, in pool: Span<UInt8>, with key: [UInt8]) -> Int {
        let offset = Int(entry >> 8)
        let count = Int(entry & 0xFF)
        var i = 0
        while i < count && i < key.count {
            let a = pool[offset + i]
            let b = key[i]
            if a != b {
                return a < b ? -1 : 1
            }
            i += 1
        }
        return count == key.count ? 0 : (count < key.count ? -1 : 1)
    }

    /// Finds `key` in the sorted `keys` by binary search, and returns its list of names.
    @inlinable
    public static func lookup(_ key: DataKey, pool: Span<UInt8>, keys: Span<UInt32>, keyLists: Span<UInt16>, listStarts: Span<UInt16>, names: Span<UInt32>) -> NameList? {
        var low = 0
        var high = keys.count
        while low < high {
            let middle = (low + high) / 2
            let order = compare(keys[middle], in: pool, with: key.bytes)
            if order == 0 {
                let list = Int(keyLists[middle])
                var result: [String] = []
                for n in Int(listStarts[list]) ..< Int(listStarts[list + 1]) {
                    result.append(text(names[n], in: pool))
                }
                return NameList(names: result)
            }
            if order < 0 {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return nil
    }
}
