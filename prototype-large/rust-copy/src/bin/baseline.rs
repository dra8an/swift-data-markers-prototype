// The baseline for code sizes: the same input and output as the size apps, with no formatter.
use std::io::Write;

fn main() {
    let mut locale = std::env::var("LOCALE").unwrap_or("ja".into()).into_bytes();
    locale.push(b'\n');
    std::io::stdout().write_all(&locale).unwrap();
}
