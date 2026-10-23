// The formatter of the Rust copy: the same design as swift/Sources/DateTimeFormat, line for line where Rust allows it.
use crate::chinese_years as cy;
use crate::data_markers::*;
use core::marker::PhantomData;

// MARK: - Markers (Markers.swift)

macro_rules! markers {
    ($($name:ident),*) => { $( pub enum $name {} impl DataMarker for $name { const NAME: &'static str = stringify!($name); } )* };
}
markers!(
    DatetimeNamesMonthGregorianV1, DatetimeNamesMonthBuddhistV1, DatetimeNamesMonthJapaneseV1, DatetimeNamesMonthHebrewV1, DatetimeNamesMonthChineseV1, DatetimeNamesMonthHijriV1,
    DatetimeNamesYearGregorianV1, DatetimeNamesYearBuddhistV1, DatetimeNamesYearJapaneseV1, DatetimeNamesYearHebrewV1, DatetimeNamesYearChineseV1, DatetimeNamesYearHijriV1,
    DatetimeNamesWeekdayV1, DatetimeNamesDayperiodV1,
    DatetimePatternsDateGregorianV1, DatetimePatternsDateBuddhistV1, DatetimePatternsDateJapaneseV1, DatetimePatternsDateHebrewV1, DatetimePatternsDateChineseV1, DatetimePatternsDateHijriV1,
    DatetimePatternsTimeV1, DatetimePatternsGlueV1, CalendarJapaneseModernV1, DecimalSymbolsV1, DecimalDigitsV1
);

// MARK: - Calendars (Calendars.swift)

#[derive(Clone, Copy, PartialEq)]
pub enum YearAmbiguity {
    Unambiguous,
    CenturyRequired,
    EraRequired,
    EraAndCenturyRequired,
}

#[derive(Clone, Copy, PartialEq)]
pub enum LeapStatus {
    Normal,
    Leap,
    Base,
}

/// An era code as bytes.
#[derive(Clone, Copy)]
pub struct EraCode {
    pub bytes: [u8; 16],
    pub count: usize,
}

impl EraCode {
    #[inline]
    pub fn new(text: &str) -> Self {
        let mut c = EraCode { bytes: [0; 16], count: text.len() };
        c.bytes[..text.len()].copy_from_slice(text.as_bytes());
        c
    }
    #[inline]
    pub fn from_pool(r: TextRef, pool: &[u8]) -> Self {
        let mut c = EraCode { bytes: [0; 16], count: text_count(r) };
        c.bytes[..c.count].copy_from_slice(&pool[text_offset(r)..text_offset(r) + c.count]);
        c
    }
    #[inline]
    fn compare(&self, r: TextRef, pool: &[u8]) -> core::cmp::Ordering {
        pool[text_offset(r)..text_offset(r) + text_count(r)].cmp(&self.bytes[..self.count])
    }
}

#[derive(Clone, Copy)]
pub struct CalendarFields {
    pub era_year: i64,
    pub has_era: bool,
    pub era_index: i64,
    pub era_code: EraCode,
    pub ambiguity: YearAmbiguity,
    pub cyclic: i64,
    pub related_iso: i64,
    pub month_number: i64,
    pub month_ordinal: i64,
    pub leap_status: LeapStatus,
    pub day: i64,
}

impl CalendarFields {
    #[inline]
    fn simple(era_year: i64, era_index: i64, era_code: &str, ambiguity: YearAmbiguity, month: i64, day: i64) -> Self {
        CalendarFields { era_year, has_era: true, era_index, era_code: EraCode::new(era_code), ambiguity, cyclic: 0, related_iso: 0, month_number: month, month_ordinal: month, leap_status: LeapStatus::Normal, day }
    }
}

pub trait CalendarSystem {
    type MonthNames: DataMarker;
    type YearNames: DataMarker;
    type DatePatterns: DataMarker;
    type EraData: DataMarker;
    fn fields<E: BakedDataMarker>(rata_die: i64, eras: Option<DataValue>) -> Option<CalendarFields>;
}

/// A calendar whose markers all have built-in data. The generated data.rs implements it.
pub trait BakedCalendar: CalendarSystem<MonthNames: BakedDataMarker, YearNames: BakedDataMarker, DatePatterns: BakedDataMarker, EraData: BakedDataMarker> {}

#[inline]
fn floor_div(a: i64, b: i64) -> i64 {
    a.div_euclid(b)
}
#[inline]
fn floor_mod(a: i64, b: i64) -> i64 {
    a.rem_euclid(b)
}
#[inline]
fn is_gregorian_leap(y: i64) -> bool {
    floor_mod(y, 4) == 0 && (floor_mod(y, 100) != 0 || floor_mod(y, 400) == 0)
}

#[inline]
pub fn rata_die(y: i64, m: i64, d: i64) -> i64 {
    let y1 = y - 1;
    let mut f = 365 * y1 + floor_div(y1, 4) - floor_div(y1, 100) + floor_div(y1, 400) + floor_div(367 * m - 362, 12) + d;
    if m > 2 {
        f -= if is_gregorian_leap(y) { 1 } else { 2 };
    }
    f
}

#[inline]
fn iso_from_rata_die(f: i64) -> (i64, i64, i64) {
    let d0 = f - 1;
    let n400 = floor_div(d0, 146_097);
    let d1 = floor_mod(d0, 146_097);
    let n100 = d1 / 36524;
    let d2 = d1 % 36524;
    let n4 = d2 / 1461;
    let d3 = d2 % 1461;
    let n1 = d3 / 365;
    let mut year = 400 * n400 + 100 * n100 + 4 * n4 + n1;
    if !(n100 == 4 || n1 == 4) {
        year += 1;
    }
    let prior_days = f - rata_die(year, 1, 1);
    let correction = if f < rata_die(year, 3, 1) { 0 } else if is_gregorian_leap(year) { 1 } else { 2 };
    let month = (12 * (prior_days + correction) + 373) / 367;
    (year, month, f - rata_die(year, month, 1) + 1)
}

#[inline]
fn ce_bce(year: i64, month: i64, day: i64) -> CalendarFields {
    if year > 0 {
        let a = if year <= 999 { YearAmbiguity::EraAndCenturyRequired } else if year <= 1949 { YearAmbiguity::CenturyRequired } else if year <= 2049 { YearAmbiguity::Unambiguous } else { YearAmbiguity::CenturyRequired };
        CalendarFields::simple(year, 1, "ce", a, month, day)
    } else {
        CalendarFields::simple(1 - year, 0, "bce", YearAmbiguity::EraAndCenturyRequired, month, day)
    }
}

pub enum Gregorian {}
impl CalendarSystem for Gregorian {
    type MonthNames = DatetimeNamesMonthGregorianV1;
    type YearNames = DatetimeNamesYearGregorianV1;
    type DatePatterns = DatetimePatternsDateGregorianV1;
    type EraData = NeverMarker;
    #[inline]
    fn fields<E: BakedDataMarker>(rd: i64, _: Option<DataValue>) -> Option<CalendarFields> {
        let (y, m, d) = iso_from_rata_die(rd);
        Some(ce_bce(y, m, d))
    }
}

pub enum Buddhist {}
impl CalendarSystem for Buddhist {
    type MonthNames = DatetimeNamesMonthBuddhistV1;
    type YearNames = DatetimeNamesYearBuddhistV1;
    type DatePatterns = DatetimePatternsDateBuddhistV1;
    type EraData = NeverMarker;
    #[inline]
    fn fields<E: BakedDataMarker>(rd: i64, _: Option<DataValue>) -> Option<CalendarFields> {
        let (y, m, d) = iso_from_rata_die(rd);
        Some(CalendarFields::simple(y + 543, 0, "be", YearAmbiguity::CenturyRequired, m, d))
    }
}

pub enum Japanese {}
impl CalendarSystem for Japanese {
    type MonthNames = DatetimeNamesMonthJapaneseV1;
    type YearNames = DatetimeNamesYearJapaneseV1;
    type DatePatterns = DatetimePatternsDateJapaneseV1;
    type EraData = CalendarJapaneseModernV1;
    #[inline]
    fn fields<E: BakedDataMarker>(rd: i64, eras: Option<DataValue>) -> Option<CalendarFields> {
        let (y, m, d) = iso_from_rata_die(rd);
        let eras = eras?;
        let t = E::TABLES;
        let count = t.words[eras.start] as i64;
        let mut i = count - 1;
        while i >= 0 {
            let at = eras.start + 1 + 4 * i as usize;
            let sy = t.words[at] as i32 as i64;
            let sm = t.words[at + 1] as i64;
            let sd = t.words[at + 2] as i64;
            if (y, m, d) >= (sy, sm, sd) {
                let era_year = y - sy + 1;
                if i == 0 && era_year < 6 {
                    return Some(ce_bce(y, m, d));
                }
                return Some(CalendarFields { era_year, has_era: true, era_index: i + 2, era_code: EraCode::from_pool(t.words[at + 3], t.pool), ambiguity: YearAmbiguity::CenturyRequired, cyclic: 0, related_iso: 0, month_number: m, month_ordinal: m, leap_status: LeapStatus::Normal, day: d });
            }
            i -= 1;
        }
        Some(ce_bce(y, m, d))
    }
}

pub enum Hebrew {}
const HEBREW_EPOCH: i64 = -1_373_427;
#[inline]
fn hebrew_is_leap(y: i64) -> bool {
    floor_mod(7 * y + 1, 19) < 7
}
#[inline]
fn hebrew_elapsed_days(y: i64) -> i64 {
    let months_elapsed = floor_div(235 * y - 234, 19);
    let parts_elapsed = 12084 + 13753 * months_elapsed;
    let day = 29 * months_elapsed + floor_div(parts_elapsed, 25920);
    if floor_mod(3 * (day + 1), 7) < 3 { day + 1 } else { day }
}
#[inline]
fn hebrew_new_year_delay(y: i64) -> i64 {
    let (ny0, ny1, ny2) = (hebrew_elapsed_days(y - 1), hebrew_elapsed_days(y), hebrew_elapsed_days(y + 1));
    if ny2 - ny1 == 356 { 2 } else if ny1 - ny0 == 382 { 1 } else { 0 }
}
#[inline]
fn hebrew_new_year(y: i64) -> i64 {
    HEBREW_EPOCH + hebrew_elapsed_days(y) + hebrew_new_year_delay(y)
}
#[inline]
fn hebrew_month_length(m: i64, leap: bool, days: i64) -> i64 {
    if m == 2 || m == 4 || m == 6 || m == 10 || m == 13 { return 29; }
    if m == 12 && !leap { return 29; }
    if m == 8 && !(days == 355 || days == 385) { return 29; }
    if m == 9 && (days == 353 || days == 383) { return 29; }
    30
}
impl CalendarSystem for Hebrew {
    type MonthNames = DatetimeNamesMonthHebrewV1;
    type YearNames = DatetimeNamesYearHebrewV1;
    type DatePatterns = DatetimePatternsDateHebrewV1;
    type EraData = NeverMarker;
    #[inline]
    fn fields<E: BakedDataMarker>(rd: i64, _: Option<DataValue>) -> Option<CalendarFields> {
        let approx = floor_div(98496 * (rd - HEBREW_EPOCH), 35_975_351) + 1;
        let (mut year, mut start) = (approx, hebrew_new_year(approx));
        if start > rd {
            year = approx - 1;
            start = hebrew_new_year(year);
        }
        let days = hebrew_new_year(year + 1) - start;
        let leap = hebrew_is_leap(year);
        let mut remaining = rd - start;
        let (mut ordinal, mut month) = (1i64, 7i64);
        loop {
            let length = hebrew_month_length(month, leap, days);
            if remaining < length { break; }
            remaining -= length;
            ordinal += 1;
            month = if month == (if leap { 13 } else { 12 }) { 1 } else { month + 1 };
        }
        let day = remaining + 1;
        let mut number = ordinal;
        let mut status = LeapStatus::Normal;
        if leap && ordinal >= 6 {
            number = ordinal - 1;
            if ordinal == 6 { status = LeapStatus::Leap; }
            if ordinal == 7 { status = LeapStatus::Base; }
        }
        let mut f = CalendarFields::simple(year, 0, "am", YearAmbiguity::CenturyRequired, number, day);
        f.month_ordinal = ordinal;
        f.leap_status = status;
        Some(f)
    }
}

pub enum Chinese {}
impl CalendarSystem for Chinese {
    type MonthNames = DatetimeNamesMonthChineseV1;
    type YearNames = DatetimeNamesYearChineseV1;
    type DatePatterns = DatetimePatternsDateChineseV1;
    type EraData = NeverMarker;
    #[inline]
    fn fields<E: BakedDataMarker>(rd: i64, _: Option<DataValue>) -> Option<CalendarFields> {
        if rd < cy::NEW_YEARS[0] as i64 || rd > cy::LAST_DAY {
            return None;
        }
        let (mut low, mut high) = (0usize, cy::NEW_YEARS.len() - 1);
        while low < high {
            let middle = (low + high + 1) / 2;
            if cy::NEW_YEARS[middle] as i64 <= rd { low = middle } else { high = middle - 1 }
        }
        let info = cy::INFO[low];
        let leap_ordinal = (info >> 16) as i64;
        let mut day = rd - cy::NEW_YEARS[low] as i64 + 1;
        let mut ordinal = 1i64;
        loop {
            let length = if (info >> (ordinal - 1)) & 1 == 1 { 30 } else { 29 };
            if day <= length { break; }
            day -= length;
            ordinal += 1;
        }
        let mut number = ordinal;
        let mut status = LeapStatus::Normal;
        if leap_ordinal != 0 {
            if ordinal == leap_ordinal {
                number = ordinal - 1;
                status = LeapStatus::Leap;
            } else if ordinal > leap_ordinal {
                number = ordinal - 1;
            } else if ordinal + 1 == leap_ordinal {
                status = LeapStatus::Base;
            }
        }
        let related_iso = cy::FIRST_YEAR as i64 + low as i64;
        let cyclic = floor_mod(related_iso - 4, 60) + 1;
        Some(CalendarFields { era_year: related_iso, has_era: false, era_index: -1, era_code: EraCode::new(""), ambiguity: YearAmbiguity::EraRequired, cyclic, related_iso, month_number: number, month_ordinal: ordinal, leap_status: status, day })
    }
}

pub enum Hijri {}
const HIJRI_EPOCH: i64 = 227_015;
#[inline]
fn hijri_fixed(y: i64, m: i64, d: i64) -> i64 {
    d + 29 * (m - 1) + floor_div(6 * m - 1, 11) + (y - 1) * 354 + floor_div(3 + 11 * y, 30) + HIJRI_EPOCH - 1
}
impl CalendarSystem for Hijri {
    type MonthNames = DatetimeNamesMonthHijriV1;
    type YearNames = DatetimeNamesYearHijriV1;
    type DatePatterns = DatetimePatternsDateHijriV1;
    type EraData = NeverMarker;
    #[inline]
    fn fields<E: BakedDataMarker>(rd: i64, _: Option<DataValue>) -> Option<CalendarFields> {
        let year = floor_div(30 * (rd - HIJRI_EPOCH) + 10646, 10631);
        let prior_days = rd - hijri_fixed(year, 1, 1);
        let month = floor_div(11 * prior_days + 330, 325);
        let day = rd - hijri_fixed(year, month, 1) + 1;
        if year > 0 {
            Some(CalendarFields::simple(year, 0, "ah", YearAmbiguity::CenturyRequired, month, day))
        } else {
            Some(CalendarFields::simple(1 - year, 1, "bh", YearAmbiguity::CenturyRequired, month, day))
        }
    }
}

pub enum NoCalendar {}
impl CalendarSystem for NoCalendar {
    type MonthNames = NeverMarker;
    type YearNames = NeverMarker;
    type DatePatterns = NeverMarker;
    type EraData = NeverMarker;
    #[inline]
    fn fields<E: BakedDataMarker>(_: i64, _: Option<DataValue>) -> Option<CalendarFields> {
        Some(CalendarFields { era_year: 0, has_era: false, era_index: -1, era_code: EraCode::new(""), ambiguity: YearAmbiguity::Unambiguous, cyclic: 0, related_iso: 0, month_number: 0, month_ordinal: 0, leap_status: LeapStatus::Normal, day: 0 })
    }
}
impl BakedCalendar for NoCalendar {}

// MARK: - Field sets (FieldSets.swift)

pub trait FieldSet {
    type WeekdayNames: DataMarker;
    type DayPeriodNames: DataMarker;
    type TimePatterns: DataMarker;
    type GluePatterns: DataMarker;
    type DecimalSymbols: DataMarker;
    type DecimalDigits: DataMarker;
    const DATE_ATTRIBUTE: &'static [u8];
    const HAS_DATE: bool;
    const HAS_TIME: bool;
}

pub trait BakedFieldSet: FieldSet<WeekdayNames: BakedDataMarker, DayPeriodNames: BakedDataMarker, TimePatterns: BakedDataMarker, GluePatterns: BakedDataMarker, DecimalSymbols: BakedDataMarker, DecimalDigits: BakedDataMarker> {}

macro_rules! field_set {
    ($name:ident, $w:ty, $dp:ty, $t:ty, $g:ty, $attr:expr, $date:expr, $time:expr) => {
        pub enum $name {}
        impl FieldSet for $name {
            type WeekdayNames = $w;
            type DayPeriodNames = $dp;
            type TimePatterns = $t;
            type GluePatterns = $g;
            type DecimalSymbols = DecimalSymbolsV1;
            type DecimalDigits = DecimalDigitsV1;
            const DATE_ATTRIBUTE: &'static [u8] = $attr;
            const HAS_DATE: bool = $date;
            const HAS_TIME: bool = $time;
        }
    };
}
field_set!(YMD, NeverMarker, NeverMarker, NeverMarker, NeverMarker, b"ym0d", true, false);
field_set!(YMDE, DatetimeNamesWeekdayV1, NeverMarker, NeverMarker, NeverMarker, b"ym0de", true, false);
field_set!(T, NeverMarker, DatetimeNamesDayperiodV1, DatetimePatternsTimeV1, NeverMarker, b"", false, true);
field_set!(YMDT, NeverMarker, DatetimeNamesDayperiodV1, DatetimePatternsTimeV1, DatetimePatternsGlueV1, b"ym0d", true, true);

// MARK: - Numbers (Numbers.swift)

impl TextOutput {
    #[inline]
    pub fn push_scalar(&mut self, v: u32) {
        let mut buf = [0u8; 4];
        self.bytes.extend_from_slice(char::from_u32(v).unwrap_or('?').encode_utf8(&mut buf).as_bytes());
    }
    #[inline]
    pub fn push_ascii(&mut self, value: i64, min_digits: usize) {
        if value < 0 {
            self.push(b'-');
        }
        let mut digits = [b'0'; 24];
        let mut n = value.unsigned_abs();
        let mut count = 0;
        loop {
            digits[count] = b'0' + (n % 10) as u8;
            n /= 10;
            count += 1;
            if n == 0 || count == 24 { break; }
        }
        for _ in count..min_digits.max(count) {
            self.push(b'0');
        }
        for i in (0..count).rev() {
            self.push(digits[i]);
        }
    }
}

mod numeric_override {
    use crate::data_markers::TextOutput;
    const HANIDEC: [u32; 10] = [0x3007, 0x4E00, 0x4E8C, 0x4E09, 0x56DB, 0x4E94, 0x516D, 0x4E03, 0x516B, 0x4E5D];
    pub fn format(number: i64, o: usize, out: &mut TextOutput) {
        match o {
            17 => hanidec(number, out),
            18 => hanidays(number, out),
            19 => hebrew(number, out),
            20 => romanlow(number, out),
            _ => jpnyear(number, out),
        }
    }
    fn jpnyear(n: i64, out: &mut TextOutput) {
        if n == 1 { out.push_scalar(0x5143) } else { out.push_ascii(n, 1) }
    }
    fn hanidec(n: i64, out: &mut TextOutput) {
        if n == 0 {
            out.push_scalar(HANIDEC[0]);
            return;
        }
        let mut digits = [0u8; 10];
        let (mut m, mut count) = (n, 0);
        while m > 0 && count < 10 {
            digits[count] = (m % 10) as u8;
            m /= 10;
            count += 1;
        }
        for i in (0..count).rev() {
            out.push_scalar(HANIDEC[digits[i] as usize]);
        }
    }
    fn hanidays(n: i64, out: &mut TextOutput) {
        const HAN: [u32; 10] = [0x4E00, 0x4E8C, 0x4E09, 0x56DB, 0x4E94, 0x516D, 0x4E03, 0x516B, 0x4E5D, 0x5341];
        match n {
            0 => out.push_scalar(0x3007),
            1..=10 => { out.push_scalar(0x521D); out.push_scalar(HAN[n as usize - 1]) }
            11..=19 => { out.push_scalar(HAN[9]); out.push_scalar(HAN[n as usize - 11]) }
            20 => { out.push_scalar(0x4E8C); out.push_scalar(0x5341) }
            21..=29 => { out.push_scalar(0x5EFF); out.push_scalar(HAN[n as usize - 21]) }
            30 => { out.push_scalar(0x4E09); out.push_scalar(0x5341) }
            31..=39 => { out.push_scalar(0x4E17); out.push_scalar(HAN[n as usize - 31]) }
            40 => { out.push_scalar(0x56DB); out.push_scalar(0x5341) }
            41..=49 => { out.push_scalar(0x534C); out.push_scalar(HAN[n as usize - 41]) }
            _ => out.push_ascii(n, 1),
        }
    }
    fn romanlow(n: i64, out: &mut TextOutput) {
        if n == 0 { out.push(b'n'); return; }
        if n >= 5000 { out.push_ascii(n, 1); return; }
        let mut m = n;
        for (v, s) in [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"), (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")] {
            while m >= v { out.append_str(s); m -= v; }
        }
    }
    const UNITS: [u32; 9] = [0x5D0, 0x5D1, 0x5D2, 0x5D3, 0x5D4, 0x5D5, 0x5D6, 0x5D7, 0x5D8];
    const TENS: [u32; 9] = [0x5D9, 0x5DB, 0x5DC, 0x5DE, 0x5E0, 0x5E1, 0x5E2, 0x5E4, 0x5E6];
    const HUNDREDS: [u32; 9] = [0x18, 0x19, 0x1A, 0x1B, 0x18 << 6 | 0x1B, 0x19 << 6 | 0x1B, 0x1A << 6 | 0x1B, 0x1B << 6 | 0x1B, 0x18 << 12 | 0x1B << 6 | 0x1B];
    const GERESH: u32 = 0x5F3;
    const GERSHAYIM: u32 = 0x5F4;
    fn hundred_letters(h: i64) -> (usize, [u32; 3]) {
        let mut letters = [0u32; 3];
        if !(1..=9).contains(&h) { return (0, letters); }
        let (mut packed, mut count) = (HUNDREDS[h as usize - 1], 0);
        while packed != 0 {
            letters[count] = 0x5D0 + (packed & 0x3F) - 1;
            packed >>= 6;
            count += 1;
        }
        (count, letters)
    }
    fn below_1000(n: i64, force_geresh: bool, out: &mut TextOutput) {
        let (hcount, hl) = hundred_letters(n / 100);
        let rem = n % 100;
        let mut wrote_gershayim = false;
        let write_hundreds = |out: &mut TextOutput| for &l in &hl[..hcount] { out.push_scalar(l) };
        if rem == 15 || rem == 16 {
            write_hundreds(out);
            out.push_scalar(0x5D8);
            out.push_scalar(GERSHAYIM);
            out.push_scalar(if rem == 15 { 0x5D5 } else { 0x5D6 });
            wrote_gershayim = true;
        } else {
            let (tens, units) = (rem / 10, rem % 10);
            if tens > 0 && units > 0 {
                write_hundreds(out);
                out.push_scalar(TENS[tens as usize - 1]);
                out.push_scalar(GERSHAYIM);
                out.push_scalar(UNITS[units as usize - 1]);
                wrote_gershayim = true;
            } else if tens > 0 || units > 0 {
                let x = if tens > 0 { TENS[tens as usize - 1] } else { UNITS[units as usize - 1] };
                if hcount > 0 {
                    write_hundreds(out);
                    out.push_scalar(GERSHAYIM);
                    out.push_scalar(x);
                    wrote_gershayim = true;
                } else {
                    out.push_scalar(x);
                    out.push_scalar(GERESH);
                }
            } else if hcount == 1 {
                out.push_scalar(hl[0]);
                out.push_scalar(GERESH);
            } else if hcount > 1 {
                for &l in &hl[..hcount - 1] { out.push_scalar(l); }
                out.push_scalar(GERSHAYIM);
                out.push_scalar(hl[hcount - 1]);
                wrote_gershayim = true;
            }
        }
        if wrote_gershayim && force_geresh {
            out.push_scalar(GERESH);
        }
    }
    fn hebrew(n: i64, out: &mut TextOutput) {
        match n {
            0 => out.push(b'0'),
            1000 => out.append_str("אלף"),
            2000 => out.append_str("אלפיים"),
            1_000_000 => out.append_str("אלף אלפים"),
            1_000_001.. => out.push_ascii(n, 1),
            1001..=999_999 => {
                let rest = n % 1000;
                below_1000(n / 1000, rest > 0, out);
                if rest == 0 { out.append_str(" אלפים") } else { below_1000(rest, false, out) }
            }
            _ => below_1000(n, false, out),
        }
    }
}

// MARK: - The formatter (Formatter.swift)

#[derive(Clone, Copy, PartialEq)]
pub enum Length {
    Long,
    Medium,
    Short,
}

#[derive(Clone, Copy)]
pub struct DateTime {
    pub year: i64,
    pub month: i64,
    pub day: i64,
    pub hour: i64,
    pub minute: i64,
    pub second: i64,
}

#[derive(Clone, Copy, PartialEq)]
enum Variant {
    Standard,
    Variant0,
    Variant1,
}

fn packed_pattern(words: &[u32], value: DataValue, length: Length, variant: Variant) -> usize {
    let header = words[value.start];
    let lms = header & 3;
    let mut index;
    match variant {
        Variant::Standard => {
            index = match length {
                Length::Long => 0,
                Length::Medium => if lms == 0 || lms == 2 { 0 } else { 1 },
                Length::Short => if lms == 0 { 0 } else if lms == 3 { 2 } else { 1 },
            };
        }
        _ => {
            let cell = (if variant == Variant::Variant0 { 0 } else { 3 }) + match length { Length::Long => 0, Length::Medium => 1, Length::Short => 2 };
            if header & 4 == 0 {
                let chunk = ((header >> (3 + 3 * cell)) & 7) as usize;
                if chunk == 0 {
                    return packed_pattern(words, value, length, Variant::Standard);
                }
                index = chunk - 1;
            } else {
                let s_offset = if lms == 0 { 0 } else if lms == 3 { 2 } else { 1 };
                index = s_offset + 1 + cell as usize;
            }
        }
    }
    let count = words[value.start + 1] as usize;
    if index >= count {
        index = 0;
    }
    value.start + words[value.start + 2 + index] as usize
}

/// The fields of one pattern, for loading their names. No heap memory.
struct FieldList {
    words: [u32; 32],
    count: usize,
}

impl FieldList {
    fn new(words: &[u32], start: usize) -> Self {
        let mut l = FieldList { words: [0; 32], count: 0 };
        for i in 0..words[start] as usize {
            let w = words[start + 1 + i];
            if is_field(w) && l.count < 32 {
                l.words[l.count] = w;
                l.count += 1;
            }
        }
        l
    }
}

pub struct FixedCalendarFormatter<C: CalendarSystem, FS: FieldSet> {
    length: Length,
    date_patterns: Option<DataValue>,
    time_patterns: Option<DataValue>,
    glue: Option<DataValue>,
    month_names: Option<DataValue>,
    year_names: Option<DataValue>,
    weekday_names: Option<DataValue>,
    day_period_names: Option<DataValue>,
    decimal_symbols: Option<DataValue>,
    decimal_digits: Option<DataValue>,
    eras: Option<DataValue>,
    _marker: PhantomData<(C, FS)>,
}

impl<C: BakedCalendar, FS: BakedFieldSet> FixedCalendarFormatter<C, FS> {
    pub fn new(text: &str, length: Length) -> Option<Self> {
        Self::with_locale(&LocaleId::parse(text)?, length)
    }

    pub fn with_locale(locale: &LocaleId, length: Length) -> Option<Self> {
        let mut f = FixedCalendarFormatter { length, date_patterns: None, time_patterns: None, glue: None, month_names: None, year_names: None, weekday_names: None, day_period_names: None, decimal_symbols: None, decimal_digits: None, eras: None, _marker: PhantomData };
        if FS::HAS_DATE {
            f.date_patterns = Some(lookup::<C::DatePatterns>(locale, FS::DATE_ATTRIBUTE)?);
        }
        if FS::HAS_TIME {
            f.time_patterns = Some(lookup::<FS::TimePatterns>(locale, b"j")?);
        }
        if FS::HAS_DATE && FS::HAS_TIME {
            let attribute: &[u8] = match length { Length::Long => b"ldt", Length::Medium => b"mdt", Length::Short => b"sdt" };
            f.glue = Some(lookup::<FS::GluePatterns>(locale, attribute)?);
        }
        f.eras = lookup_singleton::<C::EraData>(b"");
        if let Some(p) = f.date_patterns {
            let words = <C::DatePatterns as BakedDataMarker>::TABLES.words;
            let fields = FieldList::new(words, packed_pattern(words, p, length, Variant::Variant1));
            for i in 0..fields.count {
                if !f.load(fields.words[i], locale) { return None; }
            }
        }
        if let Some(p) = f.time_patterns {
            let words = <FS::TimePatterns as BakedDataMarker>::TABLES.words;
            let fields = FieldList::new(words, packed_pattern(words, p, length, Variant::Variant1));
            for i in 0..fields.count {
                if !f.load(fields.words[i], locale) { return None; }
            }
        }
        Some(f)
    }

    fn load(&mut self, field: u32, locale: &LocaleId) -> bool {
        let symbol = ((field >> 8) & 0xFF) as u8;
        let count = (field & 0xFF) as usize;
        match symbol {
            b'G' | b'U' => {
                if self.year_names.is_none() {
                    self.year_names = lookup::<C::YearNames>(locale, match count { 4 => b"5", 5 => b"4", _ => b"3" });
                }
                self.year_names.is_some()
            }
            b'M' | b'L' => {
                if count >= 17 { return true; }
                if self.month_names.is_none() {
                    let s = symbol == b'L';
                    let attribute: &[u8] = match count { 1 | 2 => b"1", 3 => if s { b"3s" } else { b"3" }, 4 => if s { b"5s" } else { b"5" }, _ => if s { b"4s" } else { b"4" } };
                    self.month_names = lookup::<C::MonthNames>(locale, attribute);
                }
                if self.month_names.is_none() { return false; }
                count > 2 || self.load_decimal(locale)
            }
            b'E' | b'c' | b'e' => {
                if self.weekday_names.is_none() {
                    let s = symbol == b'c';
                    let n = if symbol == b'E' && count < 3 { 3 } else { count };
                    let attribute: &[u8] = match n { 3 => if s { b"3s" } else { b"3" }, 4 => if s { b"5s" } else { b"5" }, 5 => if s { b"4s" } else { b"4" }, _ => if s { b"6s" } else { b"6" } };
                    self.weekday_names = lookup::<FS::WeekdayNames>(locale, attribute);
                }
                self.weekday_names.is_some()
            }
            b'a' | b'b' | b'B' => {
                if self.day_period_names.is_none() {
                    self.day_period_names = lookup::<FS::DayPeriodNames>(locale, match count { 4 => b"5", 5 => b"4", _ => b"3" });
                }
                self.day_period_names.is_some()
            }
            b'y' | b'd' => count >= 17 || self.load_decimal(locale),
            b'h' | b'H' | b'K' | b'k' | b'm' | b's' => self.load_decimal(locale),
            b'r' => true,
            _ => false,
        }
    }

    fn load_decimal(&mut self, locale: &LocaleId) -> bool {
        if self.decimal_digits.is_some() { return true; }
        let Some(s) = lookup::<FS::DecimalSymbols>(locale, b"") else { return false };
        self.decimal_symbols = Some(s);
        let t = <FS::DecimalSymbols as BakedDataMarker>::TABLES;
        let r = t.words[s.start + 6];
        self.decimal_digits = lookup_singleton::<FS::DecimalDigits>(&t.pool[text_offset(r)..text_offset(r) + text_count(r)]);
        self.decimal_digits.is_some()
    }

    pub fn format_into(&self, dt: &DateTime, out: &mut TextOutput) -> bool {
        let rd = rata_die(dt.year, dt.month, dt.day);
        let Some(fields) = C::fields::<C::EraData>(rd, self.eras) else { return false };
        let weekday = floor_mod(rd, 7) as usize;
        if let Some(g) = self.glue {
            let t = <FS::GluePatterns as BakedDataMarker>::TABLES;
            for i in 0..t.words[g.start] as usize {
                let w = t.words[g.start + 1 + i];
                if !is_field(w) {
                    out.append(w, t.pool);
                } else if (w >> 8) & 0xFF == 0x31 {
                    self.write_date(&fields, weekday, dt, out);
                } else {
                    self.write_time(&fields, weekday, dt, out);
                }
            }
        } else if self.date_patterns.is_some() {
            self.write_date(&fields, weekday, dt, out);
        } else {
            self.write_time(&fields, weekday, dt, out);
        }
        true
    }

    pub fn format(&self, dt: &DateTime) -> Option<String> {
        let mut out = TextOutput::new();
        if !self.format_into(dt, &mut out) { return None; }
        String::from_utf8(out.bytes).ok()
    }

    fn date_variant(f: &CalendarFields) -> Variant {
        match if f.has_era { f.ambiguity } else { YearAmbiguity::EraRequired } {
            YearAmbiguity::Unambiguous | YearAmbiguity::EraRequired => Variant::Standard,
            YearAmbiguity::CenturyRequired => Variant::Variant0,
            YearAmbiguity::EraAndCenturyRequired => Variant::Variant1,
        }
    }

    fn write_date(&self, f: &CalendarFields, weekday: usize, dt: &DateTime, out: &mut TextOutput) {
        let Some(p) = self.date_patterns else { return };
        let t = <C::DatePatterns as BakedDataMarker>::TABLES;
        self.write_items(t.words, packed_pattern(t.words, p, self.length, Self::date_variant(f)), t.pool, f, weekday, dt, out);
    }

    fn write_time(&self, f: &CalendarFields, weekday: usize, dt: &DateTime, out: &mut TextOutput) {
        let Some(p) = self.time_patterns else { return };
        let t = <FS::TimePatterns as BakedDataMarker>::TABLES;
        self.write_items(t.words, packed_pattern(t.words, p, self.length, Variant::Variant0), t.pool, f, weekday, dt, out);
    }

    #[allow(clippy::too_many_arguments)]
    fn write_items(&self, words: &[u32], start: usize, pool: &[u8], f: &CalendarFields, weekday: usize, dt: &DateTime, out: &mut TextOutput) {
        for i in 0..words[start] as usize {
            let w = words[start + 1 + i];
            if is_field(w) {
                self.write_field(((w >> 8) & 0xFF) as u8, (w & 0xFF) as usize, f, weekday, dt, out);
            } else {
                out.append(w, pool);
            }
        }
    }

    fn write_field(&self, symbol: u8, count: usize, f: &CalendarFields, weekday: usize, dt: &DateTime, out: &mut TextOutput) {
        match symbol {
            b'G' => self.write_era(f, out),
            b'y' => {
                if count >= 17 && f.era_year >= 0 {
                    numeric_override::format(f.era_year, count, out);
                } else {
                    self.write_number(if count == 2 { f.era_year % 100 } else { f.era_year }, count, out);
                }
            }
            b'U' => self.write_cyclic(f, out),
            b'r' => out.push_ascii(f.related_iso, count),
            b'M' | b'L' => {
                if count >= 17 { numeric_override::format(f.month_number, count, out) } else { self.write_month(f, count, out) }
            }
            b'd' => {
                if count >= 17 { numeric_override::format(f.day, count, out) } else { self.write_number(f.day, count, out) }
            }
            b'E' | b'c' | b'e' => self.write_weekday(weekday, out),
            b'h' => {
                let h = dt.hour % 12;
                self.write_number(if h == 0 { 12 } else { h }, count, out);
            }
            b'K' => self.write_number(dt.hour % 12, count, out),
            b'H' | b'k' => self.write_number(dt.hour, count, out),
            b'm' => self.write_number(dt.minute, count, out),
            b's' => self.write_number(dt.second, count, out),
            b'a' | b'b' | b'B' => self.write_day_period(symbol, dt, out),
            _ => {}
        }
    }

    fn write_number(&self, value: i64, min_digits: usize, out: &mut TextOutput) {
        let (Some(digits), Some(symbols)) = (self.decimal_digits, self.decimal_symbols) else {
            out.push_ascii(value, min_digits);
            return;
        };
        let s = <FS::DecimalSymbols as BakedDataMarker>::TABLES;
        let d = <FS::DecimalDigits as BakedDataMarker>::TABLES;
        if value < 0 {
            out.append(s.words[symbols.start], s.pool);
        }
        let mut decimal = [0u8; 24];
        let mut n = value.unsigned_abs();
        let mut count = 0;
        loop {
            decimal[count] = (n % 10) as u8;
            n /= 10;
            count += 1;
            if n == 0 || count == 24 { break; }
        }
        for _ in count..min_digits.max(count) {
            out.append(d.words[digits.start], d.pool);
        }
        for i in (0..count).rev() {
            out.append(d.words[digits.start + decimal[i] as usize], d.pool);
        }
        if value < 0 {
            out.append(s.words[symbols.start + 1], s.pool);
        }
    }

    fn write_era_code(f: &CalendarFields, out: &mut TextOutput) {
        out.bytes.extend_from_slice(&f.era_code.bytes[..f.era_code.count]);
    }

    fn write_era(&self, f: &CalendarFields, out: &mut TextOutput) {
        let Some(names) = self.year_names else { return Self::write_era_code(f, out) };
        let t = <C::YearNames as BakedDataMarker>::TABLES;
        let n = t.words[names.start + 1] as usize;
        let found = match t.words[names.start] {
            0 => {
                if f.era_index >= 0 && (f.era_index as usize) < n {
                    out.append(t.words[names.start + 2 + f.era_index as usize], t.pool);
                    true
                } else { false }
            }
            1 => {
                let (mut low, mut high, mut found) = (0, n, false);
                while low < high {
                    let middle = (low + high) / 2;
                    match f.era_code.compare(t.words[names.start + 2 + middle], t.pool) {
                        core::cmp::Ordering::Equal => {
                            out.append(t.words[names.start + 2 + n + middle], t.pool);
                            found = true;
                            break;
                        }
                        core::cmp::Ordering::Less => low = middle + 1,
                        core::cmp::Ordering::Greater => high = middle,
                    }
                }
                found
            }
            _ => false,
        };
        if !found { Self::write_era_code(f, out) }
    }

    fn write_cyclic(&self, f: &CalendarFields, out: &mut TextOutput) {
        if f.cyclic == 0 {
            return self.write_number(f.era_year, 1, out);
        }
        if let Some(names) = self.year_names {
            let t = <C::YearNames as BakedDataMarker>::TABLES;
            if t.words[names.start] == 2 && ((f.cyclic - 1) as usize) < t.words[names.start + 1] as usize {
                out.append(t.words[names.start + 2 + (f.cyclic - 1) as usize], t.pool);
                return;
            }
        }
        self.write_number(f.related_iso, 1, out);
    }

    fn write_month(&self, f: &CalendarFields, count: usize, out: &mut TextOutput) {
        let Some(names) = self.month_names else { return Self::write_month_code(f, out) };
        let t = <C::MonthNames as BakedDataMarker>::TABLES;
        let index = f.month_number - 1;
        let at = names.start + 1;
        let done = match t.words[names.start] {
            0 => { self.write_number(f.month_number, count, out); true }
            1 => {
                if f.leap_status == LeapStatus::Normal && (0..12).contains(&index) {
                    out.append(t.words[at + index as usize], t.pool);
                    true
                } else { false }
            }
            2 => {
                if !(0..12).contains(&index) { false } else {
                    let leap = f.leap_status == LeapStatus::Leap || (f.leap_status == LeapStatus::Base && f.month_number < f.month_ordinal);
                    out.append(t.words[at + if leap { 12 } else { 0 } + index as usize], t.pool);
                    true
                }
            }
            3 => {
                if f.leap_status == LeapStatus::Leap {
                    self.write_placeholder_pattern(t.words, at, t.pool, f.month_number, count, out);
                } else {
                    self.write_number(f.month_number, count, out);
                }
                true
            }
            4 => {
                let first = at + 1;
                let second = first + 1 + t.words[first] as usize;
                if f.leap_status == LeapStatus::Leap {
                    self.write_placeholder_pattern(t.words, first, t.pool, f.month_number + t.words[at] as i32 as i64, count, out);
                } else if f.leap_status == LeapStatus::Base {
                    self.write_placeholder_pattern(t.words, second + 1, t.pool, f.month_number + t.words[second] as i32 as i64, count, out);
                } else {
                    self.write_number(f.month_number, count, out);
                }
                true
            }
            _ => false,
        };
        if !done { Self::write_month_code(f, out) }
    }

    #[allow(clippy::too_many_arguments)]
    fn write_placeholder_pattern(&self, words: &[u32], start: usize, pool: &[u8], number: i64, min_digits: usize, out: &mut TextOutput) {
        for i in 0..words[start] as usize {
            let w = words[start + 1 + i];
            if is_field(w) { self.write_number(number, min_digits, out) } else { out.append(w, pool) }
        }
    }

    fn write_month_code(f: &CalendarFields, out: &mut TextOutput) {
        out.push(b'M');
        out.push_ascii(f.month_number, 2);
        if f.leap_status == LeapStatus::Leap { out.push(b'L'); }
    }

    fn write_weekday(&self, weekday: usize, out: &mut TextOutput) {
        let Some(names) = self.weekday_names else { return };
        let t = <FS::WeekdayNames as BakedDataMarker>::TABLES;
        if weekday < t.words[names.start] as usize {
            out.append(t.words[names.start + 1 + weekday], t.pool);
        }
    }

    fn write_day_period(&self, symbol: u8, dt: &DateTime, out: &mut TextOutput) {
        let Some(names) = self.day_period_names else { return };
        let t = <FS::DayPeriodNames as BakedDataMarker>::TABLES;
        let n = t.words[names.start] as usize;
        let texts = names.start + 1;
        if symbol == b'B' && n > 4 {
            let rules = t.words[texts + 4];
            if text_count(rules) >= 4 {
                let o = text_offset(rules);
                let raw = (t.pool[o] as u32) << 17 | (t.pool[o + 1] as u32) << 10 | (t.pool[o + 2] as u32) << 3 | t.pool[o + 3] as u32;
                let transitions = raw & 0xFF_FFFF;
                let up_to_hour = (transitions << (31 - dt.hour as u32)).count_ones() as usize;
                let offset = if up_to_hour == 0 { transitions.count_ones() as usize - 1 } else { up_to_hour - 1 };
                if offset == 0 {
                    out.append(((o + 4) as u32) << 8 | (text_count(rules) - 4) as u32, t.pool);
                    return;
                }
                if 4 + offset < n {
                    out.append(t.words[texts + 4 + offset], t.pool);
                    return;
                }
            }
        }
        if symbol == b'b' && dt.minute == 0 && dt.second == 0 {
            if dt.hour == 0 && n > 3 && text_count(t.words[texts + 3]) > 0 {
                out.append(t.words[texts + 3], t.pool);
                return;
            }
            if dt.hour == 12 && n > 2 && text_count(t.words[texts + 2]) > 0 {
                out.append(t.words[texts + 2], t.pool);
                return;
            }
        }
        out.append(t.words[texts + if dt.hour < 12 { 0 } else { 1 }], t.pool);
    }
}

// MARK: - Any calendar
// Behind the feature any-calendar, because it needs data for all 6 calendars. Data that is cut for one app does not have it.

#[cfg(feature = "any-calendar")]
pub enum AnyCalendarFormatter<FS: FieldSet> {
    Gregorian(FixedCalendarFormatter<Gregorian, FS>),
    Buddhist(FixedCalendarFormatter<Buddhist, FS>),
    Japanese(FixedCalendarFormatter<Japanese, FS>),
    Hebrew(FixedCalendarFormatter<Hebrew, FS>),
    Chinese(FixedCalendarFormatter<Chinese, FS>),
    Hijri(FixedCalendarFormatter<Hijri, FS>),
}

#[cfg(feature = "any-calendar")]
fn keyword(text: &str) -> u64 {
    text.bytes().take(8).enumerate().fold(0, |v, (n, b)| v | (b as u64) << (8 * n))
}

#[cfg(feature = "any-calendar")]
impl<FS: BakedFieldSet> AnyCalendarFormatter<FS>
where
    Gregorian: BakedCalendar,
    Buddhist: BakedCalendar,
    Japanese: BakedCalendar,
    Hebrew: BakedCalendar,
    Chinese: BakedCalendar,
    Hijri: BakedCalendar,
{
    pub fn new(text: &str, length: Length) -> Option<Self> {
        let locale = LocaleId::parse(text)?;
        let c = locale.calendar;
        Some(if c == keyword("buddhist") {
            Self::Buddhist(FixedCalendarFormatter::with_locale(&locale, length)?)
        } else if c == keyword("japanese") {
            Self::Japanese(FixedCalendarFormatter::with_locale(&locale, length)?)
        } else if c == keyword("hebrew") {
            Self::Hebrew(FixedCalendarFormatter::with_locale(&locale, length)?)
        } else if c == keyword("chinese") {
            Self::Chinese(FixedCalendarFormatter::with_locale(&locale, length)?)
        } else if c == keyword("islamic") {
            Self::Hijri(FixedCalendarFormatter::with_locale(&locale, length)?)
        } else {
            Self::Gregorian(FixedCalendarFormatter::with_locale(&locale, length)?)
        })
    }

    pub fn format_into(&self, dt: &DateTime, out: &mut TextOutput) -> bool {
        match self {
            Self::Gregorian(f) => f.format_into(dt, out),
            Self::Buddhist(f) => f.format_into(dt, out),
            Self::Japanese(f) => f.format_into(dt, out),
            Self::Hebrew(f) => f.format_into(dt, out),
            Self::Chinese(f) => f.format_into(dt, out),
            Self::Hijri(f) => f.format_into(dt, out),
        }
    }
}
