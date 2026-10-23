// A size app for the value API: the calendar and the time style come from the environment, as in a real app.
import Darwin
import DateTimeFormat
import DateFormatting

func env(_ name: String) -> String? { getenv(name).map { String(cString: $0) } }
// The names are compared as bytes: String keys in a Dictionary need the Unicode tables in Embedded Swift.
let names: [([UInt8], Calendar.Identifier)] = [(Array("gregorian".utf8), .gregorian), (Array("buddhist".utf8), .buddhist), (Array("japanese".utf8), .japanese), (Array("hebrew".utf8), .hebrew), (Array("chinese".utf8), .chinese), (Array("islamic-civil".utf8), .islamicCivil)]
let wanted = Array((env("CALENDAR") ?? "chinese").utf8)
let identifier = names.first { $0.0 == wanted }?.1 ?? .gregorian
let style = DateFormatStyle(date: .abbreviated, time: Array((env("TIME") ?? "").utf8) == [0x31] ? .shortened : .omitted, locale: env("LOCALE") ?? "fr", calendar: Calendar(identifier: identifier))
var text = style.format(DateTime(year: 2026, month: 10, day: 23, hour: 13, minute: 5, second: 9)) ?? "no data"
text += "\n"
var bytes = Array(text.utf8)
bytes.withUnsafeBufferPointer { _ = write(1, $0.baseAddress, $0.count) }
