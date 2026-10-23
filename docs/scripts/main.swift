// Formats 2026-09-18 14:05 (a Friday) as "<weekday>, <month> <day>, <year> <h>:<mm> <am/pm>" with the date data of #2330.
// The locale comes from the environment variable LOCALE at run time, so the linker cannot drop the data of other locales.
import Darwin
let identifier = getenv("LOCALE").map { String(cString: $0) } ?? "en_US"
let id = DataLocaleIdentifier(identifier)
let locale = DateFormatLocale(id)
let numbers = locale.numbers(id)
func digits(_ value: Int, minimum: Int = 1) -> String {
    var decimal: [Int] = []
    var rest = value
    repeat { decimal.insert(rest % 10, at: 0); rest /= 10 } while rest > 0
    while decimal.count < minimum { decimal.insert(0, at: 0) }
    var bytes: [UInt8] = []
    for digit in decimal { numbers.appendDigit(digit, to: &bytes) }
    return String(decoding: bytes, as: UTF8.self)
}
let weekday = locale.weekday(6, context: .format, width: .wide).string
let month = locale.month(9, context: .format, width: .wide).string
let period = locale.dayPeriod(1, width: .abbreviated).string
print("\(identifier): \(weekday), \(month) \(digits(18)), \(digits(2026)) \(digits(2)):\(digits(5, minimum: 2)) \(period)")
