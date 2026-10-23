// A size app for the value API: the calendar is the constant .chinese, the locale comes from the environment.
// Question: does the constant calendar let the linker remove the data of the other 5 calendars?
import Darwin
import DateTimeFormat
import DateFormatting

let locale = getenv("LOCALE").map { String(cString: $0) } ?? "fr"
let style = DateFormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: Calendar(identifier: .chinese))
var text = style.format(DateTime(year: 2026, month: 10, day: 23, hour: 13, minute: 5, second: 9)) ?? "no data"
text += "\n"
var bytes = Array(text.utf8)
bytes.withUnsafeBufferPointer { _ = write(1, $0.baseAddress, $0.count) }
