// The formatter, like FixedCalendarDateTimeFormatter and DateTimeFormatter in ICU4X, for the field sets of FieldSets.swift.
// The rules come from icu_datetime: raw/neo.rs (pattern selection), pattern/names.rs (which names to load) and format/datetime.rs (the fields).
import DataMarkers

public enum Length {
    case long, medium, short
}

/// A date and time in the ISO calendar. Year 0 is 1 BCE.
public struct DateTime {
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int
    public var minute: Int
    public var second: Int

    @inlinable
    public init(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
    }
}

// MARK: - Packed patterns

/// The variants of packed patterns (PackedSkeletonVariant in ICU4X).
@usableFromInline
enum Variant {
    /// The year as in the pattern, or the hour only.
    case standard
    /// The full year, or hours and minutes.
    case variant0
    /// The year with the era, or hours, minutes and seconds.
    case variant1
}

/// The word index of the pattern for `length` and `variant` in a packed pattern value (get_element in ICU4X). A pattern is [count, items].
@inlinable
func packedPattern(_ words: Span<UInt32>, _ value: DataValue, _ length: Length, _ variant: Variant) -> Int {
    let header = words[value.start]
    let lms = header & 3
    var index: Int
    switch variant {
    case .standard:
        switch length {
        case .long: index = 0
        case .medium: index = (lms == 0 || lms == 2) ? 0 : 1
        case .short: index = lms == 0 ? 0 : (lms == 3 ? 2 : 1)
        }
    case .variant0, .variant1:
        let cell = (variant == .variant0 ? 0 : 3) + (length == .long ? 0 : (length == .medium ? 1 : 2))
        if header & 4 == 0 {
            let chunk = Int((header >> UInt32(3 + 3 * cell)) & 7)
            if chunk == 0 {
                return packedPattern(words, value, length, .standard)
            }
            index = chunk - 1
        } else {
            let sOffset = lms == 0 ? 0 : (lms == 3 ? 2 : 1)
            index = sOffset + 1 + cell
        }
    }
    let count = Int(words[value.start + 1])
    if index >= count {
        index = 0
    }
    return value.start + Int(words[value.start + 2 + index])
}

/// The fields of one pattern, for loading their names. No heap memory.
@usableFromInline
struct FieldList {
    @usableFromInline var words: InlineArray<32, UInt32>
    @usableFromInline var count: Int

    @inlinable
    init(_ patternWords: Span<UInt32>, at start: Int) {
        words = InlineArray(repeating: 0)
        count = 0
        let n = Int(patternWords[start])
        for i in 0 ..< n {
            let w = patternWords[start + 1 + i]
            if w.isField && count < 32 {
                words[count] = w
                count += 1
            }
        }
    }
}

@usableFromInline let symbolG: UInt8 = 0x47, symbolU: UInt8 = 0x55, symbolM: UInt8 = 0x4D, symbolL: UInt8 = 0x4C
@usableFromInline let symbolE: UInt8 = 0x45, symbolc: UInt8 = 0x63, symbole: UInt8 = 0x65
@usableFromInline let symbola: UInt8 = 0x61, symbolb: UInt8 = 0x62, symbolB: UInt8 = 0x42
@usableFromInline let symboly: UInt8 = 0x79, symbolr: UInt8 = 0x72, symbold: UInt8 = 0x64
@usableFromInline let symbolh: UInt8 = 0x68, symbolH: UInt8 = 0x48, symbolK: UInt8 = 0x4B, symbolk: UInt8 = 0x6B
@usableFromInline let symbolm: UInt8 = 0x6D, symbols: UInt8 = 0x73

// MARK: - The formatter

/// Formats dates of calendar C with field set FS. Like FixedCalendarDateTimeFormatter<C, FSet> in ICU4X.
/// The formatter keeps the values that it needs as positions in the tables. It copies no data.
public struct FixedCalendarFormatter<C: CalendarSystem, FS: FieldSet> {
    @usableFromInline let length: Length
    @usableFromInline var datePatterns: DataValue?
    @usableFromInline var timePatterns: DataValue?
    @usableFromInline var glue: DataValue?
    @usableFromInline var monthNames: DataValue?
    @usableFromInline var yearNames: DataValue?
    @usableFromInline var weekdayNames: DataValue?
    @usableFromInline var dayPeriodNames: DataValue?
    @usableFromInline var decimalSymbols: DataValue?
    @usableFromInline var decimalDigits: DataValue?
    @usableFromInline var eras: DataValue?
}

