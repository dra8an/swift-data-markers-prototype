// ICU4X size app: the same as gregorian_ymd, but the locale is the constant fr. A test: does a constant locale cut the data?
use icu_calendar::cal::Gregorian;
use icu_datetime::fieldsets::YMD;
use icu_datetime::input::{Date, DateTime, Time};
use icu_datetime::FixedCalendarDateTimeFormatter;
use icu_locale_core::Locale;
use std::io::Write;
use writeable::Writeable;

fn main() {
    let locale: Locale = icu_locale_core::locale!("fr");
    let f = FixedCalendarDateTimeFormatter::<Gregorian, _>::try_new(locale.into(), YMD::medium()).unwrap();
    let dt = DateTime { date: Date::try_new_iso(2026, 10, 23).unwrap().to_calendar(Gregorian), time: Time::try_new(13, 5, 9, 0).unwrap() };
    let mut s = f.format(&dt).write_to_string().into_owned();
    s.push('\n');
    std::io::stdout().write_all(s.as_bytes()).unwrap();
}
