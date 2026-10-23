// The calendars: their markers (DESIGN.md, decision 3) and their arithmetic (decision 6). The rules for eras and leap months are the rules of icu_calendar.
import DataMarkers

// MARK: - Calendar fields

/// How much of a year number a reader needs to know the year, as YearAmbiguity in ICU4X.
public enum YearAmbiguity {
    case unambiguous, centuryRequired, eraRequired, eraAndCenturyRequired
}

/// The leap status of a month, as LeapStatus in ICU4X.
public enum LeapStatus {
    case normal, leap, base
}

/// An era code such as "reiwa", as bytes. No heap memory.
public struct EraCode {
    public var bytes: InlineArray<16, UInt8>
    public var count: Int

    @inlinable
    public init(_ text: StaticString) {
        bytes = InlineArray(repeating: 0)
        count = 0
        text.withUTF8Buffer { buffer in
            for b in buffer {
                bytes[count] = b
                count += 1
            }
        }
    }

    @inlinable
    public init(_ ref: TextRef, in pool: Span<UInt8>) {
        bytes = InlineArray(repeating: 0)
        count = ref.textCount
        for i in 0 ..< count {
            bytes[i] = pool[ref.textOffset + i]
        }
    }

    /// Compares the text `ref` of `pool` with this code. Returns -1, 0 or 1.
    @inlinable
    func compare(_ ref: TextRef, in pool: Span<UInt8>) -> Int {
        var i = 0
        while i < ref.textCount && i < count {
            let a = pool[ref.textOffset + i]
            if a != bytes[i] {
                return a < bytes[i] ? -1 : 1
            }
            i += 1
        }
        return ref.textCount == count ? 0 : (ref.textCount < count ? -1 : 1)
    }
}

/// The fields of one day in one calendar, as the input of a pattern.
public struct CalendarFields {
    /// The year of the era, or the related ISO year if the calendar has no eras.
    public var eraYear: Int
    public var hasEra: Bool
    public var eraIndex: Int
    public var eraCode: EraCode
    public var ambiguity: YearAmbiguity
    /// 1 to 60 for a cyclic year, 0 if the calendar has no cyclic years.
    public var cyclic: Int
    public var relatedIso: Int
    /// The number of the month code: 5 for M05 and for M05L.
    public var monthNumber: Int
    public var monthOrdinal: Int
    public var leapStatus: LeapStatus
    public var day: Int

    @inlinable
    init(eraYear: Int, hasEra: Bool, eraIndex: Int, eraCode: EraCode, ambiguity: YearAmbiguity, cyclic: Int = 0, relatedIso: Int = 0, monthNumber: Int, monthOrdinal: Int, leapStatus: LeapStatus = .normal, day: Int) {
        self.eraYear = eraYear
        self.hasEra = hasEra
        self.eraIndex = eraIndex
        self.eraCode = eraCode
        self.ambiguity = ambiguity
        self.cyclic = cyclic
        self.relatedIso = relatedIso
        self.monthNumber = monthNumber
        self.monthOrdinal = monthOrdinal
        self.leapStatus = leapStatus
        self.day = day
    }
}

// MARK: - The calendar protocol

/// A calendar names its markers as types, so the compiler picks the data (DESIGN.md, decision 3).
public protocol CalendarSystem {
    associatedtype MonthNames: DataMarker
    associatedtype YearNames: DataMarker
    associatedtype DatePatterns: DataMarker
    /// The data that the arithmetic needs: CalendarJapaneseModernV1 for the Japanese calendar, NeverMarker for the others.
    associatedtype EraData: DataMarker
    /// The fields of the day `rataDie`, or nil outside the range of the calendar. `eras` is the value of EraData.
    static func fields<E: BakedDataMarker>(rataDie: Int, eras: DataValue?, eraMarker: E.Type) -> CalendarFields?
}

/// A calendar whose markers all have built-in data. The generated data module adds this conformance (Conformances.swift).
public protocol BakedCalendar: CalendarSystem where MonthNames: BakedDataMarker, YearNames: BakedDataMarker, DatePatterns: BakedDataMarker, EraData: BakedDataMarker {}

// MARK: - Arithmetic

@inlinable func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }
@inlinable func floorMod(_ a: Int, _ b: Int) -> Int { a - b * floorDiv(a, b) }