extension FixedCalendarFormatter where C: BakedCalendar, FS: BakedFieldSet {
    /// Uses the built-in data. Returns nil for a locale that the prototype cannot parse, or if data is missing.
    @inlinable
    public init?(locale text: String, length: Length) {
        guard let locale = LocaleID(text) else { return nil }
        self.init(locale: locale, length: length)
    }

    @inlinable
    public init?(locale: LocaleID, length: Length) {
        self.length = length
        datePatterns = nil
        timePatterns = nil
        glue = nil
        monthNames = nil
        yearNames = nil
        weekdayNames = nil
        dayPeriodNames = nil
        decimalSymbols = nil
        decimalDigits = nil
        eras = nil
        if FS.hasDate {
            guard let p = lookup(C.DatePatterns.self, locale, attribute: FS.dateAttribute) else { return nil }
            datePatterns = p
        }
        if FS.hasTime {
            guard let p = lookup(FS.TimePatterns.self, locale, attribute: "j") else { return nil }
            timePatterns = p
        }
        if FS.hasDate && FS.hasTime {
            // UTS 35: the glue of the length of the date.
            let attribute: StaticString = length == .long ? "ldt" : (length == .medium ? "mdt" : "sdt")
            guard let g = lookup(FS.GluePatterns.self, locale, attribute: attribute) else { return nil }
            glue = g
        }
        eras = lookupSingleton(C.EraData.self)
        // Load the names for the fields of variant 1, which has all fields of the other variants (pattern_items_for_data_loading in ICU4X).
        if let p = datePatterns {
            let fields = C.DatePatterns.withTables { _, _, _, _, words in FieldList(words, at: packedPattern(words, p, length, .variant1)) }
            for i in 0 ..< fields.count {
                guard load(field: fields.words[i], locale: locale) else { return nil }
            }
        }
        if let p = timePatterns {
            let fields = FS.TimePatterns.withTables { _, _, _, _, words in FieldList(words, at: packedPattern(words, p, length, .variant1)) }
            for i in 0 ..< fields.count {
                guard load(field: fields.words[i], locale: locale) else { return nil }
            }
        }
    }

    // MARK: Loading names (load_for_pattern in ICU4X)

    @inlinable
    mutating func load(field: UInt32, locale: LocaleID) -> Bool {
        let symbol = UInt8((field >> 8) & 0xFF)
        let count = Int(field & 0xFF)
        switch symbol {
        case symbolG, symbolU:
            if yearNames == nil {
                yearNames = lookup(C.YearNames.self, locale, attribute: count == 4 ? "5" : (count == 5 ? "4" : "3"))
            }
            return yearNames != nil
        case symbolM, symbolL:
            if count >= 17 {
                return true
            }
            if monthNames == nil {
                let standalone = symbol == symbolL
                let attribute: StaticString
                switch count {
                case 1, 2: attribute = "1"
                case 3: attribute = standalone ? "3s" : "3"
                case 4: attribute = standalone ? "5s" : "5"
                default: attribute = standalone ? "4s" : "4"
                }
                monthNames = lookup(C.MonthNames.self, locale, attribute: attribute)
            }
            guard monthNames != nil else { return false }
            return count > 2 || loadDecimal(locale)
        case symbolE, symbolc, symbole:
            if weekdayNames == nil {
                let standalone = symbol == symbolc
                let n = (symbol == symbolE && count < 3) ? 3 : count
                let attribute: StaticString
                switch n {
                case 3: attribute = standalone ? "3s" : "3"
                case 4: attribute = standalone ? "5s" : "5"
                case 5: attribute = standalone ? "4s" : "4"
                default: attribute = standalone ? "6s" : "6"
                }
                weekdayNames = lookup(FS.WeekdayNames.self, locale, attribute: attribute)
            }
            return weekdayNames != nil
        case symbola, symbolb, symbolB:
            if dayPeriodNames == nil {
                dayPeriodNames = lookup(FS.DayPeriodNames.self, locale, attribute: count == 4 ? "5" : (count == 5 ? "4" : "3"))
            }
            return dayPeriodNames != nil
        case symboly, symbold:
            return count >= 17 || loadDecimal(locale)
        case symbolh, symbolH, symbolK, symbolk, symbolm, symbols:
            return loadDecimal(locale)
        case symbolr:
            return true
        default:
            return false
        }
    }

