// App A: wide Korean month names of the Japanese calendar, from the built-in data of icu_datetime.
use icu_calendar::cal::Japanese;
use icu_datetime::input::{Date, DateTime, Time};
use icu_datetime::pattern::{DateTimePattern, FixedCalendarDateTimeNames, MonthNameLength};
use icu_locale_core::locale;
use writeable::TryWriteable;

fn main() {
    let date = Date::try_new_iso(2026, 9, 18).unwrap().to_calendar(Japanese::new());
    let datetime = DateTime { date, time: Time::try_new(12, 0, 0, 0).unwrap() };
    let pattern: DateTimePattern = "MMMM".parse().unwrap();
    let mut names = FixedCalendarDateTimeNames::<Japanese>::try_new(locale!("ko").into()).unwrap();
    names.include_month_names(MonthNameLength::Wide).unwrap();
    let text = names.with_pattern_unchecked(&pattern).format(&datetime).try_write_to_string().unwrap().into_owned();
    println!("{text}");
}
