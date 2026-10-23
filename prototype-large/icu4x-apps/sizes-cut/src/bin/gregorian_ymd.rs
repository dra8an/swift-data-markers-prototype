// ICU4X size app with cut data: the same as icu4x-apps/sizes, but the data comes from icu4x-datagen through its own provider (ICU4X_CUT_DATA).
use icu_calendar::cal::Gregorian;
use icu_datetime::FixedCalendarDateTimeFormatter;
use icu_datetime::fieldsets::YMD;
use icu_datetime::input::{Date, DateTime, Time};
use icu_locale_core::Locale;
use std::io::Write;
use writeable::Writeable;

struct MyProvider;
include!(env!("ICU4X_CUT_DATA"));
impl_data_provider!(MyProvider);

fn main() {
    let locale: Locale = std::env::var("LOCALE").unwrap_or("ja".into()).parse().unwrap();
    let f = FixedCalendarDateTimeFormatter::<Gregorian, _>::try_new_unstable(&MyProvider, locale.into(), YMD::medium()).unwrap();
    let dt = DateTime { date: Date::try_new_iso(2026, 10, 23).unwrap().to_calendar(Gregorian), time: Time::try_new(13, 5, 9, 0).unwrap() };
    let mut s = f.format(&dt).write_to_string().into_owned();
    s.push('\n');
    std::io::stdout().write_all(s.as_bytes()).unwrap();
}