    /// Loads the decimal symbols of the locale and the digits of their numbering system.
    @inlinable
    mutating func loadDecimal(_ locale: LocaleID) -> Bool {
        if decimalDigits != nil {
            return true
        }
        guard let s = lookup(FS.DecimalSymbols.self, locale, attribute: "") else { return false }
        decimalSymbols = s
        decimalDigits = FS.DecimalSymbols.withTables { pool, _, _, _, words in
            lookupSingleton(FS.DecimalDigits.self, attribute: words[s.start + 6], in: pool)
        }
        return decimalDigits != nil
    }
}

// MARK: - Formatting

extension FixedCalendarFormatter where C: BakedCalendar, FS: BakedFieldSet {
    /// Appends the formatted date to `out`. Returns false if the date is outside the range of the calendar.
    @inlinable
    public func format(_ dateTime: DateTime, into out: inout TextOutput) -> Bool {
        let rd = rataDie(year: dateTime.year, month: dateTime.month, day: dateTime.day)
        guard let fields = C.fields(rataDie: rd, eras: eras, eraMarker: C.EraData.self) else { return false }
        let weekday = floorMod(rd, 7)
        if let g = glue {
            FS.GluePatterns.withTables { pool, _, _, _, words in
                let n = Int(words[g.start])
                for i in 0 ..< n {
                    let w = words[g.start + 1 + i]
                    if !w.isField {
                        out.append(w, from: pool)
                    } else if (w >> 8) & 0xFF == 0x31 {
                        writeDate(fields, weekday, dateTime, into: &out)
                    } else {
                        writeTime(fields, weekday, dateTime, into: &out)
                    }
                }
            }
        } else if datePatterns != nil {
            writeDate(fields, weekday, dateTime, into: &out)
        } else {
            writeTime(fields, weekday, dateTime, into: &out)
        }
        return true
    }

    /// The formatted date as a String, or nil if the date is outside the range of the calendar.
    @inlinable
    public func format(_ dateTime: DateTime) -> String? {
        var out = TextOutput()
        guard format(dateTime, into: &out) else { return nil }
        return out.string
    }

    /// The variant of the date pattern for year style Auto (resolve_date_variant in ICU4X).
    @inlinable
    func dateVariant(_ fields: CalendarFields) -> Variant {
        switch fields.hasEra ? fields.ambiguity : .eraRequired {
        case .unambiguous, .eraRequired: return .standard
        case .centuryRequired: return .variant0
        case .eraAndCenturyRequired: return .variant1
        }
    }

    @inlinable
    func writeDate(_ fields: CalendarFields, _ weekday: Int, _ dateTime: DateTime, into out: inout TextOutput) {
        guard let p = datePatterns else { return }
        C.DatePatterns.withTables { pool, _, _, _, words in
            writeItems(words, at: packedPattern(words, p, length, dateVariant(fields)), pool: pool, fields, weekday, dateTime, into: &out)
        }
    }

    @inlinable
    func writeTime(_ fields: CalendarFields, _ weekday: Int, _ dateTime: DateTime, into out: inout TextOutput) {
        guard let p = timePatterns else { return }
        // Time precision Minute is variant 0 (resolve_time_precision in ICU4X).
        FS.TimePatterns.withTables { pool, _, _, _, words in
            writeItems(words, at: packedPattern(words, p, length, .variant0), pool: pool, fields, weekday, dateTime, into: &out)
        }
    }

    @inlinable
    func writeItems(_ words: Span<UInt32>, at start: Int, pool: Span<UInt8>, _ fields: CalendarFields, _ weekday: Int, _ dateTime: DateTime, into out: inout TextOutput) {
        let n = Int(words[start])
        for i in 0 ..< n {
            let w = words[start + 1 + i]
            if w.isField {
                writeField(UInt8((w >> 8) & 0xFF), Int(w & 0xFF), fields, weekday, dateTime, into: &out)
            } else {
                out.append(w, from: pool)
            }
        }
    }

    // MARK: Fields (try_write_field in ICU4X)

