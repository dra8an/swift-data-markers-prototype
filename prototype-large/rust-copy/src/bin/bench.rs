// The speed test of the Rust copy: the same tests as swift/apps/Bench/main.swift.
use rust_copy::data_markers::TextOutput;
use rust_copy::format::*;
use std::time::Instant;

const LOCALES: [&str; 10] = ["en", "ja", "de", "ar-EG", "he", "zh", "fr", "hi", "ko", "pt-AO"];
const fn dt(year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64) -> DateTime {
    DateTime { year, month, day, hour, minute, second }
}
const CASES: [DateTime; 12] = [
    dt(2026, 10, 23, 13, 5, 9), dt(2000, 2, 29, 0, 0, 0), dt(1989, 1, 7, 12, 0, 0), dt(1989, 1, 8, 23, 59, 0),
    dt(2019, 4, 30, 9, 30, 0), dt(2019, 5, 1, 9, 30, 0), dt(1950, 6, 15, 18, 45, 0), dt(2023, 4, 15, 6, 7, 0),
    dt(2025, 8, 1, 20, 20, 0), dt(2024, 3, 15, 11, 11, 0), dt(1900, 1, 31, 12, 0, 0), dt(2100, 12, 31, 0, 0, 0),
];

fn report(name: &str, mut runs: Vec<u128>, operations: u128) {
    runs.sort();
    println!("{}\t{}", name, runs[runs.len() / 2] * 10 / operations);
}

fn bench_new<C: BakedCalendar, FS: BakedFieldSet>(name: &str, length: Length, repeats: usize, sink: &mut usize) {
    let mut runs = Vec::new();
    for _ in 0..5 {
        let start = Instant::now();
        for _ in 0..repeats {
            for l in LOCALES {
                if FixedCalendarFormatter::<C, FS>::new(std::hint::black_box(l), length).is_some() {
                    *sink += 1;
                }
            }
        }
        runs.push(start.elapsed().as_nanos());
    }
    report(name, runs, (repeats * LOCALES.len()) as u128);
}

fn bench_format<C: BakedCalendar, FS: BakedFieldSet>(name: &str, locale: &str, length: Length, repeats: usize, sink: &mut usize) {
    let Some(f) = FixedCalendarFormatter::<C, FS>::new(locale, length) else {
        println!("{}\tno formatter", name);
        return;
    };
    let mut runs = Vec::new();
    for _ in 0..5 {
        let start = Instant::now();
        for _ in 0..repeats {
            for c in std::hint::black_box(&CASES) {
                let mut out = TextOutput::new();
                if f.format_into(c, &mut out) {
                    *sink += out.bytes.len();
                }
            }
        }
        runs.push(start.elapsed().as_nanos());
    }
    report(name, runs, (repeats * CASES.len()) as u128);
}

fn main() {
    let mut sink = 0;
    bench_new::<Gregorian, YMD>("new Gregorian YMD medium", Length::Medium, 2000, &mut sink);
    bench_new::<Japanese, YMDT>("new Japanese YMDT long", Length::Long, 2000, &mut sink);
    bench_format::<Gregorian, YMD>("format Gregorian YMD medium en", "en", Length::Medium, 20000, &mut sink);
    bench_format::<Gregorian, YMDT>("format Gregorian YMDT medium en", "en", Length::Medium, 20000, &mut sink);
    bench_format::<Japanese, YMDT>("format Japanese YMDT long ja", "ja", Length::Long, 20000, &mut sink);
    bench_format::<Hebrew, YMD>("format Hebrew YMD long he", "he", Length::Long, 20000, &mut sink);
    bench_format::<Chinese, YMD>("format Chinese YMD long zh", "zh", Length::Long, 20000, &mut sink);
    bench_format::<Gregorian, YMD>("format Gregorian YMD long ar-EG", "ar-EG", Length::Long, 20000, &mut sink);
    println!("sink\t{}", sink);
}
