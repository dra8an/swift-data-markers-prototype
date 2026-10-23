// The correctness test (DESIGN.md, decision 7): formats every case for every locale, calendar, field set and length.
// The output has the same format as icu4x-apps/reference. Embedded Swift has no Foundation, so the app reads and writes with Darwin.
// usage: LOCALES=<locales file> DATES=<dates file> Check > out.tsv (Embedded Swift has no CommandLine)
import Darwin
import DataMarkers
import DateTimeFormat
import DateTimeData

struct Case {
    var text: [UInt8]
    var dateTime: DateTime
}

func readLines(_ path: String) -> [[UInt8]] {
    guard let file = fopen(path, "r") else { return [] }
    var lines: [[UInt8]] = []
    var current: [UInt8] = []
    while true {
        let c = getc(file)
        if c < 0 { break }
        if c == 10 {
            lines.append(current)
            current = []
        } else {
            current.append(UInt8(c))
        }
    }
    if !current.isEmpty { lines.append(current) }
    fclose(file)
    return lines.filter { !$0.isEmpty && $0[0] != 0x23 }
}

func parseInts(_ line: [UInt8]) -> [Int] {
    var values: [Int] = []
    var value = 0
    var negative = false
    var inNumber = false
    for b in line + [0x20] {
        if b == 0x2D {
            negative = true
        } else if b >= 0x30 && b <= 0x39 {
            value = value * 10 + Int(b - 0x30)
            inNumber = true
        } else if inNumber {
            values.append(negative ? -value : value)
            value = 0
            negative = false
            inNumber = false
        }
    }
    return values
}

/// The number with at least `width` characters, sign included, as {:0width} in Rust.
func padded(_ value: Int, _ width: Int) -> [UInt8] {
    var digits: [UInt8] = []
    var n = value < 0 ? -value : value
    repeat {
        digits.insert(UInt8(0x30 + n % 10), at: 0)
        n /= 10
    } while n > 0
    let sign: [UInt8] = value < 0 ? [0x2D] : []
    while sign.count + digits.count < width {
        digits.insert(0x30, at: 0)
    }
    return sign + digits
}

func makeCase(_ line: [UInt8]) -> Case {
    let v = parseInts(line)
    let text = padded(v[0], 4) + [0x2D] + padded(v[1], 2) + [0x2D] + padded(v[2], 2) + [0x54] + padded(v[3], 2) + [0x3A] + padded(v[4], 2) + [0x3A] + padded(v[5], 2)
    return Case(text: text, dateTime: DateTime(year: v[0], month: v[1], day: v[2], hour: v[3], minute: v[4], second: v[5]))
}

var output: [UInt8] = []

func emit(_ bytes: [UInt8]) {
    output.append(contentsOf: bytes)
}

func emit(_ text: StaticString) {
    text.withUTF8Buffer { output.append(contentsOf: $0) }
}

func flush() {
    output.withUnsafeBufferPointer { _ = write(1, $0.baseAddress, $0.count) }
    output.removeAll(keepingCapacity: true)
}

let lengths: [Length] = [.long, .medium, .short]
let lengthNames: [StaticString] = ["long", "medium", "short"]

func line(_ locale: [UInt8], _ calendar: StaticString, _ fieldSet: StaticString, _ length: Int, _ c: Case, _ result: TextOutput?, _ ok: Bool) {
    emit(locale)
    emit("\t")
    emit(calendar)
    emit("\t")
    emit(fieldSet)
    emit("\t")
    emit(lengthNames[length])
    emit("\t")
    emit(c.text)
    emit("\t")
    if let result {
        if ok { emit(result.bytes) } else { emit("<out of range>") }
    } else {
        emit("<no formatter>")
    }
    emit("\n")
}

func run<FS: BakedFieldSet, C: BakedCalendar>(_ calendar: C.Type, _ fieldSet: FS.Type, _ name: StaticString, _ fsName: StaticString, _ locale: [UInt8], _ cases: [Case], into lines: inout [[[UInt8]]]) {
    let id = String(decoding: locale, as: UTF8.self)
    for (i, length) in lengths.enumerated() {
        let formatter = FixedCalendarFormatter<C, FS>(locale: id, length: length)
        for (n, c) in cases.enumerated() {
            let saved = output
            output = []
            var out = TextOutput()
            let ok = formatter?.format(c.dateTime, into: &out) ?? false
            line(locale, name, fsName, i, c, formatter == nil ? nil : out, ok)
            lines[n][i] += output
            output = saved
        }
    }
}

/// The same order as icu4x-apps/reference: for each case, the 3 lengths, and for each length YMD, YMDE, YMDT.
func runCalendar<C: BakedCalendar>(_ calendar: C.Type, _ name: StaticString, _ locales: [[UInt8]], _ cases: [Case]) {
    for locale in locales {
        var ymd = Array(repeating: Array(repeating: [UInt8](), count: 3), count: cases.count)
        var ymde = ymd
        var ymdt = ymd
        run(C.self, YMD.self, name, "YMD", locale, cases, into: &ymd)
        run(C.self, YMDE.self, name, "YMDE", locale, cases, into: &ymde)
        run(C.self, YMDT.self, name, "YMDT", locale, cases, into: &ymdt)
        for n in 0 ..< cases.count {
            for i in 0 ..< 3 {
                emit(ymd[n][i])
                emit(ymde[n][i])
                emit(ymdt[n][i])
            }
        }
        flush()
    }
}

let locales = readLines(String(cString: getenv("LOCALES")!))
let cases = readLines(String(cString: getenv("DATES")!)).map(makeCase)

for locale in locales {
    let id = String(decoding: locale, as: UTF8.self)
    let formatters = lengths.map { FixedCalendarFormatter<NoCalendar, T>(locale: id, length: $0) }
    for c in cases {
        for i in 0 ..< 3 {
            var out = TextOutput()
            let ok = formatters[i]?.format(c.dateTime, into: &out) ?? false
            line(locale, "-", "T", i, c, formatters[i] == nil ? nil : out, ok)
        }
    }
    flush()
}
runCalendar(Gregorian.self, "gregorian", locales, cases)
runCalendar(Buddhist.self, "buddhist", locales, cases)
runCalendar(Japanese.self, "japanese", locales, cases)
runCalendar(Hebrew.self, "hebrew", locales, cases)
runCalendar(Chinese.self, "chinese", locales, cases)
runCalendar(Hijri.self, "hijri", locales, cases)
flush()
