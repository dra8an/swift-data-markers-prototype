// The core of the Rust copy (module data_markers, like the Swift module DataMarkers): the same design as swift/Sources/DataMarkers/DataMarkers.swift, line for line where Rust allows it.

// MARK: - Markers

/// One kind of locale data.
pub trait DataMarker {
    const NAME: &'static str;
}

/// The 5 tables of a marker (DESIGN.md, decision 11).
#[derive(Clone, Copy)]
pub struct BakedTables {
    pub pool: &'static [u8],
    pub keys: &'static [u32],
    pub key_values: &'static [u16],
    pub value_starts: &'static [u32],
    pub words: &'static [u32],
}

/// A marker whose data is built into the app. The generated data.rs implements it for each marker.
pub trait BakedDataMarker: DataMarker {
    const TABLES: BakedTables;
}

/// The marker of data that a field set does not use. It has no data.
pub enum NeverMarker {}
impl DataMarker for NeverMarker {
    const NAME: &'static str = "NeverMarker";
}
impl BakedDataMarker for NeverMarker {
    const TABLES: BakedTables = BakedTables { pool: &[], keys: &[], key_values: &[], value_starts: &[], words: &[] };
}

// MARK: - Values

/// A value in the words table of one marker.
#[derive(Clone, Copy)]
pub struct DataValue {
    pub start: usize,
    pub end: usize,
}

/// A text in the pool of one marker: offset << 8 | length.
pub type TextRef = u32;

#[inline]
pub fn is_field(w: u32) -> bool {
    w & 0x8000_0000 != 0
}
#[inline]
pub fn text_offset(w: u32) -> usize {
    (w >> 8) as usize
}
#[inline]
pub fn text_count(w: u32) -> usize {
    (w & 0xFF) as usize
}

/// The output of a formatter: UTF-8 bytes.
pub struct TextOutput {
    pub bytes: Vec<u8>,
}

impl TextOutput {
    #[inline]
    pub fn new() -> Self {
        TextOutput { bytes: Vec::with_capacity(64) }
    }
    #[inline]
    pub fn push(&mut self, b: u8) {
        self.bytes.push(b);
    }
    #[inline]
    pub fn append(&mut self, r: TextRef, pool: &[u8]) {
        let o = text_offset(r);
        self.bytes.extend_from_slice(&pool[o..o + text_count(r)]);
    }
    #[inline]
    pub fn append_str(&mut self, s: &str) {
        self.bytes.extend_from_slice(s.as_bytes());
    }
}

// MARK: - Locales

/// A locale: language, script and region packed into a u32 each, one variant packed into a u64, and the -u-ca- value.
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct LocaleId {
    pub language: u32,
    pub script: u32,
    pub region: u32,
    pub variant: u64,
    pub calendar: u64,
}

pub const UND: LocaleId = LocaleId { language: 0x0064_6E75, script: 0, region: 0, variant: 0, calendar: 0 };

fn all_letters(s: &[u8]) -> bool {
    s.iter().all(|b| (b | 0x20) >= 0x61 && (b | 0x20) <= 0x7A)
}
fn all_digits(s: &[u8]) -> bool {
    s.iter().all(|b| b.is_ascii_digit())
}
fn pack(s: &[u8], lowercase: bool, uppercase: bool, titlecase: bool) -> u32 {
    let mut value = 0u32;
    for (n, &raw) in s.iter().enumerate() {
        let mut b = raw;
        if b.is_ascii_uppercase() && lowercase && !(titlecase && n == 0) {
            b |= 0x20;
        }
        if b.is_ascii_lowercase() && (uppercase || (titlecase && n == 0)) {
            b &= !0x20;
        }
        value |= (b as u32) << (8 * n as u32);
    }
    value
}

impl LocaleId {
    #[inline]
    pub fn is_und(&self) -> bool {
        self.language == UND.language && self.script == 0 && self.region == 0 && self.variant == 0
    }

