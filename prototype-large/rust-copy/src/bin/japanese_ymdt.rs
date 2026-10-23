// A size app of the Rust copy (DESIGN.md, decision 8), the same as swift/apps. The locale comes from the environment at run time.
use rust_copy::data_markers::TextOutput;
use rust_copy::format::*;
use std::io::Write;

fn main() {
    let locale = std::env::var("LOCALE").unwrap_or("ja".into());
    let mut out = TextOutput::new();
    let dt = DateTime { year: 2026, month: 10, day: 23, hour: 13, minute: 5, second: 9 };
    match FixedCalendarFormatter::<Japanese, YMDT>::new(&locale, Length::Long) {
        Some(f) if f.format_into(&dt, &mut out) => out.push(b'\n'),
        _ => out.append_str("no data\n"),
    }
    std::io::stdout().write_all(&out.bytes).unwrap();
}
