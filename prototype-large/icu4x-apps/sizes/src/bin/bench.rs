// The speed test of ICU4X with its built-in data: the same tests as swift/apps/Bench/main.swift.
// The timed loops include the parse of the locale (new) and the conversion from ISO to the calendar (format), as in the Swift code.
use icu_calendar::cal::{ChineseTraditional, Gregorian, Hebrew, Japanese};
use icu_datetime::fieldsets::{YMD, YMDT};
use icu_datetime::input::{Date, DateTime, Time};
use icu_datetime::FixedCalendarDateTimeFormatter;
use icu_locale_core::Locale;
use std::time::Instant;
use writeable::Writeable;

const LOCALES: [&str; 10] = ["en", "ja", "de", "ar-EG", "he", "zh", "fr", "hi", "ko", "pt-AO"];
const CASES: [(i32, u8, u8, u8, u8, u8); 12] = [
    (2026, 10, 23, 13, 5, 9), (2000, 2, 29, 0, 0, 0), (1989, 1, 7, 12, 0, 0), (1989, 1, 8, 23, 59, 0),
    (2019, 4, 30, 9, 30, 0), (2019, 5, 1, 9, 30, 0), (1950, 6, 15, 18, 45, 0), (2023, 4, 15, 6, 7, 0),
    (2025, 8, 1, 20, 20, 0), (2024, 3, 15, 11, 11, 0), (1900, 1, 31, 12, 0, 0), (2100, 12, 31, 0, 0, 0),
];

fn report(name: &str, mut runs: Vec<u128>, operations: u128) {
    runs.sort();
    println!("{}\t{}", name, runs[runs.len() / 2] * 10 / operations);
}

macro_rules! bench_new {
    ($name:expr, $C:ty, $fs:expr, $sink:expr) => {{
        let mut runs = Vec::new();
        for _ in 0..5 {
            let start = Instant::now();
            for _ in 0..2000 {
                for l in LOCALES {
                    let locale: Locale = std::hint::black_box(l).parse().unwrap();
                    if FixedCalendarDateTimeFormatter::<$C, _>::try_new(locale.into(), $fs).is_ok() {
                        $sink += 1;
                    }
                }
            }
            runs.push(start.elapsed().as_nanos());
        }
        report($name, runs, (2000 * LOCALES.len()) as u128);
    }};
}

macro_rules! bench_format {
    ($name:expr, $C:ty, $calendar:expr, $fs:expr, $locale:expr, $sink:expr) => {{
        let locale: Locale = $locale.parse().unwrap();
        let f = FixedCalendarDateTimeFormatter::<$C, _>::try_new(locale.into(), $fs).unwrap();
        let calendar = $calendar;
        let mut runs = Vec::new();
        for _ in 0..5 {
            let start = Instant::now();
            for _ in 0..20000 {
                for &(y, m, d, h, min, s) in std::hint::black_box(&CASES) {
                    let date = Date::try_new_iso(y, m, d).unwrap().to_calendar(calendar.clone());
                    let datetime = DateTime { date, time: Time::try_new(h, min, s, 0).unwrap() };
                    let text = f.format(&datetime).write_to_string().into_owned();
                    $sink += text.len();
                }
            }
            runs.push(start.elapsed().as_nanos());
        }
        report($name, runs, (20000 * CASES.len()) as u128);
    }};
}

fn main() {
    let mut sink = 0usize;
    bench_new!("new Gregorian YMD medium", Gregorian, YMD::medium(), sink);
    bench_new!("new Japanese YMDT long", Japanese, YMD::long().with_time_hm(), sink);
    bench_format!("format Gregorian YMD medium en", Gregorian, Gregorian, YMD::medium(), "en", sink);
    bench_format!("format Gregorian YMDT medium en", Gregorian, Gregorian, YMD::medium().with_time_hm(), "en", sink);
    bench_format!("format Japanese YMDT long ja", Japanese, Japanese::new(), YMD::long().with_time_hm(), "ja", sink);
    bench_format!("format Hebrew YMD long he", Hebrew, Hebrew, YMD::long(), "he", sink);
    bench_format!("format Chinese YMD long zh", ChineseTraditional, ChineseTraditional::new(), YMD::long(), "zh", sink);
    bench_format!("format Gregorian YMD long ar-EG", Gregorian, Gregorian, YMD::long(), "ar-EG", sink);
    println!("sink\t{}", sink);
}
