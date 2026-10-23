// A value API in the style of Foundation, on top of the typed formatter (RESULTS.md, "A value API").
// The calendar, the styles and the locale are values chosen at run time, as in Calendar(identifier:) and Date.FormatStyle.
// This module imports the data, as Foundation would contain its data. Its functions are not inlinable, as most of Foundation is not.
import DataMarkers
import DateTimeFormat
import DateTimeData

public struct Calendar: Equatable {
    public enum Identifier: Equatable {
        case gregorian, buddhist, japanese, hebrew, chinese, islamicCivil
    }

    public var identifier: Identifier

    public init(identifier: Identifier) {
        self.identifier = identifier
    }
}

public struct DateFormatStyle: Equatable {
    public enum DateStyle: Equatable {
        case omitted, numeric, abbreviated, long, complete
    }

    public enum TimeStyle: Equatable {
        case omitted, shortened
    }

    public var date: DateStyle
    public var time: TimeStyle
    public var locale: String
    public var calendar: Calendar

    public init(date: DateStyle, time: TimeStyle, locale: String, calendar: Calendar) {
        self.date = date
        self.time = time
        self.locale = locale
        self.calendar = calendar
    }

    /// Formats one date. It makes a new formatter each time, as a format style with no cache would.
    public func format(_ dateTime: DateTime) -> String? {
        StyleFormatter(self)?.format(dateTime)
    }
}

/// A formatter made from a style, which the caller can keep.
public struct StyleFormatter {
    enum ForCalendar<FS: BakedFieldSet> {
        case gregorian(FixedCalendarFormatter<Gregorian, FS>)
        case buddhist(FixedCalendarFormatter<Buddhist, FS>)
        case japanese(FixedCalendarFormatter<Japanese, FS>)
        case hebrew(FixedCalendarFormatter<Hebrew, FS>)
        case chinese(FixedCalendarFormatter<Chinese, FS>)
        case hijri(FixedCalendarFormatter<Hijri, FS>)

        init?(_ identifier: Calendar.Identifier, _ locale: LocaleID, _ length: Length) {
            switch identifier {
            case .gregorian:
                guard let f = FixedCalendarFormatter<Gregorian, FS>(locale: locale, length: length) else { return nil }
                self = .gregorian(f)
            case .buddhist:
                guard let f = FixedCalendarFormatter<Buddhist, FS>(locale: locale, length: length) else { return nil }
                self = .buddhist(f)
            case .japanese:
                guard let f = FixedCalendarFormatter<Japanese, FS>(locale: locale, length: length) else { return nil }
                self = .japanese(f)
            case .hebrew:
                guard let f = FixedCalendarFormatter<Hebrew, FS>(locale: locale, length: length) else { return nil }
                self = .hebrew(f)
            case .chinese:
                guard let f = FixedCalendarFormatter<Chinese, FS>(locale: locale, length: length) else { return nil }
                self = .chinese(f)
            case .islamicCivil:
                guard let f = FixedCalendarFormatter<Hijri, FS>(locale: locale, length: length) else { return nil }
                self = .hijri(f)
            }
        }

        func format(_ dateTime: DateTime, into out: inout TextOutput) -> Bool {
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

    enum Storage {
        case ymd(ForCalendar<YMD>)
        case ymde(ForCalendar<YMDE>)
        case ymdt(ForCalendar<YMDT>)
        case time(FixedCalendarFormatter<NoCalendar, T>)
    }

    let storage: Storage

    /// Returns nil if the locale cannot be parsed, if data is missing, or for date .complete with a time (not in the prototype).
    public init?(_ style: DateFormatStyle) {
        guard let locale = LocaleID(style.locale) else { return nil }
        let length: Length
        switch style.date {
        case .long, .complete: length = .long
        case .abbreviated: length = .medium
        case .numeric, .omitted: length = .short
        }
        switch (style.date, style.time) {
        case (.omitted, .omitted), (.complete, .shortened):
            return nil
        case (.omitted, .shortened):
            guard let f = FixedCalendarFormatter<NoCalendar, T>(locale: locale, length: .short) else { return nil }
            storage = .time(f)
        case (.complete, .omitted):
            guard let f = ForCalendar<YMDE>(style.calendar.identifier, locale, length) else { return nil }
            storage = .ymde(f)
        case (_, .omitted):
            guard let f = ForCalendar<YMD>(style.calendar.identifier, locale, length) else { return nil }
            storage = .ymd(f)
        case (_, .shortened):
            guard let f = ForCalendar<YMDT>(style.calendar.identifier, locale, length) else { return nil }
            storage = .ymdt(f)
        }
    }

    public func format(_ dateTime: DateTime, into out: inout TextOutput) -> Bool {
        switch storage {
        case .ymd(let f): return f.format(dateTime, into: &out)
        case .ymde(let f): return f.format(dateTime, into: &out)
        case .ymdt(let f): return f.format(dateTime, into: &out)
        case .time(let f): return f.format(dateTime, into: &out)
        }
    }

    public func format(_ dateTime: DateTime) -> String? {
        var out = TextOutput()
        guard format(dateTime, into: &out) else { return nil }
        return out.string
    }
}
