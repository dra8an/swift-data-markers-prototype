// A size app (DESIGN.md, decision 8): The calendar of the -u-ca- keyword, YMD with T, medium. Like DateTimeFormatter<YMDT>. It keeps the markers of all 6 calendars.
// The locale comes from the environment at run time, so the compiler cannot remove the data of other locales.
import Darwin
import DataMarkers
import DateTimeFormat
import DateTimeData

let locale = getenv("LOCALE").map { String(cString: $0) } ?? "ja"
var out = TextOutput()
if let formatter = AnyCalendarFormatter<AllCalendars, YMDT>(locale: locale, length: .medium), formatter.format(DateTime(year: 2026, month: 10, day: 23, hour: 13, minute: 5, second: 9), into: &out) {
    out.append(0x0A)
} else {
    out.append("no data\n")
}
out.bytes.withUnsafeBufferPointer { _ = write(1, $0.baseAddress, $0.count) }