    /// Parses a BCP 47 locale such as "zh-Hant-TW" or "th-u-ca-buddhist".
    pub fn parse(text: &str) -> Option<LocaleId> {
        let subtags: Vec<&[u8]> = text.as_bytes().split(|&b| b == b'-' || b == b'_').collect();
        let first = subtags[0];
        if first.len() < 2 || first.len() > 3 {
            return None;
        }
        let mut l = LocaleId { language: pack(first, true, false, false), script: 0, region: 0, variant: 0, calendar: 0 };
        let mut i = 1;
        while i < subtags.len() {
            let s = subtags[i];
            if s.len() == 1 {
                break;
            }
            if s.len() == 4 && all_letters(s) && l.script == 0 && l.region == 0 && l.variant == 0 {
                l.script = pack(s, true, false, true);
            } else if ((s.len() == 2 && all_letters(s)) || (s.len() == 3 && all_digits(s))) && l.variant == 0 {
                l.region = pack(s, false, true, false);
            } else if ((5..=8).contains(&s.len()) || (s.len() == 4 && s[0].is_ascii_digit())) && l.variant == 0 {
                for (n, &raw) in s.iter().enumerate() {
                    l.variant |= (raw.to_ascii_lowercase() as u64) << (8 * n as u64);
                }
            } else {
                return None;
            }
            i += 1;
        }
        if i < subtags.len() && subtags[i] == b"u" {
            i += 1;
            while i + 1 < subtags.len() {
                if subtags[i] == b"ca" {
                    for (n, &b) in subtags[i + 1].iter().take(8).enumerate() {
                        l.calendar |= (b as u64) << (8 * n as u64);
                    }
                    break;
                }
                i += 1;
            }
        }
        Some(l)
    }
}

// MARK: - Keys

/// The bytes of a key: the locale, 0x1E, the attribute. No heap memory.
pub struct DataKey {
    pub bytes: [u8; 32],
    pub count: usize,
}

impl DataKey {
    #[inline]
    pub fn new(locale: &LocaleId, attribute: &[u8]) -> Self {
        let mut k = DataKey { bytes: [0; 32], count: 0 };
        k.append_subtag(locale.language as u64);
        if locale.script != 0 {
            k.push(0x2D);
            k.append_subtag(locale.script as u64);
        }
        if locale.region != 0 {
            k.push(0x2D);
            k.append_subtag(locale.region as u64);
        }
        if locale.variant != 0 {
            k.push(0x2D);
            k.append_subtag(locale.variant);
        }
        k.push(0x1E);
        for &b in attribute {
            k.push(b);
        }
        k
    }
    #[inline]
    pub fn push(&mut self, b: u8) {
        self.bytes[self.count] = b;
        self.count += 1;
    }
    #[inline]
    fn append_subtag(&mut self, mut s: u64) {
        while s != 0 {
            self.push((s & 0xFF) as u8);
            s >>= 8;
        }
    }
    #[inline]
    fn compare(&self, r: TextRef, pool: &[u8]) -> core::cmp::Ordering {
        let o = text_offset(r);
        pool[o..o + text_count(r)].cmp(&self.bytes[..self.count])
    }
}

// MARK: - The fallback of ICU4X, with language priority

use crate::fallback_tables as ft;

fn likely(language: u32) -> Option<(u32, u32)> {
    ft::LANGUAGE_KEYS.binary_search(&language).ok().map(|i| (ft::LANGUAGE_SCRIPTS[i], ft::LANGUAGE_REGIONS[i]))
}

fn script_for(language: u32, region: u32) -> Option<u32> {
    let n = ft::LANGUAGE_REGION_KEYS.len() / 2;
    let (mut low, mut high) = (0, n);
    while low < high {
        let middle = (low + high) / 2;
        let k = (ft::LANGUAGE_REGION_KEYS[2 * middle], ft::LANGUAGE_REGION_KEYS[2 * middle + 1]);
        if k == (language, region) {
            return Some(ft::LANGUAGE_REGION_SCRIPTS[middle]);
        }
        if k < (language, region) { low = middle + 1 } else { high = middle }
    }
    None
}