@inlinable func isGregorianLeap(_ y: Int) -> Bool { floorMod(y, 4) == 0 && (floorMod(y, 100) != 0 || floorMod(y, 400) == 0) }

/// The rata die of an ISO date (Reingold and Dershowitz, fixed-from-gregorian).
@inlinable
public func rataDie(year y: Int, month m: Int, day d: Int) -> Int {
    let y1 = y - 1
    var f = 365 * y1 + floorDiv(y1, 4) - floorDiv(y1, 100) + floorDiv(y1, 400) + floorDiv(367 * m - 362, 12) + d
    if m > 2 {
        f -= isGregorianLeap(y) ? 1 : 2
    }
    return f
}

/// The ISO date of a rata die (gregorian-from-fixed).
@inlinable
func isoFromRataDie(_ f: Int) -> (year: Int, month: Int, day: Int) {
    let d0 = f - 1
    let n400 = floorDiv(d0, 146_097)
    let d1 = floorMod(d0, 146_097)
    let n100 = d1 / 36524
    let d2 = d1 % 36524
    let n4 = d2 / 1461
    let d3 = d2 % 1461
    let n1 = d3 / 365
    var year = 400 * n400 + 100 * n100 + 4 * n4 + n1
    if !(n100 == 4 || n1 == 4) {
        year += 1
    }
    let priorDays = f - rataDie(year: year, month: 1, day: 1)
    let correction = f < rataDie(year: year, month: 3, day: 1) ? 0 : (isGregorianLeap(year) ? 1 : 2)
    let month = (12 * (priorDays + correction) + 373) / 367
    return (year, month, f - rataDie(year: year, month: month, day: 1) + 1)
}

/// The era of a Gregorian year (CeBce in icu_calendar).
@inlinable
func ceBce(_ year: Int, month: Int, day: Int) -> CalendarFields {
    if year > 0 {
        let ambiguity: YearAmbiguity = year <= 999 ? .eraAndCenturyRequired : (year <= 1949 ? .centuryRequired : (year <= 2049 ? .unambiguous : .centuryRequired))
        return CalendarFields(eraYear: year, hasEra: true, eraIndex: 1, eraCode: EraCode("ce"), ambiguity: ambiguity, monthNumber: month, monthOrdinal: month, day: day)
    }
    return CalendarFields(eraYear: 1 - year, hasEra: true, eraIndex: 0, eraCode: EraCode("bce"), ambiguity: .eraAndCenturyRequired, monthNumber: month, monthOrdinal: month, day: day)
}

// MARK: - The 6 calendars

public enum Gregorian: CalendarSystem {
    public typealias MonthNames = DatetimeNamesMonthGregorianV1
    public typealias YearNames = DatetimeNamesYearGregorianV1
    public typealias DatePatterns = DatetimePatternsDateGregorianV1
    public typealias EraData = NeverMarker

    @inlinable
    public static func fields<E: BakedDataMarker>(rataDie: Int, eras: DataValue?, eraMarker: E.Type) -> CalendarFields? {
        let (y, m, d) = isoFromRataDie(rataDie)
        return ceBce(y, month: m, day: d)
    }
}

public enum Buddhist: CalendarSystem {
    public typealias MonthNames = DatetimeNamesMonthBuddhistV1
    public typealias YearNames = DatetimeNamesYearBuddhistV1
    public typealias DatePatterns = DatetimePatternsDateBuddhistV1
    public typealias EraData = NeverMarker

    @inlinable
    public static func fields<E: BakedDataMarker>(rataDie: Int, eras: DataValue?, eraMarker: E.Type) -> CalendarFields? {
        let (y, m, d) = isoFromRataDie(rataDie)
        return CalendarFields(eraYear: y + 543, hasEra: true, eraIndex: 0, eraCode: EraCode("be"), ambiguity: .centuryRequired, monthNumber: m, monthOrdinal: m, day: d)
    }
}

public enum Japanese: CalendarSystem {
    public typealias MonthNames = DatetimeNamesMonthJapaneseV1
    public typealias YearNames = DatetimeNamesYearJapaneseV1
    public typealias DatePatterns = DatetimePatternsDateJapaneseV1
    public typealias EraData = CalendarJapaneseModernV1

