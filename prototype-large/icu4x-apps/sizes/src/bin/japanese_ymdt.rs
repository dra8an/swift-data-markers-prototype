// ICU4X size app: Japanese, YMD with T, long. The locale comes from the environment at run time.
use icu_calendar::cal::Japanese;
use icu_datetime::fieldsets::YMD;
use icu_datetime::input::{Date, DateTime, Time};
use icu_datetime::FixedCalendarDateTimeFormatter;
use icu_locale_core::Locale;
use std::io::Write;
use writeable::Writeable;

fn main() {
    let locale: Locale = std::env::var("LOCALE").unwrap_or("ja".into()).parse().unwrap();
    let f = FixedCalendarDateTimeFormatter::<Japanese, _>::try_new(locale.into(), YMD::long().with_time_hm()).unwrap();
    let dt = DateTime { date: Date::try_new_iso(2026, 10, 23).unwrap().to_calendar(Japanese::new()), time: Time::try_new(13, 5, 9, 0).unwrap() };
    let mut s = f.format(&dt).write_to_string().into_owned();
    s.push('\n');
    std::io::stdout().write_all(s.as_bytes()).unwrap();
}
