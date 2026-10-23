// Dumps the Chinese years whose related ISO year is 1900 to 2100 (DESIGN.md, decision 6).
// Output, one line for each year: related ISO year, rata die of the new year, ordinal of the leap month (0 if none), the length of each month, the cyclic year.
use icu_calendar::cal::ChineseTraditional;
use icu_calendar::Date;
use std::collections::BTreeMap;

fn main() {
    let mut years: BTreeMap<i32, (i64, u8, Vec<(u8, u8)>, u8)> = BTreeMap::new();
    let start = Date::try_new_iso(1899, 12, 1).unwrap().to_rata_die();
    let end = Date::try_new_iso(2102, 3, 1).unwrap().to_rata_die();
    let mut rd = start;
    let mut last: Option<(i32, u8)> = None;
    while rd < end {
        let date = Date::from_rata_die(rd, ChineseTraditional::new());
        let cyclic = date.year().cyclic().unwrap();
        let month = date.month();
        let key = (cyclic.related_iso, month.ordinal);
        if last != Some(key) {
            let entry = years.entry(cyclic.related_iso).or_insert((rd.to_i64_date(), 0, Vec::new(), cyclic.year));
            if month.ordinal == 1 {
                entry.0 = rd.to_i64_date();
            }
            if month.is_leap() {
                entry.1 = month.ordinal;
            }
            entry.2.push((month.ordinal, 0));
            last = Some(key);
        }
        let entry = years.get_mut(&cyclic.related_iso).unwrap();
        entry.2.last_mut().unwrap().1 += 1;
        rd = rd + 1;
    }
    for (y, (new_year, leap, months, cyclic)) in years {
        if !(1900..=2100).contains(&y) {
            continue;
        }
        let lengths: Vec<String> = months.iter().map(|(_, n)| n.to_string()).collect();
        println!("{} {} {} {} {}", y, new_year, leap, lengths.join(","), cyclic);
    }
}
