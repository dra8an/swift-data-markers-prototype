// Formats the test date with today's Foundation (Date.FormatStyle, with ICU), in the format of icu4x-apps/reference.
// Mapping: YMD long = date .long, medium = .abbreviated, short = .numeric. YMDT = the same with time .shortened. YMDE long = .complete.
import Foundation

let locales = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8).split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") }
var utc = Foundation.Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC")!
let date = utc.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 13, minute: 5, second: 9))!
let calendars: [(Foundation.Calendar.Identifier, String)] = [(.gregorian, "gregorian"), (.japanese, "japanese"), (.hebrew, "hebrew"), (.chinese, "chinese"), (.islamicCivil, "hijri"), (.buddhist, "buddhist")]
let styles: [(Date.FormatStyle.DateStyle, Date.FormatStyle.TimeStyle, String, String)] = [(.long, .omitted, "YMD", "long"), (.abbreviated, .omitted, "YMD", "medium"), (.numeric, .omitted, "YMD", "short"), (.complete, .omitted, "YMDE", "long"), (.long, .shortened, "YMDT", "long"), (.abbreviated, .shortened, "YMDT", "medium"), (.numeric, .shortened, "YMDT", "short")]
var out = ""
for l in locales {
    for (id, name) in calendars {
        var cal = Foundation.Calendar(identifier: id)
        cal.timeZone = TimeZone(identifier: "UTC")!
        for (d, t, fs, len) in styles {
            var style = Date.FormatStyle(date: d, time: t, locale: Locale(identifier: l), calendar: cal, timeZone: TimeZone(identifier: "UTC")!)
            style.capitalizationContext = .unknown
            out += "\(l)\t\(name)\t\(fs)\t\(len)\t2026-10-23T13:05:09\t\(date.formatted(style))\n"
        }
    }
}
FileHandle.standardOutput.write(out.data(using: .utf8)!)