    @inlinable
    func writeField(_ symbol: UInt8, _ count: Int, _ fields: CalendarFields, _ weekday: Int, _ dateTime: DateTime, into out: inout TextOutput) {
        switch symbol {
        case symbolG:
            writeEra(fields, into: &out)
        case symboly:
            let year = fields.eraYear
            if count >= 17 && year >= 0 {
                NumericOverride.format(year, override: count, into: &out)
            } else {
                writeNumber(count == 2 ? year % 100 : year, minDigits: count, into: &out)
            }
        case symbolU:
            writeCyclic(fields, into: &out)
        case symbolr:
            out.appendASCII(fields.relatedIso, minDigits: count)
        case symbolM, symbolL:
            if count >= 17 {
                NumericOverride.format(fields.monthNumber, override: count, into: &out)
            } else {
                writeMonth(fields, count, into: &out)
            }
        case symbold:
            if count >= 17 {
                NumericOverride.format(fields.day, override: count, into: &out)
            } else {
                writeNumber(fields.day, minDigits: count, into: &out)
            }
        case symbolE, symbolc, symbole:
            writeWeekday(weekday, into: &out)
        case symbolh:
            let h = dateTime.hour % 12
            writeNumber(h == 0 ? 12 : h, minDigits: count, into: &out)
        case symbolK:
            writeNumber(dateTime.hour % 12, minDigits: count, into: &out)
        case symbolH, symbolk:
            writeNumber(dateTime.hour, minDigits: count, into: &out)
        case symbolm:
            writeNumber(dateTime.minute, minDigits: count, into: &out)
        case symbols:
            writeNumber(dateTime.second, minDigits: count, into: &out)
        case symbola, symbolb, symbolB:
            writeDayPeriod(symbol, dateTime, into: &out)
        default:
            break
        }
    }

    /// A number in the digits of the locale, with at least `minDigits` digits, and no grouping (DecimalFormatter in ICU4X, GroupingStrategy::Never).
    @inlinable
    func writeNumber(_ value: Int, minDigits: Int, into out: inout TextOutput) {
        guard let digits = decimalDigits, let symbols = decimalSymbols else {
            out.appendASCII(value, minDigits: minDigits)
            return
        }
        FS.DecimalSymbols.withTables { spool, _, _, _, swords in
            FS.DecimalDigits.withTables { dpool, _, _, _, dwords in
                if value < 0 {
                    out.append(swords[symbols.start], from: spool)
                }
                var decimal = InlineArray<24, UInt8>(repeating: 0)
                var n = value < 0 ? -value : value
                var count = 0
                repeat {
                    decimal[count] = UInt8(n % 10)
                    n /= 10
                    count += 1
                } while n > 0 && count < 24
                var pad = minDigits - count
                while pad > 0 {
                    out.append(dwords[digits.start], from: dpool)
                    pad -= 1
                }
                var i = count - 1
                while i >= 0 {
                    out.append(dwords[digits.start + Int(decimal[i])], from: dpool)
                    i -= 1
                }
                if value < 0 {
                    out.append(swords[symbols.start + 1], from: spool)
                }
            }
        }
    }

    @inlinable
    func writeEraCode(_ fields: CalendarFields, into out: inout TextOutput) {
        for i in 0 ..< fields.eraCode.count {
            out.append(fields.eraCode.bytes[i])
        }
    }

    /// get_name_for_era in ICU4X. If there is no name, the era code (the error case of ICU4X).
    @inlinable
    func writeEra(_ fields: CalendarFields, into out: inout TextOutput) {
        guard let names = yearNames else {
            writeEraCode(fields, into: &out)
            return
        }
        let found: Bool = C.YearNames.withTables { pool, _, _, _, words in
            let kind = words[names.start]
            let n = Int(words[names.start + 1])
            switch kind {
            case 0:
                guard fields.eraIndex >= 0 && fields.eraIndex < n else { return false }
                out.append(words[names.start + 2 + fields.eraIndex], from: pool)
                return true
            case 1:
                var low = 0
                var high = n
                while low < high {
                    let middle = (low + high) / 2
                    let order = fields.eraCode.compare(words[names.start + 2 + middle], in: pool)
                    if order == 0 {
                        out.append(words[names.start + 2 + n + middle], from: pool)
                        return true
                    }
                    if order < 0 { low = middle + 1 } else { high = middle }
                }
                return false
            default:
                return false
            }
        }
        if !found {
            writeEraCode(fields, into: &out)
        }
    }

    /// get_name_for_cyclic in ICU4X. If there is no name, the year as a number (the error case of ICU4X).
    @inlinable
    func writeCyclic(_ fields: CalendarFields, into out: inout TextOutput) {
        guard fields.cyclic != 0 else {
            writeNumber(fields.eraYear, minDigits: 1, into: &out)
            return
        }
        let found: Bool
        if let names = yearNames {
            found = C.YearNames.withTables { pool, _, _, _, words in
                guard words[names.start] == 2 && fields.cyclic - 1 < Int(words[names.start + 1]) else { return false }
                out.append(words[names.start + 2 + fields.cyclic - 1], from: pool)
                return true
            }
        } else {
            found = false
        }
        if !found {
            writeNumber(fields.relatedIso, minDigits: 1, into: &out)
        }
    }

