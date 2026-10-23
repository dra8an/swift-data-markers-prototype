// The speed test of the value API, with the same method as apps/Bench. Compare with the typed formatter in apps/Bench.
import Darwin
import DataMarkers
import DateTimeFormat
import DateFormatting

let locales = ["en", "ja", "de", "ar-EG", "he", "zh", "fr", "hi", "ko", "pt-AO"]
let cases: [DateTime] = [
    DateTime(year: 2026, month: 10, day: 23, hour: 13, minute: 5, second: 9), DateTime(year: 2000, month: 2, day: 29),
    DateTime(year: 1989, month: 1, day: 7, hour: 12), DateTime(year: 1989, month: 1, day: 8, hour: 23, minute: 59),
    DateTime(year: 2019, month: 4, day: 30, hour: 9, minute: 30), DateTime(year: 2019, month: 5, day: 1, hour: 9, minute: 30),
    DateTime(year: 1950, month: 6, day: 15, hour: 18, minute: 45), DateTime(year: 2023, month: 4, day: 15, hour: 6, minute: 7),
    DateTime(year: 2025, month: 8, day: 1, hour: 20, minute: 20), DateTime(year: 2024, month: 3, day: 15, hour: 11, minute: 11),
    DateTime(year: 1900, month: 1, day: 31, hour: 12), DateTime(year: 2100, month: 12, day: 31),
]
var sink = 0

func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }

func report(_ name: StaticString, _ runs: [UInt64], operations: Int) {
    print("\(name)\t\(runs.sorted()[runs.count / 2] * 10 / UInt64(operations))")
}

func benchNew(_ name: StaticString, _ date: DateFormatStyle.DateStyle, _ time: DateFormatStyle.TimeStyle, _ identifier: Calendar.Identifier) {
    var runs: [UInt64] = []
    for _ in 0 ..< 5 {
        let start = now()
        for _ in 0 ..< 2000 {
            for locale in locales {
                if StyleFormatter(DateFormatStyle(date: date, time: time, locale: locale, calendar: Calendar(identifier: identifier))) != nil {
                    sink &+= 1
                }
            }
        }
        runs.append(now() - start)
    }
    report(name, runs, operations: 2000 * locales.count)
}

func benchFormat(_ name: StaticString, _ date: DateFormatStyle.DateStyle, _ time: DateFormatStyle.TimeStyle, _ identifier: Calendar.Identifier, _ locale: String, repeats: Int = 20000) {
    let formatter = StyleFormatter(DateFormatStyle(date: date, time: time, locale: locale, calendar: Calendar(identifier: identifier)))!
    var runs: [UInt64] = []
    for _ in 0 ..< 5 {
        let start = now()
        for _ in 0 ..< repeats {
            for c in cases {
                var out = TextOutput()
                if formatter.format(c, into: &out) {
                    sink &+= out.bytes.count
                }
            }
        }
        runs.append(now() - start)
    }
    report(name, runs, operations: repeats * cases.count)
}

func benchStyleFormat(_ name: StaticString, _ style: DateFormatStyle) {
    var runs: [UInt64] = []
    for _ in 0 ..< 5 {
        let start = now()
        for _ in 0 ..< 2000 {
            for c in cases {
                sink &+= style.format(c)?.utf8.count ?? 0
            }
        }
        runs.append(now() - start)
    }
    report(name, runs, operations: 2000 * cases.count)
}

benchNew("new Gregorian YMD medium", .abbreviated, .omitted, .gregorian)
benchNew("new Japanese YMDT long", .long, .shortened, .japanese)
benchFormat("format Gregorian YMD medium en", .abbreviated, .omitted, .gregorian, "en")
benchFormat("format Gregorian YMDT medium en", .abbreviated, .shortened, .gregorian, "en")
benchFormat("format Japanese YMDT long ja", .long, .shortened, .japanese, "ja")
benchFormat("format Hebrew YMD long he", .long, .omitted, .hebrew, "he")
benchFormat("format Chinese YMD long zh", .long, .omitted, .chinese, "zh")
benchFormat("format Gregorian YMD long ar-EG", .long, .omitted, .gregorian, "ar-EG")
benchStyleFormat("style.format, new formatter each time, Gregorian YMD medium en", DateFormatStyle(date: .abbreviated, time: .omitted, locale: "en", calendar: Calendar(identifier: .gregorian)))
print("sink\t\(sink)")
