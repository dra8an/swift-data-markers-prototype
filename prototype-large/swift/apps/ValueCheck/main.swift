// The correctness test of the value API. It writes the cases that the styles can express, in the format of icu4x-apps/reference:
// date .long, .abbreviated, .numeric (YMD long, medium, short), date .complete (YMDE long), the same dates with time .shortened (YMDT), and time only (T short).
// usage: LOCALES=<locales file> DATES=<dates file> ValueCheck > out.tsv. Compare with tools/compare.py --keyed.
import Darwin
import DataMarkers
import DateTimeFormat
import DateFormatting

func readLines(_ path: String) -> [String] {
    guard let file = fopen(path, "r") else { return [] }
    var lines: [String] = []
    var current: [UInt8] = []
    while true {
        let c = getc(file)
        if c < 0 { break }
        if c == 10 {
            lines.append(String(decoding: current, as: UTF8.self))
            current = []
        } else {
            current.append(UInt8(c))
        }
    }
    if !current.isEmpty { lines.append(String(decoding: current, as: UTF8.self)) }
    fclose(file)
    return lines.filter { !$0.isEmpty && !$0.hasPrefix("#") }
}

func padded(_ value: Int, _ width: Int) -> String {
    var digits = String(value < 0 ? -value : value)
    while digits.utf8.count + (value < 0 ? 1 : 0) < width { digits = "0" + digits }
    return (value < 0 ? "-" : "") + digits
}

struct Case {
    var text: String
    var dateTime: DateTime
}

let locales = readLines(String(cString: getenv("LOCALES")!))
let cases: [Case] = readLines(String(cString: getenv("DATES")!)).map { line in
    let v = line.split(separator: " ").map { Int(String($0))! }
    let text = padded(v[0], 4) + "-" + padded(v[1], 2) + "-" + padded(v[2], 2) + "T" + padded(v[3], 2) + ":" + padded(v[4], 2) + ":" + padded(v[5], 2)
    return Case(text: text, dateTime: DateTime(year: v[0], month: v[1], day: v[2], hour: v[3], minute: v[4], second: v[5]))
}
let calendars: [(Calendar.Identifier, String)] = [(.gregorian, "gregorian"), (.buddhist, "buddhist"), (.japanese, "japanese"), (.hebrew, "hebrew"), (.chinese, "chinese"), (.islamicCivil, "hijri")]
let dateStyles: [(DateFormatStyle.DateStyle, String, String)] = [(.long, "YMD", "long"), (.abbreviated, "YMD", "medium"), (.numeric, "YMD", "short"), (.complete, "YMDE", "long")]

var output: [UInt8] = []
func emit(_ s: String) { output.append(contentsOf: s.utf8) }
func flush() {
    output.withUnsafeBufferPointer { _ = write(1, $0.baseAddress, $0.count) }
    output.removeAll(keepingCapacity: true)
}
func result(_ f: StyleFormatter?, _ c: Case) -> String {
    guard let f else { return "<no formatter>" }
    return f.format(c.dateTime) ?? "<out of range>"
}

for locale in locales {
    let t = StyleFormatter(DateFormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: Calendar(identifier: .gregorian)))
    for c in cases {
        emit("\(locale)\t-\tT\tshort\t\(c.text)\t\(result(t, c))\n")
    }
    for (identifier, name) in calendars {
        for (date, fieldSet, length) in dateStyles {
            let f = StyleFormatter(DateFormatStyle(date: date, time: .omitted, locale: locale, calendar: Calendar(identifier: identifier)))
            let ft = date == .complete ? nil : StyleFormatter(DateFormatStyle(date: date, time: .shortened, locale: locale, calendar: Calendar(identifier: identifier)))
            for c in cases {
                emit("\(locale)\t\(name)\t\(fieldSet)\t\(length)\t\(c.text)\t\(result(f, c))\n")
                if date != .complete {
                    emit("\(locale)\t\(name)\tYMDT\t\(length)\t\(c.text)\t\(result(ft, c))\n")
                }
            }
        }
    }
    flush()
}