    /// get_name_for_month in ICU4X, and the cases of MonthPlaceholderValue in try_write_field.
    @inlinable
    func writeMonth(_ fields: CalendarFields, _ count: Int, into out: inout TextOutput) {
        guard let names = monthNames else {
            writeMonthCode(fields, into: &out)
            return
        }
        let index = fields.monthNumber - 1
        let done: Bool = C.MonthNames.withTables { pool, _, _, _, words in
            let at = names.start + 1
            switch words[names.start] {
            case 0:
                writeNumber(fields.monthNumber, minDigits: count, into: &out)
                return true
            case 1:
                guard fields.leapStatus == .normal && index >= 0 && index < 12 else { return false }
                out.append(words[at + index], from: pool)
                return true
            case 2:
                if fields.leapStatus == .leap || (fields.leapStatus == .base && fields.monthNumber < fields.monthOrdinal) {
                    guard index >= 0 && index < 12 else { return false }
                    out.append(words[at + 12 + index], from: pool)
                } else {
                    guard index >= 0 && index < 12 else { return false }
                    out.append(words[at + index], from: pool)
                }
                return true
            case 3:
                if fields.leapStatus == .leap {
                    writePlaceholderPattern(words, at: at, pool: pool, number: fields.monthNumber, minDigits: count, into: &out)
                } else {
                    writeNumber(fields.monthNumber, minDigits: count, into: &out)
                }
                return true
            case 4:
                // [sized, pattern] for the leap month, then [sized, pattern] for its base month.
                let firstPattern = at + 1
                let second = firstPattern + 1 + Int(words[firstPattern])
                if fields.leapStatus == .leap {
                    writePlaceholderPattern(words, at: firstPattern, pool: pool, number: fields.monthNumber + Int(Int32(bitPattern: words[at])), minDigits: count, into: &out)
                } else if fields.leapStatus == .base {
                    writePlaceholderPattern(words, at: second + 1, pool: pool, number: fields.monthNumber + Int(Int32(bitPattern: words[second])), minDigits: count, into: &out)
                } else {
                    writeNumber(fields.monthNumber, minDigits: count, into: &out)
                }
                return true
            default:
                return false
            }
        }
        if !done {
            writeMonthCode(fields, into: &out)
        }
    }

    /// A pattern with one placeholder, such as "闰{0}", with a number in the placeholder.
    @inlinable
    func writePlaceholderPattern(_ words: Span<UInt32>, at start: Int, pool: Span<UInt8>, number: Int, minDigits: Int, into out: inout TextOutput) {
        let n = Int(words[start])
        for i in 0 ..< n {
            let w = words[start + 1 + i]
            if w.isField {
                writeNumber(number, minDigits: minDigits, into: &out)
            } else {
                out.append(w, from: pool)
            }
        }
    }

    /// The month code, such as "M05L" (the error case of ICU4X).
    @inlinable
    func writeMonthCode(_ fields: CalendarFields, into out: inout TextOutput) {
        out.append(0x4D)
        out.appendASCII(fields.monthNumber, minDigits: 2)
        if fields.leapStatus == .leap {
            out.append(0x4C)
        }
    }

    @inlinable
    func writeWeekday(_ weekday: Int, into out: inout TextOutput) {
        guard let names = weekdayNames else { return }
        FS.WeekdayNames.withTables { pool, _, _, _, words in
            if weekday < Int(words[names.start]) {
                out.append(words[names.start + 1 + weekday], from: pool)
            }
        }
    }

