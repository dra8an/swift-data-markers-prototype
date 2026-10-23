// App 3: brings its own data for one marker, and does not import DateNamesData (like ICU4X with compiled_data off).
import Darwin
import DataMarkers
import DateNames

/// Serves the Japanese month names for ko, wide, and nothing else.
struct KoreanJapaneseMonths: DataProvider {
    typealias Marker = MonthNamesJapaneseV1
    func load(_ key: DataKey) -> NameList? {
        let wanted = DataKey(locale: "ko", attribute: "5")
        guard key.bytes == wanted.bytes else { return nil }
        var names: [String] = []
        for month in 1 ... 12 {
            names.append("\(month)월")
        }
        return NameList(names: names)
    }
}

let locale = getenv("LOCALE").map { String(cString: $0) } ?? "ko"
if let months = MonthNames<Japanese>(locale: locale, width: .wide, provider: KoreanJapaneseMonths()) {
    print("\(locale): \(months[9])")
} else {
    print("\(locale): no data")
}
