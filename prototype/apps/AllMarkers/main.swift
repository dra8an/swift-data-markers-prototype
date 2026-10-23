// App 2, the control: uses all 4 markers.
import Darwin
import DateNames
import DateNamesData

let locale = getenv("LOCALE").map { String(cString: $0) } ?? "ko"
let gregorianMonths = MonthNames<Gregorian>(locale: locale, width: .wide)
let japaneseMonths = MonthNames<Japanese>(locale: locale, width: .wide)
let gregorianWeekdays = WeekdayNames<Gregorian>(locale: locale, width: .wide)
let japaneseWeekdays = WeekdayNames<Japanese>(locale: locale, width: .wide)
print("\(locale): \(gregorianMonths?[9] ?? "?") \(japaneseMonths?[9] ?? "?") \(gregorianWeekdays?[6] ?? "?") \(japaneseWeekdays?[6] ?? "?")")
