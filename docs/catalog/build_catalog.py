"""Builds the catalog of data kinds for Foundation: docs/catalog/data-kinds.json and docs/MARKER-CATALOG.md.

This script is the only source of the catalog (DESIGN-DATA-KINDS.md, section 3). It builds every name from its parts by the naming rule,
checks every word against the word lists, and writes the registry and the document. Run: python3 -I -B docs/catalog/build_catalog.py

Facts come from swift-foundation at commit 662eac61 (2026-10-26): the ICU calls in Sources/FoundationInternationalization and
Sources/FoundationEssentials. The CLDR paths are the names of the CLDR JSON data. Status: a draft design. Nothing is built.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# MARK: - The word lists (DESIGN-DATA-KINDS.md, section 4). A new word needs a review.

FEATURES = ["Date", "Calendar", "RelativeDate", "Duration", "TimeZone", "Number", "Currency", "Unit", "List", "Plural",
            "LocaleName", "Locale", "Collation", "Text", "URL", "Encoding"]
DATA = ["Names", "Patterns", "Symbols", "Rules", "Info", "Tables"]
ITEMS = {
    "Date": ["Month", "Era", "Cyclic", "Weekday", "Quarter", "DayPeriod", "Field", "Style", "Skeleton", "Glue", "Interval", "HourCycle", "Context", "Parse"],
    "Calendar": ["Week", "Preference", "JapaneseEras", "UmmAlQura"],
    "RelativeDate": ["Unit"],
    "Duration": ["Time"],
    "TimeZone": ["Formats", "Metazone", "Zone", "MetazoneMap", "Aliases", "Windows", "Transitions"],
    "Number": ["Decimal", "Compact", "NumberingSystems", "Algorithmic"],
    "Currency": ["Display", "Format", "Fractions", "Region", "Codes"],
    "Unit": ["Digital", "Duration", "Preference", "MeasurementSystem"],
    "List": ["Join"],
    "Plural": ["Cardinal"],
    "LocaleName": ["Language", "Script", "Region", "Variant", "Keyword", "Pattern"],
    "Locale": ["LikelySubtags", "Parents", "Aliases", "WindowsLCID", "Available", "Regions", "Layout", "Delimiters", "Exemplars"],
    "Collation": ["Root", "Tailoring"],
    "Text": ["CaseMapping", "BidiClass", "Script", "Block"],
    "URL": ["IDNA"],
    "Encoding": ["Converters"],
}

# The data calendars: the calendars that have their own data. Several Foundation calendars share the data of one data calendar.
# source: "cldr" = public CLDR has this calendar. "apple" = not in public CLDR, so the data must come from Apple's data (to check).
CALENDARS = [
    ("Gregorian", ["gregorian", "iso8601"], "gregorian", "cldr"),
    ("Buddhist", ["buddhist"], "buddhist", "cldr"),
    ("Chinese", ["chinese"], "chinese", "cldr"),
    ("Coptic", ["coptic"], "coptic", "cldr"),
    ("Dangi", ["dangi"], "dangi", "cldr"),
    ("Ethiopic", ["ethiopicAmeteMihret"], "ethiopic", "cldr"),
    ("EthiopicAmeteAlem", ["ethiopicAmeteAlem"], "ethiopic-amete-alem", "cldr"),
    ("Hebrew", ["hebrew"], "hebrew", "cldr"),
    ("Indian", ["indian"], "indian", "cldr"),
    ("Islamic", ["islamic", "islamicCivil", "islamicTabular", "islamicUmmAlQura"], "islamic", "cldr"),
    ("Japanese", ["japanese"], "japanese", "cldr"),
    ("Persian", ["persian"], "persian", "cldr"),
    ("Roc", ["republicOfChina"], "roc", "cldr"),
    ("Bangla", ["bangla"], "bangla", "apple"),
    ("Gujarati", ["gujarati"], "gujarati", "apple"),
    ("Kannada", ["kannada"], "kannada", "apple"),
    ("Malayalam", ["malayalam"], "malayalam", "apple"),
    ("Marathi", ["marathi"], "marathi", "apple"),
    ("Odia", ["odia"], "odia", "apple"),
    ("Tamil", ["tamil"], "tamil", "apple"),
    ("Telugu", ["telugu"], "telugu", "apple"),
    ("Vikram", ["vikram"], "vikram", "apple"),
    ("Vietnamese", ["vietnamese"], "vietnamese", "apple"),
]
CYCLIC_CALENDARS = ["Chinese", "Dangi", "Vietnamese"]

# Keys: "locale" = one value for each locale, with the locale fallback. "region" = one value for each region. "none" = one value for all.
# Rule: the reason for a separate kind (DESIGN-DATA-KINDS.md, section 5): 1 = separate API function, 2 = a build can leave it out
# (for example a calendar), 4 = always used together. Choices at run time inside one function are attributes (rule 3).

# Each entry: feature, data, item, per_calendar, key, attributes, content, source, used_by, icu4x, rule, user setting
KINDS = [
    # Date and time formatting, one kind for each data calendar
    ("Date", "Names", "Month", True, "locale", "context (format, standalone) x width (abbreviated, wide, narrow), month patterns for leap months",
     "Month names", "dates/calendars/<cal>/months, monthPatterns", "Date.FormatStyle, Date.VerbatimFormatStyle, parse strategies (udat)", "DatetimeNamesMonth<Cal>V1", "2", "dates, calendar"),
    ("Date", "Names", "Era", True, "locale", "width (abbreviated, wide, narrow)",
     "Era names", "dates/calendars/<cal>/eras", "Date.FormatStyle era field (udat)", "DatetimeNamesYear<Cal>V1 (with cyclic years)", "2", "dates, calendar"),
    ("Date", "Names", "Cyclic", True, "locale", "set (years, zodiacs) x width",
     "Cyclic year names, only for the calendars in CYCLIC_CALENDARS", "dates/calendars/<cal>/cyclicNameSets", "Date.FormatStyle cyclicYear field (udat)", "DatetimeNamesYear<Cal>V1 (with era names)", "2", "dates, calendar"),
    ("Date", "Patterns", "Style", True, "locale", "date or time x style (full, long, medium, short)",
     "The date and time patterns of each style", "dates/calendars/<cal>/dateFormats, timeFormats", "Date.FormatStyle with date and time styles (udat)", "none (ICU4X has no styles)", "2", "dates, calendar"),
    ("Date", "Patterns", "Skeleton", True, "locale", "skeleton, append items",
     "Skeleton to pattern tables of the pattern generator", "dates/calendars/<cal>/dateTimeFormats/availableFormats, appendItems", "Date.FormatStyle with fields, Date.FormatString (udatpg_getBestPatternWithOptions)", "none (ICU4X uses semantic skeletons: DatetimePatternsDate<Cal>V1)", "2", "dates, calendar"),
    ("Date", "Patterns", "Glue", True, "locale", "style (full, long, medium, short) x variant (standard, atTime)",
     "How a date and a time join", "dates/calendars/<cal>/dateTimeFormats", "Date.FormatStyle with a date and a time (udat)", "DatetimePatternsGlueV1 (one for all calendars)", "2", "dates, calendar"),
    ("Date", "Patterns", "Interval", True, "locale", "skeleton x greatest difference, fallback",
     "Date interval patterns", "dates/calendars/<cal>/dateTimeFormats/intervalFormats", "Date.IntervalFormatStyle (udtitvfmt)", "DatetimePatternsRangeDate<Cal>V1", "1, 2", "date-intervals, calendar"),
    # Date and time formatting, shared by all calendars
    ("Date", "Names", "Weekday", False, "locale", "context x width (abbreviated, wide, narrow, short)",
     "Weekday names. CLDR has them for each calendar, but all calendars use the Gregorian names", "dates/calendars/gregorian/days", "Date.FormatStyle weekday fields (udat)", "DatetimeNamesWeekdayV1", "4", "dates"),
    ("Date", "Names", "Quarter", False, "locale", "context x width",
     "Quarter names", "dates/calendars/gregorian/quarters", "Date.FormatStyle quarter field (udat)", "none", "4", "dates"),
    ("Date", "Names", "DayPeriod", False, "locale", "context x width, noon and midnight, flexible periods",
     "AM, PM, and the flexible day periods (\"in the morning\"), with their hour rules", "dates/calendars/gregorian/dayPeriods, supplemental/dayPeriods", "Date.FormatStyle hour and dayPeriod fields (udat)", "DatetimeNamesDayperiodV1", "4", "dates"),
    ("Date", "Names", "Field", False, "locale", "field x width",
     "Display names of the date fields (\"year\", \"month\")", "dates/fields/<field>/displayName", "the pattern generator (append items)", "none", "4", "dates"),
    ("Date", "Rules", "HourCycle", False, "region", "none",
     "The preferred and allowed hour cycles (12 or 24 hours)", "supplemental/timeData", "Locale.hourCycle, the j skeleton (udatpg_getDefaultHourCycle)", "none (in the patterns)", "4", "dates"),
    ("Date", "Rules", "Context", False, "locale", "usage x context",
     "Capitalization rules for names at the start of a sentence, in a menu, or alone", "contextTransforms", "capitalizationContext of the format styles (UDISPCTX_CAPITALIZATION)", "none", "4", "dates"),
    ("Date", "Rules", "Parse", False, "locale", "scope (date, number)",
     "Characters that parsing treats as the same", "characters/parseLenients", "Date.ParseStrategy, number parse strategies (lenient parsing)", "none", "1", "date-parsing"),
    # Calendar arithmetic
    ("Calendar", "Rules", "Week", False, "region", "none",
     "First weekday, minimum days in the first week, the weekend", "supplemental/weekData", "Calendar.firstWeekday, minimumDaysInFirstWeek, isDateInWeekend (ucal)", "CalendarWeekV1", "4", "core"),
    ("Calendar", "Rules", "Preference", False, "region", "none",
     "The calendars that a region uses, in order", "supplemental/calendarPreferenceData", "the default calendar of a locale (ucal_getKeywordValuesForLocale)", "CalendarPreferredV1", "4", "core"),
    ("Calendar", "Tables", "JapaneseEras", False, "none", "none",
     "The start dates of the Japanese eras", "supplemental/calendarData/japanese/eras", "Calendar(identifier: .japanese)", "CalendarJapaneseModernV1", "2", "calendar"),
    ("Calendar", "Tables", "UmmAlQura", False, "none", "none",
     "The month lengths of the Umm al-Qura calendar", "ICU islamic-umalqura table (not CLDR)", "Calendar(identifier: .islamicUmmAlQura)", "none (in code)", "2", "calendar"),
    # Relative dates and durations
    ("RelativeDate", "Patterns", "Unit", False, "locale", "unit (year, quarter, month, week, day, hour, minute, second, each weekday) x width (long, short, narrow)",
     "\"yesterday\", \"in 3 days\", \"next Monday\", with plural forms", "dates/fields/<unit>/relative, relativeTime", "Date.RelativeFormatStyle, Date.AnchoredRelativeFormatStyle (ureldatefmt)", "DatetimeRelative<Unit><Length>V1 (24 kinds)", "1", "relative-dates"),
    ("Duration", "Patterns", "Time", False, "locale", "fields (hm, hms, ms)",
     "Patterns such as \"1:05:09\"", "units/durationUnit", "Duration.TimeFormatStyle (uatmufmt_getTimePattern)", "UnitsDurationDigitalV1", "1", "durations"),
    # Time zones
    ("TimeZone", "Names", "Formats", False, "locale", "kind (GMT, GMT zero, hour, region, fallback)",
     "The patterns that build time zone names, such as \"GMT+02:00\" and \"France Time\"", "dates/timeZoneNames (gmtFormat, hourFormat, regionFormat, fallbackFormat)", "TimeZone.localizedName, the z, O, v, V fields (ucal_getTimeZoneDisplayName, uatimezone_getDisplayName)", "TimezoneNamesEssentialsV1", "1", "time-zone-names"),
    ("TimeZone", "Names", "Metazone", False, "locale", "metazone x style (generic, standard, daylight) x width (long, short)",
     "Names such as \"Central European Summer Time\"", "dates/timeZoneNames/metazone", "the same", "TimezoneNames(Generic|Specific|Standard)(Long|Short)V1", "1", "time-zone-names"),
    ("TimeZone", "Names", "Zone", False, "locale", "zone x style",
     "Exemplar cities and names for single zones", "dates/timeZoneNames/zone", "the same, and the exemplarLocation field", "TimezoneNamesCities(Root|Override)V1, TimezoneNamesLocations(Root|Override)V1", "1", "time-zone-names"),
    ("TimeZone", "Info", "MetazoneMap", False, "none", "zone",
     "Which metazone a zone belongs to, over time, and the primary zone of each region", "supplemental/metaZones, primaryZones", "time zone names", "TimezonePeriodsV1", "1", "time-zone-names"),
    ("TimeZone", "Info", "Aliases", False, "none", "zone",
     "Canonical zone IDs and their aliases", "bcp47/timezone", "TimeZone(identifier:) (ucal_getCanonicalTimeZoneID)", "TimezoneIdentifiersIanaCoreV1, TimezoneIdentifiersIanaExtendedV1", "4", "core"),
    ("TimeZone", "Info", "Windows", False, "none", "Windows zone",
     "Windows zone names to IANA zones", "supplemental/windowsZones", "TimeZone on Windows (ucal_getTimeZoneIDForWindowsID)", "TimezoneIdentifiersWindowsV1", "2", "windows"),
    ("TimeZone", "Rules", "Transitions", False, "none", "zone",
     "The offsets and transitions of each zone (not locale data)", "IANA tzdata (ICU zoneinfo64)", "TimeZone offsets and daylight saving time (TimeZone_ICUResource, uatimezone)", "none (outside ICU4X data)", "4", "core"),
    # Numbers
    ("Number", "Symbols", "Decimal", False, "locale", "numbering system",
     "Decimal and grouping separators, signs, percent, exponent, infinity, NaN, and the default and native numbering systems", "numbers/symbols-numberSystem-<ns>, defaultNumberingSystem", "all number format styles, digits in dates (unumf, unum)", "DecimalSymbolsV1", "4", "core"),
    ("Number", "Patterns", "Decimal", False, "locale", "numbering system x type (decimal, percent, scientific)",
     "Number patterns and the minimum grouping digits", "numbers/decimalFormats, percentFormats, scientificFormats, minimumGroupingDigits", "IntegerFormatStyle, FloatingPointFormatStyle, Decimal.FormatStyle, percent (unumf)", "DecimalSymbolsV1, DecimalPercentV1 (part)", "1", "numbers"),
    ("Number", "Patterns", "Compact", False, "locale", "numbering system x width (short, long) x magnitude x plural form",
     "\"1.2K\", \"1.2 thousand\"", "numbers/decimalFormats-numberSystem-<ns>/short, long", "notation .compactName (unumf compact-short)", "DecimalCompactShortV1, DecimalCompactLongV1", "1", "numbers"),
    ("Number", "Info", "NumberingSystems", False, "none", "numbering system",
     "The digits of each numbering system, and if it is algorithmic", "supplemental/numberingSystems", "Locale.NumberingSystem, digits everywhere (unumsys)", "DecimalDigitsV1", "4", "core"),
    ("Number", "Rules", "Algorithmic", False, "none", "numbering system",
     "Rules for numbering systems that are not decimal digits, such as Hebrew or Roman numerals", "rbnf (root)", "a locale with -u-nu- of an algorithmic system (unumsys_isAlgorithmic)", "none (in code in ICU4X)", "2", "algorithmic-numbers"),
    # Currencies
    ("Currency", "Names", "Display", False, "locale", "currency x form (symbol, narrow symbol, name, plural names)",
     "\"$\", \"US$\", \"US dollar\", \"US dollars\"", "numbers/currencies", "currency format styles with .narrow, .standard, .fullName (unumf unit-width), Locale.localizedString(forCurrencyCode:) (ucurr_getName)", "CurrencyEssentialsV1, CurrencyDisplaynameV1, CurrencySymbolsV1", "1", "currencies"),
    ("Currency", "Patterns", "Format", False, "locale", "numbering system x type (standard, accounting), currency spacing, unit pattern",
     "Currency patterns", "numbers/currencyFormats-numberSystem-<ns>", "currency format styles, sign-accounting (unumf)", "CurrencyPatternsDataV1, CurrencyExtendedDataV1", "1", "currencies"),
    ("Currency", "Info", "Fractions", False, "none", "currency",
     "Digits and rounding of each currency", "supplemental/currencyData/fractions", "currency format styles", "CurrencyFractionsV1", "1", "currencies"),
    ("Currency", "Info", "Region", False, "region", "none",
     "The currency of each region, over time", "supplemental/currencyData/region", "Locale.currency (ucurr_forLocale)", "none", "4", "core"),
    ("Currency", "Info", "Codes", False, "none", "currency",
     "The ISO currency codes and their numeric codes", "supplemental/codeMappings, ISO 4217", "Locale.Currency.isoCurrencies, numeric codes (ucurr_openISOCurrencies, ucurr_getNumericCode)", "none", "4", "core"),
    # Units
    ("Unit", "Names", "Digital", False, "locale", "unit (byte to petabyte, bit) x width x plural form",
     "\"12 MB\", \"12 megabytes\"", "units/<width>/digital-*", "ByteCountFormatStyle (unumf measure-unit/digital)", "none (ICU4X has no digital unit marker)", "1", "byte-counts"),
    ("Unit", "Names", "Duration", False, "locale", "unit (year to nanosecond) x width x plural form",
     "\"3 hours\", \"3 hr\"", "units/<width>/duration-*", "Duration.UnitsFormatStyle (unumf measure-unit/duration)", "UnitsNamesDurationCoreV1, ...ExtendedV1, ...OutlierV1", "1", "durations"),
    ("Unit", "Info", "Preference", False, "region", "quantity x usage",
     "Which units a region uses, for example for temperature", "supplemental/unitPreferenceData", "Locale.measurementSystem related preferences (uameasfmt_getUnitsForUsage)", "UnitsInfoV1 (part)", "4", "core"),
    ("Unit", "Info", "MeasurementSystem", False, "region", "none",
     "Metric, US or UK system, and the paper size", "supplemental/measurementData", "Locale.measurementSystem, usesMetricSystem (ulocdata_getMeasurementSystem)", "none", "4", "core"),
    # Lists
    ("List", "Patterns", "Join", False, "locale", "type (and, or, units) x width (standard, short, narrow) x position (start, middle, end, pair)",
     "\"a, b, and c\"", "listPatterns", "ListFormatStyle, Duration units lists (ulistfmt, uatmufmt_getListPattern). swift-foundation already has Swift data: _FoundationInternationalizationData/ListFormatData.swift", "ListAndV1, ListOrV1, ListUnitV1", "1", "lists"),
    # Plural rules
    ("Plural", "Rules", "Cardinal", False, "locale", "none",
     "Which plural form a number takes (\"1 day\", \"2 days\")", "supplemental/plurals", "used inside number, currency, unit and relative date formatting", "PluralsCardinalV1", "4", "plurals"),
    # Names of languages, scripts and regions
    ("LocaleName", "Names", "Language", False, "locale", "language x form (standard, short, variant, menu)",
     "\"French\", \"Swiss French\"", "localeDisplayNames/languages", "Locale.localizedString(forLanguageCode:), forIdentifier: (uloc_getDisplayLanguage, uloc_getDisplayName)", "LocaleNamesLanguage...V1 (9 kinds), LocaleNamesLanguageV0", "1", "locale-names"),
    ("LocaleName", "Names", "Script", False, "locale", "script x form",
     "\"Cyrillic\"", "localeDisplayNames/scripts", "Locale.localizedString(forScriptCode:) (uloc_getDisplayScript)", "LocaleNamesScript...V1 (3 kinds), LocaleNamesScriptV0", "1", "locale-names"),
    ("LocaleName", "Names", "Region", False, "locale", "region x form (standard, short, variant)",
     "\"Germany\"", "localeDisplayNames/territories", "Locale.localizedString(forRegionCode:) (uloc_getDisplayCountry)", "LocaleNamesRegion...V1 (4 kinds), LocaleNamesRegionV0", "1", "locale-names"),
    ("LocaleName", "Names", "Variant", False, "locale", "variant",
     "\"Polytonic\"", "localeDisplayNames/variants", "Locale.localizedString(forVariantCode:) (uloc_getDisplayVariant)", "LocaleNamesVariantMediumHeavyV1, LocaleNamesVariantV0", "1", "locale-names"),
    ("LocaleName", "Names", "Keyword", False, "locale", "key x type",
     "\"Gregorian Calendar\", \"Phonebook Sort Order\"", "localeDisplayNames/keys, types", "Locale.localizedString(forCalendarIdentifier:), forCollationIdentifier: (uloc_getDisplayKeywordValue)", "none", "1", "locale-names"),
    ("LocaleName", "Patterns", "Pattern", False, "locale", "kind (pattern, separator, key-type pattern)",
     "How the parts of a locale name join: \"English (United States)\"", "localeDisplayNames/localeDisplayPattern", "Locale.localizedString(forIdentifier:) (uloc_getDisplayName)", "LocaleNamesEssentialsV1", "1", "locale-names"),
    # Locale information
    ("Locale", "Info", "LikelySubtags", False, "none", "none",
     "The likely script and region of a language", "supplemental/likelySubtags", "the locale fallback, Locale.maximalIdentifier (uloc_addLikelySubtags, uloc_minimizeSubtags)", "LocaleLikelySubtagsLanguageV1, ...ScriptRegionV1, ...ExtendedV1", "4", "core"),
    ("Locale", "Info", "Parents", False, "none", "none",
     "Parent locales, with the Apple additions", "supplemental/parentLocales, Apple parents", "the locale fallback (ualoc_getAppleParent)", "LocaleParentsV1", "4", "core"),
    ("Locale", "Info", "Aliases", False, "none", "kind (language, script, region, variant)",
     "Old and alias codes and their canonical form", "supplemental/aliases", "Locale.identifier canonicalization (ualoc_canonicalForm, uloc_toLanguageTag)", "LocaleAliasesV1", "4", "core"),
    ("Locale", "Info", "WindowsLCID", False, "none", "none",
     "Windows locale IDs (LCID)", "ICU LCID table (not CLDR)", "Locale(windowsLocaleCode:), windowsLocaleCode (uloc_getLCID, uloc_getLocaleForLCID)", "none", "2", "windows"),
    ("Locale", "Info", "Available", False, "none", "kind (locales, ISO languages, ISO regions)",
     "The list of locales with data, and the ISO code lists", "derived from the data, ISO 639 and ISO 3166", "Locale.availableIdentifiers, Locale.LanguageCode.isoLanguageCodes, Locale.Region.isoRegions (uloc_getAvailable, uloc_getISOLanguages)", "none", "4", "core"),
    ("Locale", "Info", "Regions", False, "none", "region",
     "Which regions contain which regions, and the type of each region", "supplemental/territoryContainment", "Locale.Region.containingRegion, subRegions, continent (uregion)", "none", "1", "regions"),
    ("Locale", "Info", "Layout", False, "locale", "none",
     "Character order and line order", "layout/orientation", "Locale.Language.characterDirection, lineLayoutDirection (uloc_getCharacterOrientation)", "LocaleScriptDirectionV1 (by script)", "4", "core"),
    ("Locale", "Info", "Delimiters", False, "locale", "kind (quotation start and end, alternate)",
     "Quotation marks", "delimiters", "Locale.quotationBeginDelimiter and the related properties (ulocdata_getDelimiter)", "none", "1", "locale-info"),
    ("Locale", "Info", "Exemplars", False, "locale", "set (main, auxiliary, index, numbers, punctuation)",
     "The characters that a language uses", "characters/exemplarCharacters", "Locale.exemplarCharacterSet (ulocdata_getExemplarSet)", "LocaleExemplarCharacters(Main|Auxiliary|Index|Numbers|Punctuation)V1", "1", "locale-info"),
    # Collation
    ("Collation", "Rules", "Root", False, "none", "none",
     "The default sort order of all characters", "CLDR root collation (based on the Unicode DUCET)", "String.compare(_:options:range:locale:), localizedStandardCompare, SortDescriptor, Predicate localized operators (ucol)", "CollationRootV1, CollationDiacriticsV1, CollationJamoV1, CollationSpecialPrimariesV1", "1", "collation"),
    ("Collation", "Rules", "Tailoring", False, "locale", "collation type (standard, phonebook, pinyin, stroke, search, and others)",
     "The changes of each language to the default sort order", "collation/<locale>", "the same, Locale.collation (ucol_open, ucol_getKeywordValuesForLocale)", "CollationTailoringV1, CollationMetadataV1, CollationReorderingV1", "1", "collation"),
    # Text
    ("Text", "Rules", "CaseMapping", False, "none", "language (tr, az, lt, el, nl)",
     "The case rules that depend on the language, such as the Turkish dotless i", "Unicode SpecialCasing, ICU case data", "uppercased(with:), lowercased(with:), capitalized(with:) (ucasemap)", "CaseMapV1, CaseMapUnfoldV1", "1", "case-mapping"),
    ("Text", "Info", "BidiClass", False, "none", "none",
     "The bidirectional class of each character (Unicode data, not locale data)", "Unicode UCD", "BidiClass+ICU.swift", "PropertyEnumBidiClassV1", "1", "core"),
    ("Text", "Info", "Script", False, "none", "none",
     "The script of each character (Unicode data)", "Unicode UCD", "URL lookalike checks, Locale.Script (uscript)", "PropertyEnumScriptV1", "1", "urls"),
    ("Text", "Info", "Block", False, "none", "none",
     "The Unicode block of each character (Unicode data)", "Unicode UCD", "URL lookalike checks (ublock_getCode)", "none", "1", "urls"),
    ("URL", "Rules", "IDNA", False, "none", "none",
     "The mapping of international domain names (UTS 46)", "Unicode IDNA mapping", "URL host parsing (uidna_nameToASCII, uidna_nameToUnicode)", "none (separate crate in ICU4X)", "1", "urls"),
    ("Encoding", "Tables", "Converters", False, "none", "encoding",
     "Conversion tables of legacy text encodings (not locale data)", "ICU converter data", "String(data:encoding:) for legacy encodings (ucnv)", "none", "1", "encodings"),
]

# The user settings (DESIGN-DATA-KINDS.md, section 7): each feature setting, and the features that it needs too.
SETTINGS = {
    "core": ("always in the build: the locale fallback, calendar rules, digits, time zone IDs and offsets", []),
    "dates": ("Date.FormatStyle, Date.VerbatimFormatStyle, Date.FormatString", ["core", "plurals"]),
    "date-intervals": ("Date.IntervalFormatStyle", ["dates"]),
    "date-parsing": ("Date.ParseStrategy and lenient number parsing", ["dates"]),
    "relative-dates": ("Date.RelativeFormatStyle, Date.AnchoredRelativeFormatStyle", ["dates", "numbers", "plurals"]),
    "durations": ("Duration.TimeFormatStyle, Duration.UnitsFormatStyle", ["numbers", "plurals", "lists"]),
    "time-zone-names": ("TimeZone.localizedName, and time zone fields in dates", ["core"]),
    "numbers": ("IntegerFormatStyle, FloatingPointFormatStyle, Decimal.FormatStyle and their parse strategies", ["core", "plurals"]),
    "algorithmic-numbers": ("numbers in algorithmic numbering systems, such as -u-nu-hebr", ["numbers"]),
    "currencies": ("the currency format styles, and currency names", ["numbers", "plurals"]),
    "byte-counts": ("ByteCountFormatStyle", ["numbers", "plurals"]),
    "lists": ("ListFormatStyle", ["core"]),
    "plurals": ("plural rules, used by other features", ["core"]),
    "locale-names": ("the localizedString(for...) methods of Locale", ["core", "currencies"]),
    "locale-info": ("quotation marks and exemplar characters of Locale", ["core"]),
    "regions": ("the region containment of Locale.Region", ["core"]),
    "collation": ("localized string comparison and sorting", ["core"]),
    "case-mapping": ("case changes with a locale", ["core"]),
    "urls": ("URL parsing of international host names", ["core"]),
    "encodings": ("legacy text encodings", []),
    "windows": ("Windows zone names and LCIDs", ["core"]),
    "calendar": ("selected by the calendars setting, not by a feature setting", []),
}


def kind_name(feature, data, item, calendar=None):
    assert feature in FEATURES, feature
    assert data in DATA, data
    assert item in ITEMS[feature], (feature, item)
    return f"{feature}{data}{item}{calendar or ''}V1"


def expand():
    entries = []
    for (feature, data, item, per_cal, key, attrs, content, source, used_by, icu4x, rule, setting) in KINDS:
        cals = [c for c in CALENDARS if not (item == "Cyclic" and c[0] not in CYCLIC_CALENDARS)] if per_cal else [None]
        for cal in cals:
            name = kind_name(feature, data, item, cal[0] if cal else None)
            entries.append({
                "name": name, "feature": feature, "data": data, "item": item,
                "calendar": cal[0] if cal else None,
                "foundationCalendars": cal[1] if cal else None,
                "key": key, "attributes": attrs, "content": content,
                "source": source.replace("<cal>", cal[2]) if cal else source,
                "sourceAvailability": cal[3] if cal else "cldr",
                "usedBy": used_by, "icu4x": icu4x.replace("<Cal>", cal[0]) if cal else icu4x,
                "splitRule": rule,
                "settings": [s.strip() for s in setting.split(",")],
            })
    names = [e["name"] for e in entries]
    assert len(names) == len(set(names)), "duplicate names"
    for e in entries:
        for s in e["settings"]:
            assert s in SETTINGS, s
    return entries


def md_table(rows, header):
    out = ["| " + " | ".join(header) + " |", "|" + "|".join("---" for _ in header) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(x).replace("|", "\\|") for x in r) + " |")
    return "\n".join(out)


def write_doc(entries):
    per_cal = [k for k in KINDS if k[3]]
    shared = [k for k in KINDS if not k[3]]
    counts = {"per_calendar": sum(1 for e in entries if e["calendar"]), "shared": sum(1 for e in entries if not e["calendar"])}
    by_key = {}
    for e in entries:
        by_key[e["key"]] = by_key.get(e["key"], 0) + 1
    L = []
    L.append("# The catalog of data kinds for Foundation")
    L.append("")
    L.append("**Status:** a draft design, 2026-10-26. Nothing in it is built. Generated by `docs/catalog/build_catalog.py`, which also writes the registry `docs/catalog/data-kinds.json`. Do not edit this file by hand: change the script and run it again.")
    L.append("")
    L.append("## What this is")
    L.append("")
    L.append("Every kind of locale data that Foundation needs, defined up front, with its final name, its key, its keys inside (attributes), its source, the API that uses it, and the user setting that selects it. Engineers use these kinds. Users choose only features, calendars and locales (section \"User settings\"), and never see a name.")
    L.append("")
    L.append("**Scope:** swift-foundation (the open source Foundation), at commit `662eac61` of 2026-10-26. The list of features comes from every ICU call in `Sources/FoundationInternationalization` and `Sources/FoundationEssentials`: 188 ICU functions in 28 ICU services. Section \"Not covered\" lists the features that only the Darwin Foundation has.")
    L.append("")
    L.append(f"**Size:** {len(KINDS)} kinds by definition. {len(per_cal)} of them exist once for each data calendar, so the registry has {len(entries)} entries: {counts['per_calendar']} for calendars and {counts['shared']} shared. By key: " + ", ".join(f"{v} keyed by {k}" for k, v in sorted(by_key.items())) + ".")
    L.append("")
    L.append("## How to read a name")
    L.append("")
    L.append("`<Feature><Data><Item>[<Calendar>]V<version>`. Each part is one word from a fixed list:")
    L.append("")
    L.append(md_table([[ "Feature", ", ".join(FEATURES)], ["Data", ", ".join(DATA)], ["Item", "a list for each feature, see the tables"], ["Calendar", "a data calendar, see \"Calendars\""], ["Version", "1 for all kinds now. A new table layout gets a new version."]], ["Part", "Words"]))
    L.append("")
    L.append("Example: `DateNamesMonthChineseV1` = Date, Names, Month, Chinese, version 1 = the month names of the Chinese calendar.")
    L.append("")
    L.append("**Keys.** `locale`: one value for each locale, found with the locale fallback (`fr-CA`, `fr`, root). `region`: one value for each region. `none`: one value for everything. **Attributes** are keys inside a kind that the code chooses at run time, such as a width.")
    L.append("")
    L.append("**Split rules** (`DESIGN-DATA-KINDS.md`, section 5): 1 = a separate function of the API, so the linker can remove it. 2 = a build can leave it out, for example a calendar. 4 = always used together. A choice at run time inside one function is an attribute (rule 3), never a separate kind.")
    L.append("")
    L.append("## Calendars")
    L.append("")
    L.append("Foundation has 27 calendar identifiers. They share the data of 23 data calendars:")
    L.append("")
    L.append(md_table([[c[0], ", ".join(f"`.{x}`" for x in c[1]), f"`{c[2]}`", "public CLDR" if c[3] == "cldr" else "**not in public CLDR**: Apple's data (to check)"] for c in CALENDARS], ["Data calendar", "Foundation identifiers", "Data name", "Source"]))
    L.append("")
    L.append("Calendar arithmetic needs data only for the Japanese eras and Umm al-Qura. The other calendars compute their dates in code (Foundation already has Swift code for most of them).")
    L.append("")
    L.append("## The kinds for each calendar")
    L.append("")
    L.append(f"Each of these exists once for each data calendar. `DateNamesCyclic` exists only for {', '.join(CYCLIC_CALENDARS)}. Each kind holds the complete data of its calendar, with the CLDR inheritance already resolved, as in ICU4X.")
    L.append("")
    L.append(md_table([[f"`{k[0]}{k[1]}{k[2]}<Calendar>V1`", k[6], k[4], k[5], k[7], k[8], k[9], k[10], k[11]] for k in per_cal], ["Name", "Content", "Key", "Attributes", "Source (CLDR)", "Used by", "ICU4X", "Rule", "Setting"]))
    L.append("")
    groups = {}
    for k in shared:
        groups.setdefault(k[0], []).append(k)
    titles = {"Date": "Dates, shared by all calendars", "Calendar": "Calendar arithmetic", "RelativeDate": "Relative dates", "Duration": "Durations",
              "TimeZone": "Time zones", "Number": "Numbers", "Currency": "Currencies", "Unit": "Units", "List": "Lists", "Plural": "Plural rules",
              "LocaleName": "Names of languages, scripts and regions", "Locale": "Locale information", "Collation": "Collation", "Text": "Text",
              "URL": "URLs", "Encoding": "Text encodings"}
    L.append("## The shared kinds")
    L.append("")
    for feature in FEATURES:
        if feature not in groups:
            continue
        L.append(f"### {titles[feature]}")
        L.append("")
        L.append(md_table([[f"`{kind_name(k[0], k[1], k[2])}`", k[6], k[4], k[5], k[7], k[8], k[9], k[10], k[11]] for k in groups[feature]], ["Name", "Content", "Key", "Attributes", "Source", "Used by", "ICU4X", "Rule", "Setting"]))
        L.append("")
    L.append("## User settings")
    L.append("")
    L.append("A user chooses three things. A tool turns them into kinds, with this table and the registry.")
    L.append("")
    L.append("* **locales:** the locales of the app (or its `.lproj` folders). Every kind keyed by `locale` keeps only these locales and their fallback locales. Kinds keyed by `region` or `none` stay whole: they are small.")
    L.append("* **calendars:** the data calendars that the app needs. The kinds for each calendar keep only these calendars. Default: Gregorian.")
    L.append("* **features:** the features below. Each feature also brings the features that it needs.")
    L.append("")
    rows = []
    for s, (desc, needs) in SETTINGS.items():
        kinds = [e["name"] for e in entries if s in e["settings"] and not e["calendar"]]
        cal_kinds = sorted({f"{e['feature']}{e['data']}{e['item']}<Calendar>V1" for e in entries if s in e["settings"] and e["calendar"]})
        rows.append([f"`{s}`", desc, ", ".join(needs) or "nothing", ", ".join(f"`{k}`" for k in cal_kinds + kinds) or "-"])
    L.append(md_table(rows, ["Setting", "What it is for", "Also needs", "Kinds"]))
    L.append("")
    L.append("Code that names its calendar as a type needs no `calendars` setting. With Foundation's value API, the setting is needed (`CONCEPT.md`, section 4).")
    L.append("")
    L.append("## Not covered")
    L.append("")
    L.append("These features are not in swift-foundation, so the source of this catalog does not show their data. A complete catalog for the Darwin Foundation would add them:")
    L.append("")
    L.append("* Measurement formatting of all units (`Measurement.FormatStyle`, a stub in swift-foundation), so all unit names beyond digital and duration units.")
    L.append("* `Date.ComponentsFormatStyle` (a stub in swift-foundation).")
    L.append("* Text transforms (`applyingTransform`), text segmentation by words or sentences, morphology and inflection, person name formatting, number spell-out.")
    L.append("* Ordinal plural rules and plural ranges (not used in swift-foundation).")
    L.append("")
    L.append("## Open questions")
    L.append("")
    L.append("1. The data of the 10 calendars that public CLDR does not have (Bangla to Vietnamese): where does it come from?")
    L.append("2. The date patterns: this catalog keeps the CLDR model that Foundation uses today (styles, skeletons, the pattern generator), so that the output stays the same. ICU4X uses another model (semantic skeletons). Is that the right choice?")
    L.append("3. Kinds for each calendar: should non-Gregorian calendars store only their differences from a shared \"generic\" calendar, to save data? This catalog stores complete data, as ICU4X does.")
    L.append("4. Unicode data (bidi class, scripts, blocks, IDNA, case rules): should it be in this catalog, or does the Swift standard library provide it?")
    L.append("5. Collation: is one root kind and one tailoring kind enough, or should the root be split as in ICU4X (4 kinds)?")
    L.append("")
    open(os.path.join(ROOT, "MARKER-CATALOG.md"), "w", encoding="utf-8").write("\n".join(L) + "\n")


def main():
    entries = expand()
    registry = {"status": "draft design, 2026-10-26", "source": "swift-foundation 662eac61", "namingRule": "<Feature><Data><Item>[<Calendar>]V<version>",
                "words": {"features": FEATURES, "data": DATA, "items": ITEMS}, "calendars": [{"dataCalendar": c[0], "foundationIdentifiers": c[1], "dataName": c[2], "source": c[3]} for c in CALENDARS],
                "settings": {k: {"description": v[0], "needs": v[1]} for k, v in SETTINGS.items()}, "kinds": entries}
    json.dump(registry, open(os.path.join(HERE, "data-kinds.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    write_doc(entries)
    print(f"{len(KINDS)} kinds, {len(entries)} registry entries. Wrote docs/catalog/data-kinds.json and docs/MARKER-CATALOG.md")


if __name__ == "__main__":
    main()