    /// The era is the last era whose start is on or before the date. Meiji 1 to 5 are CE, as in icu_calendar.
    @inlinable
    public static func fields<E: BakedDataMarker>(rataDie: Int, eras: DataValue?, eraMarker: E.Type) -> CalendarFields? {
        let (y, m, d) = isoFromRataDie(rataDie)
        guard let eras else { return nil }
        return E.withTables { pool, _, _, _, words in
            let count = Int(words[eras.start])
            var i = count - 1
            while i >= 0 {
                let at = eras.start + 1 + 4 * i
                let sy = Int(Int32(bitPattern: words[at]))
                let sm = Int(words[at + 1])
                let sd = Int(words[at + 2])
                if (y, m, d) >= (sy, sm, sd) {
                    let code = EraCode(words[at + 3], in: pool)
                    let eraYear = y - sy + 1
                    // Meiji is the first era of the table.
                    if i == 0 && eraYear < 6 {
                        return ceBce(y, month: m, day: d)
                    }
                    return CalendarFields(eraYear: eraYear, hasEra: true, eraIndex: i + 2, eraCode: code, ambiguity: .centuryRequired, monthNumber: m, monthOrdinal: m, day: d)
                }
                i -= 1
            }
            return ceBce(y, month: m, day: d)
        }
    }
}

public enum Hebrew: CalendarSystem {
    public typealias MonthNames = DatetimeNamesMonthHebrewV1
    public typealias YearNames = DatetimeNamesYearHebrewV1
    public typealias DatePatterns = DatetimePatternsDateHebrewV1
    public typealias EraData = NeverMarker

    // Reingold and Dershowitz, chapter 8. Months are numbered from Nisan (1) to Adar II (13).
    @usableFromInline static let epoch = -1_373_427

    @inlinable static func isLeap(_ y: Int) -> Bool { floorMod(7 * y + 1, 19) < 7 }

    @inlinable static func elapsedDays(_ y: Int) -> Int {
        let monthsElapsed = floorDiv(235 * y - 234, 19)
        let partsElapsed = 12084 + 13753 * monthsElapsed
        let day = 29 * monthsElapsed + floorDiv(partsElapsed, 25920)
        return floorMod(3 * (day + 1), 7) < 3 ? day + 1 : day
    }

    @inlinable static func newYearDelay(_ y: Int) -> Int {
        let ny0 = elapsedDays(y - 1)
        let ny1 = elapsedDays(y)
        let ny2 = elapsedDays(y + 1)
        if ny2 - ny1 == 356 { return 2 }
        if ny1 - ny0 == 382 { return 1 }
        return 0
    }

    @inlinable static func newYear(_ y: Int) -> Int { epoch + elapsedDays(y) + newYearDelay(y) }

    /// The length of month m (numbered from Nisan) in a year with `days` days.
    @inlinable static func monthLength(_ m: Int, leap: Bool, days: Int) -> Int {
        if m == 2 || m == 4 || m == 6 || m == 10 || m == 13 { return 29 }
        if m == 12 && !leap { return 29 }
        if m == 8 && !(days == 355 || days == 385) { return 29 }
        if m == 9 && (days == 353 || days == 383) { return 29 }
        return 30
    }

    /// Computes the new year and the length of the year once, then walks the months from Tishri.
    @inlinable
    public static func fields<E: BakedDataMarker>(rataDie: Int, eras: DataValue?, eraMarker: E.Type) -> CalendarFields? {
        let approx = floorDiv(98496 * (rataDie - epoch), 35_975_351) + 1
        var year = approx
        var start = newYear(approx)
        if start > rataDie {
            year = approx - 1
            start = newYear(year)
        }
        let days = newYear(year + 1) - start
        let leap = isLeap(year)
        var remaining = rataDie - start
        var ordinal = 1
        var month = 7
        while true {
            let length = monthLength(month, leap: leap, days: days)
            if remaining < length { break }
            remaining -= length
            ordinal += 1
            month = month == (leap ? 13 : 12) ? 1 : month + 1
        }
        let day = remaining + 1
        // ICU4X numbers the months from Tishri. In a leap year, ordinal 6 is M05L (Adar I) and ordinal 7 is M06 with the status Base (Adar II).
        var number = ordinal
        var status = LeapStatus.normal
        if leap && ordinal >= 6 {
            number = ordinal - 1
            if ordinal == 6 { status = .leap }
            if ordinal == 7 { status = .base }
        }
        return CalendarFields(eraYear: year, hasEra: true, eraIndex: 0, eraCode: EraCode("am"), ambiguity: .centuryRequired, monthNumber: number, monthOrdinal: ordinal, leapStatus: status, day: day)
    }
}

