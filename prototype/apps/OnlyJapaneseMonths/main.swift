// App 1: uses only the Japanese month names. The locale comes from the environment at run time.
import Darwin
import DateNames
import DateNamesData

let locale = getenv("LOCALE").map { String(cString: $0) } ?? "ko"
if let months = MonthNames<Japanese>(locale: locale, width: .wide) {
    print("\(locale): \(months[9])")
} else {
    print("\(locale): no data")
}