fn parent(l: &LocaleId) -> Option<LocaleId> {
    let wanted = (l.language, l.script, l.region);
    let n = ft::PARENT_KEYS.len() / 3;
    let (mut low, mut high) = (0, n);
    while low < high {
        let middle = (low + high) / 2;
        let k = (ft::PARENT_KEYS[3 * middle], ft::PARENT_KEYS[3 * middle + 1], ft::PARENT_KEYS[3 * middle + 2]);
        if k == wanted {
            let v = &ft::PARENT_VALUES[3 * middle..3 * middle + 3];
            return Some(LocaleId { language: v[0], script: v[1], region: v[2], variant: 0, calendar: 0 });
        }
        if k < wanted { low = middle + 1 } else { high = middle }
    }
    None
}

/// Walks the locales that a lookup tries (step_language in ICU4X).
pub struct LocaleFallbackIterator {
    pub current: LocaleId,
    max_script: u32,
    backup_variant: u64,
}

impl LocaleFallbackIterator {
    pub fn new(locale: &LocaleId) -> Self {
        let mut l = *locale;
        l.calendar = 0;
        let mut default_script = 0;
        if l.script != 0 || l.region != 0 {
            if let Some(s) = if l.region != 0 { script_for(l.language, l.region) } else { None } {
                default_script = s;
            } else if let Some((s, _)) = likely(l.language) {
                default_script = s;
            }
            if l.script == default_script {
                l.script = 0;
            }
        }
        let max_script = if l.script != 0 { l.script } else { default_script };
        LocaleFallbackIterator { current: l, max_script, backup_variant: 0 }
    }

    pub fn step(&mut self) {
        if self.current.variant != 0 {
            self.backup_variant = self.current.variant;
            self.current.variant = 0;
            return;
        }
        if let Some(p) = parent(&self.current) {
            self.current = p;
            self.current.variant = self.backup_variant;
            self.backup_variant = 0;
            return;
        }
        if self.current.region != 0 {
            let implied = likely(self.current.language).map(|x| x.0).unwrap_or(0);
            self.current.script = if implied != self.max_script { self.max_script } else { 0 };
            self.current.region = 0;
            self.current.variant = self.backup_variant;
            self.backup_variant = 0;
            return;
        }
        self.current = UND;
    }
}

// MARK: - The lookup

#[inline]
pub fn lookup_exact<M: BakedDataMarker>(key: &DataKey) -> Option<DataValue> {
    let t = M::TABLES;
    let (mut low, mut high) = (0, t.keys.len());
    while low < high {
        let middle = (low + high) / 2;
        match key.compare(t.keys[middle], t.pool) {
            core::cmp::Ordering::Equal => {
                let v = t.key_values[middle] as usize;
                return Some(DataValue { start: t.value_starts[v] as usize, end: t.value_starts[v + 1] as usize });
            }
            core::cmp::Ordering::Less => low = middle + 1,
            core::cmp::Ordering::Greater => high = middle,
        }
    }
    None
}

#[inline]
pub fn lookup<M: BakedDataMarker>(locale: &LocaleId, attribute: &[u8]) -> Option<DataValue> {
    let mut it = LocaleFallbackIterator::new(locale);
    loop {
        if let Some(v) = lookup_exact::<M>(&DataKey::new(&it.current, attribute)) {
            return Some(v);
        }
        if it.current.is_und() {
            return None;
        }
        it.step();
    }
}

#[inline]
pub fn lookup_singleton<M: BakedDataMarker>(attribute: &[u8]) -> Option<DataValue> {
    lookup_exact::<M>(&DataKey::new(&UND, attribute))
}
