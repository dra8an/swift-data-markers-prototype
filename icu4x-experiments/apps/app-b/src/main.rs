// App B: the same output as app A, but the month names come from data that icu4x-datagen generated for one marker, one locale and one width.
use icu_calendar::cal::Japanese;
use icu_datetime::input::{Date, DateTime, Time};
use icu_datetime::pattern::{DateTimePattern, FixedCalendarDateTimeNames, MonthNameLength};
use icu_locale_core::Locale;
use writeable::TryWriteable;

struct MyProvider;
include!(env!("APP_B_DATA"));
impl_data_provider!(MyProvider);

fn main() {
    let date = Date::try_new_iso(2026, 9, 18).unwrap().to_calendar(Japanese::new());
    let datetime = DateTime { date, time: Time::try_new(12, 0, 0, 0).unwrap() };
    let pattern: DateTimePattern = "MMMM".parse().unwrap();
    let mut names = FixedCalendarDateTimeNames::<Japanese>::new_without_number_formatting(std::env::var("LOCALE").unwrap_or("ko".into()).parse::<Locale>().unwrap().into());
    names.load_month_names(&MyProvider, MonthNameLength::Wide).unwrap();
    let text = names.with_pattern_unchecked(&pattern).format(&datetime).try_write_to_string().unwrap().into_owned();
    println!("{text}");
}
