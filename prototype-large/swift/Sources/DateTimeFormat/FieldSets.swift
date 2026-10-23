// The field sets: each names the markers that it uses, like the field sets of ICU4X (DESIGN.md, decision 10).
// A field set that does not use a kind of data names NeverMarker, so the formatter refers to no tables of that kind.
import DataMarkers

public protocol FieldSet {
    associatedtype WeekdayNames: DataMarker
    associatedtype DayPeriodNames: DataMarker
    associatedtype TimePatterns: DataMarker
    associatedtype GluePatterns: DataMarker
    associatedtype DecimalSymbols: DataMarker
    associatedtype DecimalDigits: DataMarker
    /// The attribute of the date patterns, such as "ym0d". Not used if hasDate is false.
    static var dateAttribute: StaticString { get }
    static var hasDate: Bool { get }
    static var hasTime: Bool { get }
}

/// A field set whose markers all have built-in data. The generated data module adds this conformance (Conformances.swift).
public protocol BakedFieldSet: FieldSet where WeekdayNames: BakedDataMarker, DayPeriodNames: BakedDataMarker, TimePatterns: BakedDataMarker, GluePatterns: BakedDataMarker, DecimalSymbols: BakedDataMarker, DecimalDigits: BakedDataMarker {}

/// Year, month and day.
public enum YMD: FieldSet {
    public typealias WeekdayNames = NeverMarker
    public typealias DayPeriodNames = NeverMarker
    public typealias TimePatterns = NeverMarker
    public typealias GluePatterns = NeverMarker
    public typealias DecimalSymbols = DecimalSymbolsV1
    public typealias DecimalDigits = DecimalDigitsV1
    public static var dateAttribute: StaticString { "ym0d" }
    public static var hasDate: Bool { true }
    public static var hasTime: Bool { false }
}

/// Year, month, day and weekday.
public enum YMDE: FieldSet {
    public typealias WeekdayNames = DatetimeNamesWeekdayV1
    public typealias DayPeriodNames = NeverMarker
    public typealias TimePatterns = NeverMarker
    public typealias GluePatterns = NeverMarker
    public typealias DecimalSymbols = DecimalSymbolsV1
    public typealias DecimalDigits = DecimalDigitsV1
    public static var dateAttribute: StaticString { "ym0de" }
    public static var hasDate: Bool { true }
    public static var hasTime: Bool { false }
}

/// Hour and minute, in the hour cycle of the locale.
public enum T: FieldSet {
    public typealias WeekdayNames = NeverMarker
    public typealias DayPeriodNames = DatetimeNamesDayperiodV1
    public typealias TimePatterns = DatetimePatternsTimeV1
    public typealias GluePatterns = NeverMarker
    public typealias DecimalSymbols = DecimalSymbolsV1
    public typealias DecimalDigits = DecimalDigitsV1
    public static var dateAttribute: StaticString { "" }
    public static var hasDate: Bool { false }
    public static var hasTime: Bool { true }
}

/// Year, month and day, with hour and minute.
public enum YMDT: FieldSet {
    public typealias WeekdayNames = NeverMarker
    public typealias DayPeriodNames = DatetimeNamesDayperiodV1
    public typealias TimePatterns = DatetimePatternsTimeV1
    public typealias GluePatterns = DatetimePatternsGlueV1
    public typealias DecimalSymbols = DecimalSymbolsV1
    public typealias DecimalDigits = DecimalDigitsV1
    public static var dateAttribute: StaticString { "ym0d" }
    public static var hasDate: Bool { true }
    public static var hasTime: Bool { true }
}
