// The correctness test of the Rust copy: the same output as icu4x-apps/reference and the Swift Check app.
// usage: LOCALES=<locales file> DATES=<dates file> check > out.tsv
use rust_copy::data_markers::TextOutput;
use rust_copy::format::*;
use std::io::Write;

struct Case {
    text: String,
    dt: DateTime,
}

fn read_lines(path: &str) -> Vec<String> {
    std::fs::read_to_string(path).unwrap().lines().map(|l| l.trim().to_string()).filter(|l| !l.is_empty() && !l.starts_with('#')).collect()
}

const LENGTHS: [Length; 3] = [Length::Long, Length::Medium, Length::Short];
const NAMES: [&str; 3] = ["long", "medium", "short"];

fn text(f: Option<&TextOutput>, ok: bool) -> String {
    match f {
        None => "<no formatter>".into(),
        Some(_) if !ok => "<out of range>".into(),
        Some(o) => String::from_utf8(o.bytes.clone()).unwrap(),
    }
}

fn run<C: BakedCalendar, FS: BakedFieldSet>(locale: &str, cases: &[Case]) -> Vec<[String; 3]> {
    let fs: Vec<Option<FixedCalendarFormatter<C, FS>>> = LENGTHS.iter().map(|&l| FixedCalendarFormatter::new(locale, l)).collect();
    cases.iter().map(|c| {
        let mut r: [String; 3] = Default::default();
        for i in 0..3 {
            let mut out = TextOutput::new();
            let ok = fs[i].as_ref().map(|f| f.format_into(&c.dt, &mut out)).unwrap_or(false);
            r[i] = text(fs[i].as_ref().map(|_| &out), ok);
        }
        r
    }).collect()
}

fn run_calendar<C: BakedCalendar>(name: &str, locales: &[String], cases: &[Case], out: &mut impl Write) {
    for locale in locales {
        let ymd = run::<C, YMD>(locale, cases);
        let ymde = run::<C, YMDE>(locale, cases);
        let ymdt = run::<C, YMDT>(locale, cases);
        for (n, c) in cases.iter().enumerate() {
            for i in 0..3 {
                writeln!(out, "{}\t{}\tYMD\t{}\t{}\t{}", locale, name, NAMES[i], c.text, ymd[n][i]).unwrap();
                writeln!(out, "{}\t{}\tYMDE\t{}\t{}\t{}", locale, name, NAMES[i], c.text, ymde[n][i]).unwrap();
                writeln!(out, "{}\t{}\tYMDT\t{}\t{}\t{}", locale, name, NAMES[i], c.text, ymdt[n][i]).unwrap();
            }
        }
    }
}

fn main() {
    let locales = read_lines(&std::env::var("LOCALES").unwrap());
    let cases: Vec<Case> = read_lines(&std::env::var("DATES").unwrap()).iter().map(|l| {
        let v: Vec<i64> = l.split_whitespace().map(|x| x.parse().unwrap()).collect();
        Case { text: format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}", v[0], v[1], v[2], v[3], v[4], v[5]), dt: DateTime { year: v[0], month: v[1], day: v[2], hour: v[3], minute: v[4], second: v[5] } }
    }).collect();
    let stdout = std::io::stdout();
    let mut out = std::io::BufWriter::new(stdout.lock());
    for locale in &locales {
        let t: Vec<[String; 3]> = run::<NoCalendar, T>(locale, &cases);
        for (n, c) in cases.iter().enumerate() {
            for i in 0..3 {
                writeln!(out, "{}\t-\tT\t{}\t{}\t{}", locale, NAMES[i], c.text, t[n][i]).unwrap();
            }
        }
    }
    run_calendar::<Gregorian>("gregorian", &locales, &cases, &mut out);
    run_calendar::<Buddhist>("buddhist", &locales, &cases, &mut out);
    run_calendar::<Japanese>("japanese", &locales, &cases, &mut out);
    run_calendar::<Hebrew>("hebrew", &locales, &cases, &mut out);
    run_calendar::<Chinese>("chinese", &locales, &cases, &mut out);
    run_calendar::<Hijri>("hijri", &locales, &cases, &mut out);
}
