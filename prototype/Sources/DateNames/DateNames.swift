// The date names component, like icu_datetime in ICU4X: the markers, the calendars, and the API.
import DataMarkers

// MARK: - The 4 markers

/// The month names of the Gregorian calendar.
public enum MonthNamesGregorianV1: DataMarker {
    public typealias DataStruct = NameList
    public static var name: StaticString { "MonthNamesGregorianV1" }
}

/// The month names of the Japanese calendar.
public enum MonthNamesJapaneseV1: DataMarker {
    public typealias DataStruct = NameList
    public static var name: StaticString { "MonthNamesJapaneseV1" }
}

/// The weekday names of the Gregorian calendar.
public enum WeekdayNamesGregorianV1: DataMarker {
    public typealias DataStruct = NameList
    public static var name: StaticString { "WeekdayNamesGregorianV1" }
}

/// The weekday names of the Japanese calendar.
public enum WeekdayNamesJapaneseV1: DataMarker {
    public typealias DataStruct = NameList
    public static var name: StaticString { "WeekdayNamesJapaneseV1" }
}

// MARK: - Calendars

/// A calendar names its markers as types, so the compiler picks the data. See DESIGN.md, decision 2.
public protocol CalendarSystem {
    associatedtype MonthNamesMarker: DataMarker where MonthNamesMarker.DataStruct == NameList
    associatedtype WeekdayNamesMarker: DataMarker where WeekdayNamesMarker.DataStruct == NameList
}

public enum Gregorian: CalendarSystem {
    public typealias MonthNamesMarker = MonthNamesGregorianV1
    public typealias WeekdayNamesMarker = WeekdayNamesGregorianV1
}

public enum Japanese: CalendarSystem {
    public typealias MonthNamesMarker = MonthNamesJapaneseV1
    public typealias WeekdayNamesMarker = WeekdayNamesJapaneseV1
}

// MARK: - Widths

/// The width and context of names. The attribute is the one of ICU4X (DESIGN.md, decision 3).
public enum NameWidth {
    case abbreviated, narrow, wide, short
    case standaloneAbbreviated, standaloneNarrow, standaloneWide, standaloneShort

    @inlinable
    public var attribute: String {
        switch self {
        case .abbreviated: return "3"
        case .narrow: return "4"
        case .wide: return "5"
        case .short: return "6"
        case .standaloneAbbreviated: return "3s"
        case .standaloneNarrow: return "4s"
        case .standaloneWide: return "5s"
        case .standaloneShort: return "6s"
        }
    }
}

// MARK: - The API

/// The month names of calendar C, for one locale and width.
public struct MonthNames<C: CalendarSystem> {
    public var list: NameList

    /// Uses the built-in data. Needs the module DateNamesData, which conforms the marker to BakedDataMarker.
    @inlinable
    public init?(locale: String, width: NameWidth) where C.MonthNamesMarker: BakedDataMarker {
        guard let list = loadWithFallback(DataKey(locale: locale, attribute: width.attribute), { C.MonthNamesMarker.bakedLookup($0) }) else { return nil }
        self.list = list
    }

    /// Uses data from the app's own provider for this marker.
    @inlinable
    public init?<P: DataProvider>(locale: String, width: NameWidth, provider: P) where P.Marker == C.MonthNamesMarker {
        guard let list = loadWithFallback(DataKey(locale: locale, attribute: width.attribute), { provider.load($0) }) else { return nil }
        self.list = list
    }

    /// The name of month 1 to 12.
    @inlinable
    public subscript(month: Int) -> String { list.names[month - 1] }
}

/// The weekday names of calendar C, for one locale and width. Weekday 1 is Sunday.
public struct WeekdayNames<C: CalendarSystem> {
    public var list: NameList

    @inlinable
    public init?(locale: String, width: NameWidth) where C.WeekdayNamesMarker: BakedDataMarker {
        guard let list = loadWithFallback(DataKey(locale: locale, attribute: width.attribute), { C.WeekdayNamesMarker.bakedLookup($0) }) else { return nil }
        self.list = list
    }

    @inlinable
    public init?<P: DataProvider>(locale: String, width: NameWidth, provider: P) where P.Marker == C.WeekdayNamesMarker {
        guard let list = loadWithFallback(DataKey(locale: locale, attribute: width.attribute), { provider.load($0) }) else { return nil }
        self.list = list
    }

    /// The name of weekday 1 (Sunday) to 7 (Saturday).
    @inlinable
    public subscript(weekday: Int) -> String { list.names[weekday - 1] }
}