public enum Chinese: CalendarSystem {
    public typealias MonthNames = DatetimeNamesMonthChineseV1
    public typealias YearNames = DatetimeNamesYearChineseV1
    public typealias DatePatterns = DatetimePatternsDateChineseV1
    public typealias EraData = NeverMarker

    /// Uses the table of years from icu_calendar (ChineseYears.swift). Returns nil outside the table.
    @inlinable
    public static func fields<E: BakedDataMarker>(rataDie: Int, eras: DataValue?, eraMarker: E.Type) -> CalendarFields? {
        let newYears = ChineseYears.newYears.span
        guard rataDie >= Int(newYears[0]) && rataDie <= ChineseYears.lastDay else { return nil }
        var low = 0
        var high = newYears.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if Int(newYears[middle]) <= rataDie { low = middle } else { high = middle - 1 }
        }
        let info = ChineseYears.info[low]
        let leapOrdinal = Int(info >> 16)
        var day = rataDie - Int(newYears[low]) + 1
        var ordinal = 1
        while true {
            let length = (info >> UInt32(ordinal - 1)) & 1 == 1 ? 30 : 29
            if day <= length { break }
            day -= length
            ordinal += 1
        }
        var number = ordinal
        var status = LeapStatus.normal
        if leapOrdinal != 0 {
            if ordinal == leapOrdinal {
                number = ordinal - 1
                status = .leap
            } else if ordinal > leapOrdinal {
                number = ordinal - 1
            } else if ordinal + 1 == leapOrdinal {
                status = .base
            }
        }
        let relatedIso = ChineseYears.firstYear + low
        let cyclic = floorMod(relatedIso - 4, 60) + 1
        return CalendarFields(eraYear: relatedIso, hasEra: false, eraIndex: -1, eraCode: EraCode(""), ambiguity: .eraRequired, cyclic: cyclic, relatedIso: relatedIso, monthNumber: number, monthOrdinal: ordinal, leapStatus: status, day: day)
    }
}

public enum Hijri: CalendarSystem {
    public typealias MonthNames = DatetimeNamesMonthHijriV1
    public typealias YearNames = DatetimeNamesYearHijriV1
    public typealias DatePatterns = DatetimePatternsDateHijriV1
    public typealias EraData = NeverMarker

    // The tabular calendar with the leap years of type II and the Friday epoch (islamic-civil). Reingold and Dershowitz, chapter 7.
    @usableFromInline static let epoch = 227_015

    @inlinable static func fixed(_ y: Int, _ m: Int, _ d: Int) -> Int {
        d + 29 * (m - 1) + floorDiv(6 * m - 1, 11) + (y - 1) * 354 + floorDiv(3 + 11 * y, 30) + epoch - 1
    }

    @inlinable
    public static func fields<E: BakedDataMarker>(rataDie: Int, eras: DataValue?, eraMarker: E.Type) -> CalendarFields? {
        let year = floorDiv(30 * (rataDie - epoch) + 10646, 10631)
        let priorDays = rataDie - fixed(year, 1, 1)
        let month = floorDiv(11 * priorDays + 330, 325)
        let day = rataDie - fixed(year, month, 1) + 1
        if year > 0 {
            return CalendarFields(eraYear: year, hasEra: true, eraIndex: 0, eraCode: EraCode("ah"), ambiguity: .centuryRequired, monthNumber: month, monthOrdinal: month, day: day)
        }
        return CalendarFields(eraYear: 1 - year, hasEra: true, eraIndex: 1, eraCode: EraCode("bh"), ambiguity: .centuryRequired, monthNumber: month, monthOrdinal: month, day: day)
    }
}

/// The calendar of a formatter with no date, like NoCalendarFormatter in ICU4X.
public enum NoCalendar: CalendarSystem, BakedCalendar {
    public typealias MonthNames = NeverMarker
    public typealias YearNames = NeverMarker
    public typealias DatePatterns = NeverMarker
    public typealias EraData = NeverMarker

    @inlinable
    public static func fields<E: BakedDataMarker>(rataDie: Int, eras: DataValue?, eraMarker: E.Type) -> CalendarFields? {
        CalendarFields(eraYear: 0, hasEra: false, eraIndex: -1, eraCode: EraCode(""), ambiguity: .unambiguous, monthNumber: 0, monthOrdinal: 0, day: 0)
    }
}