    /// get_name_for_day_period in ICU4X.
    @inlinable
    func writeDayPeriod(_ symbol: UInt8, _ dateTime: DateTime, into out: inout TextOutput) {
        guard let names = dayPeriodNames else { return }
        FS.DayPeriodNames.withTables { pool, _, _, _, words in
            let n = Int(words[names.start])
            let texts = names.start + 1
            if symbol == symbolB && n > 4 {
                // The first 4 bytes of name 4 are the rules of the flexible day periods (DayPeriodRules in ICU4X).
                let rules = words[texts + 4]
                if rules.textCount >= 4 {
                    let o = rules.textOffset
                    let raw = UInt32(pool[o]) << 17 | UInt32(pool[o + 1]) << 10 | UInt32(pool[o + 2]) << 3 | UInt32(pool[o + 3])
                    let transitions = raw & 0xFF_FFFF
                    let upToHour = (transitions << UInt32(31 - dateTime.hour)).nonzeroBitCount
                    let offset = upToHour == 0 ? transitions.nonzeroBitCount - 1 : upToHour - 1
                    if offset == 0 {
                        out.append(TextRef(o + 4) << 8 | TextRef(rules.textCount - 4), from: pool)
                        return
                    }
                    if 4 + offset < n {
                        out.append(words[texts + 4 + offset], from: pool)
                        return
                    }
                }
            }
            if symbol == symbolb && dateTime.minute == 0 && dateTime.second == 0 {
                if dateTime.hour == 0 && n > 3 && words[texts + 3].textCount > 0 {
                    out.append(words[texts + 3], from: pool)
                    return
                }
                if dateTime.hour == 12 && n > 2 && words[texts + 2].textCount > 0 {
                    out.append(words[texts + 2], from: pool)
                    return
                }
            }
            out.append(words[texts + (dateTime.hour < 12 ? 0 : 1)], from: pool)
        }
    }
}

// MARK: - Any calendar

/// The 6 calendars, for a formatter that picks the calendar at run time. The generated data module conforms AllCalendars to it if all 6 calendars have data.
public protocol CalendarSet {
    associatedtype GregorianCalendar: BakedCalendar
    associatedtype BuddhistCalendar: BakedCalendar
    associatedtype JapaneseCalendar: BakedCalendar
    associatedtype HebrewCalendar: BakedCalendar
    associatedtype ChineseCalendar: BakedCalendar
    associatedtype HijriCalendar: BakedCalendar
}

/// Picks the calendar from the -u-ca- keyword of the locale, like DateTimeFormatter in ICU4X. Gregorian if there is no keyword.
/// It uses the markers of all 6 calendars.
public enum AnyCalendarFormatter<S: CalendarSet, FS: BakedFieldSet> {
    case gregorian(FixedCalendarFormatter<S.GregorianCalendar, FS>)
    case buddhist(FixedCalendarFormatter<S.BuddhistCalendar, FS>)
    case japanese(FixedCalendarFormatter<S.JapaneseCalendar, FS>)
    case hebrew(FixedCalendarFormatter<S.HebrewCalendar, FS>)
    case chinese(FixedCalendarFormatter<S.ChineseCalendar, FS>)
    case hijri(FixedCalendarFormatter<S.HijriCalendar, FS>)

    @inlinable
    public init?(locale text: String, length: Length) {
        guard let locale = LocaleID(text) else { return nil }
        let wrapped: Self?
        switch locale.calendar {
        case keyword("buddhist"): wrapped = FixedCalendarFormatter(locale: locale, length: length).map { .buddhist($0) }
        case keyword("japanese"): wrapped = FixedCalendarFormatter(locale: locale, length: length).map { .japanese($0) }
        case keyword("hebrew"): wrapped = FixedCalendarFormatter(locale: locale, length: length).map { .hebrew($0) }
        case keyword("chinese"): wrapped = FixedCalendarFormatter(locale: locale, length: length).map { .chinese($0) }
        case keyword("islamic"): wrapped = FixedCalendarFormatter(locale: locale, length: length).map { .hijri($0) }
        default: wrapped = FixedCalendarFormatter(locale: locale, length: length).map { .gregorian($0) }
        }
        guard let wrapped else { return nil }
        self = wrapped
    }

    @inlinable
    public func format(_ dateTime: DateTime, into out: inout TextOutput) -> Bool {
        switch self {
        case .gregorian(let f): return f.format(dateTime, into: &out)
        case .buddhist(let f): return f.format(dateTime, into: &out)
        case .japanese(let f): return f.format(dateTime, into: &out)
        case .hebrew(let f): return f.format(dateTime, into: &out)
        case .chinese(let f): return f.format(dateTime, into: &out)
        case .hijri(let f): return f.format(dateTime, into: &out)
        }
    }
}

/// The first 8 bytes of a keyword value, packed as LocaleID.calendar.
@inlinable
func keyword(_ text: StaticString) -> UInt64 {
    var value: UInt64 = 0
    text.withUTF8Buffer { buffer in
        for (n, b) in buffer.prefix(8).enumerated() {
            value |= UInt64(b) << (8 * UInt64(n))
        }
    }
    return value
}
