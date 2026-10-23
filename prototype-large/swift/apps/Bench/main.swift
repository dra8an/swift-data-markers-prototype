// The speed test (DESIGN.md, decision 9). The same tests as rust-copy/src/bin/bench.rs and icu4x-apps/sizes/src/bin/bench.rs.
// Each test runs 5 times. The output is the median time of one operation, in tenths of a nanosecond.
import Darwin
import DataMarkers
import DateTimeFormat
import DateTimeData

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

func median(_ values: [UInt64]) -> UInt64 {
    let s = values.sorted()
    return s[s.count / 2]
}

/// Tenths of a nanosecond for one operation.
func report(_ name: StaticString, _ runs: [UInt64], operations: Int) {
    let tenths = median(runs) * 10 / UInt64(operations)
    print("\(name)\t\(tenths)")
}

func benchNew<C: BakedCalendar, FS: BakedFieldSet>(_ name: StaticString, _: C.Type, _: FS.Type, _ length: Length, repeats: Int) {
    var runs: [UInt64] = []
    for _ in 0 ..< 5 {
        let start = now()
        for _ in 0 ..< repeats {
            for locale in locales {
                if FixedCalendarFormatter<C, FS>(locale: locale, length: length) != nil {
                    sink &+= 1
                }
            }
        }
        runs.append(now() - start)
    }
    report(name, runs, operations: repeats * locales.count)
}

func benchFormat<C: BakedCalendar, FS: BakedFieldSet>(_ name: StaticString, _: C.Type, _: FS.Type, _ locale: String, _ length: Length, repeats: Int) {
    guard let formatter = FixedCalendarFormatter<C, FS>(locale: locale, length: length) else {
        print("\(name)\tno formatter")
        return
    }
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

benchNew("new Gregorian YMD medium", Gregorian.self, YMD.self, .medium, repeats: 2000)
benchNew("new Japanese YMDT long", Japanese.self, YMDT.self, .long, repeats: 2000)
benchFormat("format Gregorian YMD medium en", Gregorian.self, YMD.self, "en", .medium, repeats: 20000)
benchFormat("format Gregorian YMDT medium en", Gregorian.self, YMDT.self, "en", .medium, repeats: 20000)
benchFormat("format Japanese YMDT long ja", Japanese.self, YMDT.self, "ja", .long, repeats: 20000)
benchFormat("format Hebrew YMD long he", Hebrew.self, YMD.self, "he", .long, repeats: 20000)
benchFormat("format Chinese YMD long zh", Chinese.self, YMD.self, "zh", .long, repeats: 20000)
benchFormat("format Gregorian YMD long ar-EG", Gregorian.self, YMD.self, "ar-EG", .long, repeats: 20000)
print("sink\t\(sink)")
