// The reference for the correctness test (DESIGN.md, decision 7).
// Formats every date of the cases file for every locale, calendar, field set and length with ICU4X and its built-in data.
// usage: reference <locales file> <dates file> > out.tsv
// Output: locale, calendar, field set, length, date, text. Separated by tabs.
use icu_calendar::cal::hijri::{TabularAlgorithmEpoch, TabularAlgorithmLeapYears};
use icu_calendar::cal::{Buddhist, ChineseTraditional, Gregorian, Hebrew, Hijri, Japanese};
use icu_datetime::fieldsets::{T, YMD, YMDE};
use icu_datetime::input::{Date, DateTime, Time};
use icu_datetime::options::TimePrecision;
use icu_datetime::{FixedCalendarDateTimeFormatter, NoCalendarFormatter};
use icu_locale_core::Locale;
use std::io::Write;

struct Case {
    text: String,
    y: i32,
    m: u8,
    d: u8,
    h: u8,
    min: u8,
    s: u8,
}

fn read_lines(path: &str) -> Vec<String> {
    std::fs::read_to_string(path).unwrap().lines().map(|l| l.trim().to_string()).filter(|l| !l.is_empty() && !l.starts_with('#')).collect()
}

fn read_cases(path: &str) -> Vec<Case> {
    read_lines(path)
        .iter()
        .map(|l| {
            let v: Vec<i32> = l.split_whitespace().map(|x| x.parse().unwrap()).collect();
            Case { text: format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}", v[0], v[1], v[2], v[3], v[4], v[5]), y: v[0], m: v[1] as u8, d: v[2] as u8, h: v[3] as u8, min: v[4] as u8, s: v[5] as u8 }
        })
        .collect()
}

const LENGTHS: [&str; 3] = ["long", "medium", "short"];

macro_rules! run_calendar {
    ($out:expr, $locales:expr, $cases:expr, $C:ty, $calendar:expr, $name:expr) => {
        for locale in $locales {
            let prefs = locale.parse::<Locale>().unwrap().into();
            let ymd = [
                FixedCalendarDateTimeFormatter::<$C, _>::try_new(prefs, YMD::long()).unwrap(),
                FixedCalendarDateTimeFormatter::<$C, _>::try_new(prefs, YMD::medium()).unwrap(),
                FixedCalendarDateTimeFormatter::<$C, _>::try_new(prefs, YMD::short()).unwrap(),
            ];
            let ymde = [
                FixedCalendarDateTimeFormatter::<$C, _>::try_new(prefs, YMDE::long()).unwrap(),
                FixedCalendarDateTimeFormatter::<$C, _>::try_new(prefs, YMDE::medium()).unwrap(),
                FixedCalendarDateTimeFormatter::<$C, _>::try_new(prefs, YMDE::short()).unwrap(),
            ];
            let ymdt = [
                FixedCalendarDateTimeFormatter::<$C, _>::try_new(prefs, YMD::long().with_time_hm()).unwrap(),
                FixedCalendarDateTimeFormatter::<$C, _>::try_new(prefs, YMD::medium().with_time_hm()).unwrap(),
                FixedCalendarDateTimeFormatter::<$C, _>::try_new(prefs, YMD::short().with_time_hm()).unwrap(),
            ];
            for case in $cases {
                let date = Date::try_new_iso(case.y, case.m, case.d).unwrap().to_calendar($calendar);
                let datetime = DateTime { date, time: Time::try_new(case.h, case.min, case.s, 0).unwrap() };
                for i in 0..3 {
                    writeln!($out, "{}\t{}\tYMD\t{}\t{}\t{}", locale, $name, LENGTHS[i], case.text, ymd[i].format(&datetime)).unwrap();
                    writeln!($out, "{}\t{}\tYMDE\t{}\t{}\t{}", locale, $name, LENGTHS[i], case.text, ymde[i].format(&datetime)).unwrap();
                    writeln!($out, "{}\t{}\tYMDT\t{}\t{}\t{}", locale, $name, LENGTHS[i], case.text, ymdt[i].format(&datetime)).unwrap();
                }
            }
        }
    };
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let locales = read_lines(&args[1]);
    let cases = read_cases(&args[2]);
    let stdout = std::io::stdout();
    let mut out = std::io::BufWriter::new(stdout.lock());

    // Time only: no calendar.
    for locale in &locales {
        let prefs = locale.parse::<Locale>().unwrap().into();
        let t = [
            NoCalendarFormatter::try_new(prefs, T::long().with_time_precision(TimePrecision::Minute)).unwrap(),
            NoCalendarFormatter::try_new(prefs, T::medium().with_time_precision(TimePrecision::Minute)).unwrap(),
            NoCalendarFormatter::try_new(prefs, T::short().with_time_precision(TimePrecision::Minute)).unwrap(),
        ];
        for case in &cases {
            let time = Time::try_new(case.h, case.min, case.s, 0).unwrap();
            for i in 0..3 {
                writeln!(out, "{}\t-\tT\t{}\t{}\t{}", locale, LENGTHS[i], case.text, t[i].format(&time)).unwrap();
            }
        }
    }

    run_calendar!(out, &locales, &cases, Gregorian, Gregorian, "gregorian");
    run_calendar!(out, &locales, &cases, Buddhist, Buddhist, "buddhist");
    run_calendar!(out, &locales, &cases, Japanese, Japanese::new(), "japanese");
    run_calendar!(out, &locales, &cases, Hebrew, Hebrew, "hebrew");
    run_calendar!(out, &locales, &cases, ChineseTraditional, ChineseTraditional::new(), "chinese");
    run_calendar!(out, &locales, &cases, Hijri<icu_calendar::cal::hijri::TabularAlgorithm>, Hijri::new_tabular(TabularAlgorithmLeapYears::TypeII, TabularAlgorithmEpoch::Friday), "hijri");
}
