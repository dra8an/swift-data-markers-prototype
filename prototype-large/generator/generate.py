"""Generates the baked data of the large prototype, in Swift and in Rust, from the JSON output of icu4x-datagen.

See DESIGN.md, decisions 1, 2 and 10. Python 3.9, standard library only.

Usage:
  python3 -I generate.py --fs <icu4x-datagen fs folder> --fallback <fs folder of the fallback markers> --out <folder>
                         [--markers A,B] [--locales ko,en | all] [--attributes 5,ym0d]

Output in <folder>:
  swift/<Marker>+Data.swift   one file for each marker: the tables and the conformance to BakedDataMarker
  swift/Conformances.swift    the conformances of the calendars and field sets whose markers are all in the data
  rust/data.rs                the same tables for the Rust copy
  markers.json                marker name, hash and tag
  stats.json                  the sizes of the tables of each marker
The fallback tables are written by --fallback-out (once, into the core modules), see write_fallback().
"""
import argparse
import json
import os
import re

TAG = b"dmk1"
SEPARATOR = 0x1E
CALENDARS = ["Gregorian", "Buddhist", "Japanese", "Hebrew", "Chinese", "Hijri"]

# Marker name: (path in the fs folder, kind of value, layout)
# layout "attr": <path>/<attribute>/<locale>.json. "locale": <path>/<locale>.json. "singleton": <path>.json. "digits": <path>/<numsys>/und.json
MARKERS = {}
for cal in CALENDARS:
    low = cal.lower()
    MARKERS[f"DatetimeNamesMonth{cal}V1"] = (f"datetime/names/month/{low}/v1", "month", "attr")
    MARKERS[f"DatetimeNamesYear{cal}V1"] = (f"datetime/names/year/{low}/v1", "year", "attr")
    MARKERS[f"DatetimePatternsDate{cal}V1"] = (f"datetime/patterns/date/{low}/v1", "packed", "attr")
MARKERS["DatetimeNamesWeekdayV1"] = ("datetime/names/weekday/v1", "list", "attr")
MARKERS["DatetimeNamesDayperiodV1"] = ("datetime/names/dayperiod/v1", "list", "attr")
MARKERS["DatetimePatternsTimeV1"] = ("datetime/patterns/time/v1", "packed", "attr")
MARKERS["DatetimePatternsGlueV1"] = ("datetime/patterns/glue/v1", "glue", "attr")
MARKERS["CalendarJapaneseModernV1"] = ("calendar/japanese/modern/v1", "eras", "singleton")
MARKERS["DecimalSymbolsV1"] = ("decimal/symbols/v1", "symbols", "locale")
MARKERS["DecimalDigitsV1"] = ("decimal/digits/v1", "digits", "digits")

# The markers of each calendar and field set (DESIGN.md, decision 10). A conformance is written only if all its markers are in the data.
CALENDAR_MARKERS = {cal: [f"DatetimeNamesMonth{cal}V1", f"DatetimeNamesYear{cal}V1", f"DatetimePatternsDate{cal}V1"] + (["CalendarJapaneseModernV1"] if cal == "Japanese" else []) for cal in CALENDARS}
FIELD_SET_MARKERS = {
    "YMD": ["DecimalSymbolsV1", "DecimalDigitsV1"],
    "YMDE": ["DatetimeNamesWeekdayV1", "DecimalSymbolsV1", "DecimalDigitsV1"],
    "T": ["DatetimeNamesDayperiodV1", "DatetimePatternsTimeV1", "DecimalSymbolsV1", "DecimalDigitsV1"],
    "YMDT": ["DatetimeNamesDayperiodV1", "DatetimePatternsTimeV1", "DatetimePatternsGlueV1", "DecimalSymbolsV1", "DecimalDigitsV1"],
}

FIELD_FLAG = 0x80000000


def fnv1a32(data):
    h = 0x811C9DC5
    for b in data:
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def marker_tag(name):
    return TAG + fnv1a32(name.encode()).to_bytes(4, "little")


# MARK: - Locales and the fallback of ICU4X (language priority), used to cut the data


class Fallback:
    """The fallback of ICU4X with language priority (components/locale_fallback/src/algorithms.rs)."""

    def __init__(self, folder):
        likely = json.load(open(os.path.join(folder, "locale/likely/subtags/language/v1.json")))
        self.language_script = {(l, s): r for (l, s), r in likely["language_script"]}
        self.language_region = {(l, r): s for (l, r), s in likely["language_region"]}
        self.language = {l: tuple(v) for l, v in likely["language"].items()}
        self.und = tuple(likely["und"])
        self.parents = {k: tuple(v) for k, v in json.load(open(os.path.join(folder, "locale/parents/v1.json")))["parents"].items()}

    @staticmethod
    def parse(locale):
        """[language, script, region, variant]. The prototype supports one variant."""
        parts = locale.split("-")
        lang, script, region, variant = parts[0], None, None, None
        for p in parts[1:]:
            if len(p) == 4 and p.isalpha() and not region and not variant:
                script = p
            elif ((len(p) == 2 and p.isalpha()) or (len(p) == 3 and p.isdigit())) and not variant:
                region = p
            elif (5 <= len(p) <= 8 or (len(p) == 4 and p[0].isdigit())) and not variant:
                variant = p.lower()
            else:
                raise SystemExit(f"Locale {locale!r}: subtag {p!r} is not supported by the prototype")
        return [lang, script, region, variant]

    @staticmethod
    def text(loc):
        return "-".join(x for x in loc if x)

    def chain(self, locale):
        """All locales that a lookup for `locale` tries, in order, ending with und."""
        loc = self.parse(locale)
        default_script = None
        if loc[1] or loc[2]:
            default_script = self.language_region.get((loc[0], loc[2])) if loc[2] else None
            if default_script is None and loc[0] in self.language:
                default_script = self.language[loc[0]][0]
            if loc[1] == default_script:
                loc[1] = None
        max_script = loc[1] or default_script
        out = [self.text(loc)]
        backup_variant = None
        while self.text(loc) != "und":
            parent = self.parents.get(self.text(loc))
            if loc[3]:
                backup_variant, loc[3] = loc[3], None
            elif parent:
                loc = [parent[0], parent[1], parent[2], backup_variant]
                backup_variant = None
            elif loc[2]:
                implied = self.language[loc[0]][0] if loc[0] in self.language else None
                loc = [loc[0], max_script if implied != max_script else None, None, backup_variant]
                backup_variant = None
            else:
                loc = ["und", None, None, None]
            out.append(self.text(loc))
        return out


# MARK: - Patterns


def parse_pattern(p):
    """Splits a UTS 35 pattern into items: ("lit", text) and ("field", symbol, length). Quotes as in UTS 35."""
    items, i, lit = [], 0, []
    while i < len(p):
        c = p[i]
        if c == "'":
            # '' is a quote. Otherwise the text up to the next single quote is literal, and '' inside it is a quote.
            if i + 1 < len(p) and p[i + 1] == "'":
                lit.append("'")
                i += 2
                continue
            j = i + 1
            while j < len(p):
                if p[j] == "'":
                    if j + 1 < len(p) and p[j + 1] == "'":
                        lit.append("'")
                        j += 2
                        continue
                    break
                lit.append(p[j])
                j += 1
            i = j + 1
        elif ("a" <= c <= "z") or ("A" <= c <= "Z"):
            j = i
            while j < len(p) and p[j] == c:
                j += 1
            if lit:
                items.append(("lit", "".join(lit)))
                lit = []
            items.append(("field", c, j - i))
            i = j
        else:
            lit.append(c)
            i += 1
    if lit:
        items.append(("lit", "".join(lit)))
    return items


def parse_placeholder_pattern(p):
    """A glue pattern such as "{1} 'at' {0}": items ("lit", text) and ("field", "0" or "1", 1). Quotes as in UTS 35."""
    items, lit, i = [], [], 0
    while i < len(p):
        c = p[i]
        if c == "'":
            if i + 1 < len(p) and p[i + 1] == "'":
                lit.append("'")
                i += 2
                continue
            j = p.index("'", i + 1)
            lit.append(p[i + 1:j])
            i = j + 1
        elif c == "{" and p[i:i + 3] in ("{0}", "{1}"):
            if lit:
                items.append(("lit", "".join(lit)))
                lit = []
            items.append(("field", p[i + 1], 1))
            i += 3
        else:
            lit.append(c)
            i += 1
    if lit:
        items.append(("lit", "".join(lit)))
    return items


def single_placeholder_items(parts):
    """The JSON form of a single placeholder pattern: [{"Literal": "闰"}, {"Placeholder": "Singleton"}]."""
    items = []
    for part in parts:
        if "Literal" in part:
            items.append(("lit", part["Literal"]))
        else:
            items.append(("field", "0", 1))
    return items


# MARK: - Packing into tables


class Packer:
    """The tables of one marker (DESIGN.md, decision 11)."""

    def __init__(self, marker):
        self.pool = bytearray(marker_tag(marker))
        self.text_at = {}
        self.words = []
        self.value_starts = []
        self.value_index = {}

    def text(self, s):
        b = s.encode("utf-8")
        assert len(b) < 256, s
        if b not in self.text_at:
            self.text_at[b] = len(self.pool)
            self.pool.extend(b)
        off = self.text_at[b]
        assert off < (1 << 23)
        return (off << 8) | len(b)

    def pattern_words(self, items):
        out = [len(items)]
        for item in items:
            if item[0] == "lit":
                out.append(self.text(item[1]))
            else:
                out.append(FIELD_FLAG | (ord(item[1]) << 8) | item[2])
        return out

    def encode(self, kind, d):
        w = []
        if kind == "month":
            if d == "Numeric":
                w = [0]
            elif "Linear" in d:
                assert len(d["Linear"]) == 12
                w = [1] + [self.text(s) for s in d["Linear"]]
            elif "LeapLinear" in d:
                assert len(d["LeapLinear"]) == 24
                w = [2] + [self.text(s) for s in d["LeapLinear"]]
            elif "LeapNumeric" in d:
                w = [3] + self.pattern_words(single_placeholder_items(d["LeapNumeric"]))
            elif "LeapNumericWithBase" in d:
                w = [4]
                for entry in d["LeapNumericWithBase"]:
                    w += [entry["sized"] & 0xFFFFFFFF] + self.pattern_words(single_placeholder_items(entry["variable"]))
            else:
                raise SystemExit(f"Unknown month names {d}")
        elif kind == "year":
            if "FixedEras" in d:
                w = [0, len(d["FixedEras"])] + [self.text(s) for s in d["FixedEras"]]
            elif "VariableEras" in d:
                codes, names = d["VariableEras"]
                assert codes == sorted(codes)
                w = [1, len(codes)] + [self.text(s) for s in codes] + [self.text(s) for s in names]
            elif "Cyclic" in d:
                w = [2, len(d["Cyclic"])] + [self.text(s) for s in d["Cyclic"]]
            else:
                raise SystemExit(f"Unknown year names {d}")
        elif kind == "list":
            w = [len(d["names"])] + [self.text(s) for s in d["names"]]
        elif kind == "packed":
            q = d.get("has_one_pattern_per_variant", False)
            header = (1 if d.get("has_explicit_medium") else 0) | (2 if d.get("has_explicit_short") else 0)
            if q:
                header |= 4
            else:
                for i, chunk in enumerate(d.get("variant_pattern_indices", [0] * 6)):
                    assert 0 <= chunk <= 7
                    header |= chunk << (3 + 3 * i)
            patterns = [self.pattern_words(parse_pattern(p)) for p in d["elements"]]
            w = [header, len(patterns)]
            offsets_at = len(w)
            w += [0] * len(patterns)
            for i, p in enumerate(patterns):
                w[offsets_at + i] = len(w)
                w += p
        elif kind == "glue":
            w = self.pattern_words(parse_placeholder_pattern(d["pattern"]))
        elif kind == "eras":
            eras = d["dates_to_eras"]
            w = [len(eras)]
            for start, code in eras:
                w += [start["year"] & 0xFFFFFFFF, start["month"], start["day"], self.text(code)]
        elif kind == "symbols":
            s, g = d["strings"], d["grouping_sizes"]
            w = [self.text(s[k]) for k in ["minus_sign_prefix", "minus_sign_suffix", "plus_sign_prefix", "plus_sign_suffix", "decimal_separator", "grouping_separator", "numsys"]]
            w += [g["primary"], g["secondary"], g["min_grouping"]]
        elif kind == "digits":
            assert len(d) == 10
            w = [self.text(s) for s in d]
        else:
            raise SystemExit(kind)
        return w

    def add_value(self, kind, d):
        """Stores a value once and returns its index."""
        canonical = json.dumps(d, sort_keys=True, ensure_ascii=False)
        if canonical not in self.value_index:
            self.value_index[canonical] = len(self.value_starts)
            self.value_starts.append(len(self.words))
            self.words.extend(self.encode(kind, d))
        return self.value_index[canonical]


def read_marker(fs, marker):
    """All entries of a marker: {(locale, attribute): JSON value}."""
    path, kind, layout = MARKERS[marker]
    base = os.path.join(fs, path)
    entries = {}
    if layout == "singleton":
        entries[("und", "")] = json.load(open(base + ".json", encoding="utf-8"))
    elif layout == "locale":
        # The default entry has no attribute. A folder holds the entries for one numbering system (-u-nu-).
        for f in os.listdir(base):
            if f.endswith(".json"):
                entries[(f[:-5], "")] = json.load(open(os.path.join(base, f), encoding="utf-8"))
            else:
                for g in os.listdir(os.path.join(base, f)):
                    entries[(g[:-5], f)] = json.load(open(os.path.join(base, f, g), encoding="utf-8"))
    else:
        for attr in os.listdir(base):
            for f in os.listdir(os.path.join(base, attr)):
                entries[(f[:-5], attr)] = json.load(open(os.path.join(base, attr, f), encoding="utf-8"))
    return entries


def build(marker, entries):
    kind = MARKERS[marker][1]
    packer = Packer(marker)
    rows = []
    for (loc, attr), value in sorted(entries.items()):
        key = loc.encode() + bytes([SEPARATOR]) + attr.encode()
        rows.append((key, packer.add_value(kind, value)))
    rows.sort()
    keys = [packer.text(k.decode("utf-8")) for k, _ in rows]
    key_values = [v for _, v in rows]
    packer.value_starts.append(len(packer.words))
    assert len(packer.value_starts) < (1 << 16)
    return {"pool": bytes(packer.pool), "keys": keys, "keyValues": key_values, "valueStarts": packer.value_starts, "words": packer.words}


def table_bytes(t):
    return len(t["pool"]) + 4 * len(t["keys"]) + 2 * len(t["keyValues"]) + 4 * len(t["valueStarts"]) + 4 * len(t["words"])


# MARK: - Writing


def swift_array(values, width):
    return ", ".join(f"0x{v:0{width}X}" for v in values)


def write_swift(folder, marker, t, note):
    src = f"""// Generated by generator/generate.py. Do not edit.
// Marker: {marker}. {note}
// {len(t["keys"])} keys, {len(t["valueStarts"]) - 1} values, {len(t["words"])} words, {len(t["pool"])} bytes of text.
import DataMarkers
import DateTimeFormat

extension {marker}: @retroactive BakedDataMarker {{
    // Array literals, not InlineArray: .span on a static let InlineArray copies the whole array (RESULTS.md, "The copy of InlineArray").
    @usableFromInline static let pool: [UInt8] = [{swift_array(t["pool"], 2)}]
    @usableFromInline static let keys: [UInt32] = [{swift_array(t["keys"], 8)}]
    @usableFromInline static let keyValues: [UInt16] = [{swift_array(t["keyValues"], 4)}]
    @usableFromInline static let valueStarts: [UInt32] = [{swift_array(t["valueStarts"], 8)}]
    @usableFromInline static let words: [UInt32] = [{swift_array(t["words"], 8)}]

    @inlinable @inline(__always)
    public static func withTables<R>(_ body: (Span<UInt8>, Span<UInt32>, Span<UInt16>, Span<UInt32>, Span<UInt32>) -> R) -> R {{
        body(pool.span, keys.span, keyValues.span, valueStarts.span, words.span)
    }}
}}
"""
    open(os.path.join(folder, f"{marker}+Data.swift"), "w", encoding="utf-8").write(src)


def rust_name(marker):
    return re.sub(r"(?<!^)(?=[A-Z])", "_", marker).upper()


def rust_tables(marker, t, note):
    n = rust_name(marker)
    return f"""
// Marker: {marker}. {note}
static {n}_POOL: [u8; {len(t["pool"])}] = [{swift_array(t["pool"], 2)}];
static {n}_KEYS: [u32; {len(t["keys"])}] = [{swift_array(t["keys"], 8)}];
static {n}_KEY_VALUES: [u16; {len(t["keyValues"])}] = [{swift_array(t["keyValues"], 4)}];
static {n}_VALUE_STARTS: [u32; {len(t["valueStarts"])}] = [{swift_array(t["valueStarts"], 8)}];
static {n}_WORDS: [u32; {len(t["words"])}] = [{swift_array(t["words"], 8)}];
impl BakedDataMarker for {marker} {{
    const TABLES: BakedTables = BakedTables {{ pool: &{n}_POOL, keys: &{n}_KEYS, key_values: &{n}_KEY_VALUES, value_starts: &{n}_VALUE_STARTS, words: &{n}_WORDS }};
}}
"""


def write_conformances(folder, present):
    lines = ["// Generated by generator/generate.py. Do not edit.", "// The calendars and field sets whose markers are all in this data (DESIGN.md, decision 10).", "import DataMarkers", "import DateTimeFormat", ""]
    rust = ["", "// The calendars and field sets whose markers are all in this data (DESIGN.md, decision 10)."]
    for cal, ms in CALENDAR_MARKERS.items():
        if all(m in present for m in ms):
            lines.append(f"extension {cal}: @retroactive BakedCalendar {{}}")
            rust.append(f"impl BakedCalendar for {cal} {{}}")
    if all(all(m in present for m in ms) for ms in CALENDAR_MARKERS.values()):
        lines.append("")
        lines.append("/// All 6 calendars, for AnyCalendarFormatter.")
        lines.append("public enum AllCalendars: CalendarSet {")
        for cal in CALENDARS:
            lines.append(f"    public typealias {cal}Calendar = {cal}")
        lines.append("}")
        lines.append("")
    for fs, ms in FIELD_SET_MARKERS.items():
        if all(m in present for m in ms):
            lines.append(f"extension {fs}: @retroactive BakedFieldSet {{}}")
            rust.append(f"impl BakedFieldSet for {fs} {{}}")
    open(os.path.join(folder, "Conformances.swift"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
    return "\n".join(rust) + "\n"


def pack_subtag(s):
    """Packs a subtag of up to 4 ASCII bytes into a UInt32, first byte lowest. 0 is no subtag."""
    if not s:
        return 0
    b = s.encode()
    assert len(b) <= 4, s
    return int.from_bytes(b.ljust(4, b"\0"), "little")


def write_fallback(fallback_folder, swift_path, rust_path):
    """The fallback tables of ICU4X (LocaleLikelySubtagsLanguageV1 and LocaleParentsV1) for the core modules."""
    fb = Fallback(fallback_folder)
    t = lambda *xs: tuple(pack_subtag(x) for x in xs)
    lang = sorted((t(l), t(*v)) for l, v in fb.language.items())
    lang_script = sorted((t(l, s), t(r)) for (l, s), r in fb.language_script.items())
    lang_region = sorted((t(l, r), t(s)) for (l, r), s in fb.language_region.items())
    parents = sorted((t(*Fallback.parse(k)[:3]), t(*v)) for k, v in fb.parents.items())
    tables = {
        "languageKeys": [k[0] for k, _ in lang], "languageScripts": [v[0] for _, v in lang], "languageRegions": [v[1] for _, v in lang],
        "languageScriptKeys": [x for k, _ in lang_script for x in k], "languageScriptRegions": [v[0] for _, v in lang_script],
        "languageRegionKeys": [x for k, _ in lang_region for x in k], "languageRegionScripts": [v[0] for _, v in lang_region],
        "parentKeys": [x for k, _ in parents for x in k], "parentValues": [x for _, v in parents for x in v],
    }
    swift = ["// Generated by generator/generate.py from LocaleLikelySubtagsLanguageV1 and LocaleParentsV1. Do not edit.", "// Each subtag is packed into a UInt32 (pack_subtag in generate.py). Keys are sorted. Array literals, not InlineArray (see the data files).", "", "enum FallbackTables {"]
    rust = ["// Generated by generator/generate.py from LocaleLikelySubtagsLanguageV1 and LocaleParentsV1. Do not edit.", "// Each subtag is packed into a u32 (pack_subtag in generate.py). Keys are sorted.", ""]
    for name, values in tables.items():
        swift.append(f"    static let {name}: [UInt32] = [{swift_array(values, 8)}]")
        rust.append(f"pub static {rust_name(name)}: [u32; {len(values)}] = [{swift_array(values, 8)}];")
    swift.append(f"    static let und: (UInt32, UInt32, UInt32) = (0x{pack_subtag(fb.und[0]):08X}, 0x{pack_subtag(fb.und[1]):08X}, 0x{pack_subtag(fb.und[2]):08X})")
    swift.append("}")
    rust.append(f"pub const UND: (u32, u32, u32) = (0x{pack_subtag(fb.und[0]):08X}, 0x{pack_subtag(fb.und[1]):08X}, 0x{pack_subtag(fb.und[2]):08X});")
    open(swift_path, "w", encoding="utf-8").write("\n".join(swift) + "\n")
    open(rust_path, "w", encoding="utf-8").write("\n".join(rust) + "\n")


def write_chinese_table(table_path, swift_path, rust_path):
    """The Chinese years 1900 to 2100 from icu4x-apps/chinese-table (DESIGN.md, decision 6).
    newYears: the rata die of each new year. info: the leap ordinal << 16, and bit i set if month i + 1 has 30 days."""
    rows = [line.split() for line in open(table_path) if line.strip()]
    first = int(rows[0][0])
    new_years, info = [], []
    for i, (year, new_year, leap, lengths, cyclic) in enumerate(rows):
        assert int(year) == first + i
        bits = sum(1 << j for j, n in enumerate(lengths.split(",")) if n == "30")
        assert len(lengths.split(",")) == (13 if int(leap) else 12)
        new_years.append(int(new_year))
        info.append((int(leap) << 16) | bits)
    last_day = new_years[-1] + sum(int(n) for n in rows[-1][3].split(",")) - 1
    swift = ["// Generated by generator/generate.py from cases/chinese-years.txt (icu4x-apps/chinese-table). Do not edit.", f"// The Chinese years {first} to {first + len(rows) - 1}. info: the leap ordinal << 16, and bit i set if month i + 1 has 30 days.", "",
             "@usableFromInline enum ChineseYears {", f"    @usableFromInline static let firstYear = {first}", f"    @usableFromInline static let lastDay = {last_day}",
             f"    @usableFromInline static let newYears: [Int32] = [{', '.join(str(x) for x in new_years)}]",
             f"    @usableFromInline static let info: [UInt32] = [{swift_array(info, 8)}]", "}"]
    rust = ["// Generated by generator/generate.py from cases/chinese-years.txt (icu4x-apps/chinese-table). Do not edit.", "",
            f"pub const FIRST_YEAR: i32 = {first};", f"pub const LAST_DAY: i64 = {last_day};",
            f"pub static NEW_YEARS: [i32; {len(rows)}] = [{', '.join(str(x) for x in new_years)}];",
            f"pub static INFO: [u32; {len(rows)}] = [{swift_array(info, 8)}];"]
    open(swift_path, "w", encoding="utf-8").write("\n".join(swift) + "\n")
    open(rust_path, "w", encoding="utf-8").write("\n".join(rust) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fs", required=True)
    ap.add_argument("--fallback", required=True)
    ap.add_argument("--out")
    ap.add_argument("--markers", default=",".join(MARKERS))
    ap.add_argument("--locales", default="all")
    ap.add_argument("--attributes", default="")
    ap.add_argument("--replace", action="store_true", help="write over the files of an earlier run in --out")
    ap.add_argument("--fallback-swift", help="also write the fallback tables for the Swift core module to this file")
    ap.add_argument("--fallback-rust", help="also write the fallback tables for the Rust copy to this file")
    ap.add_argument("--chinese-table", help="the output of icu4x-apps/chinese-table. Writes --chinese-swift and --chinese-rust.")
    ap.add_argument("--chinese-swift")
    ap.add_argument("--chinese-rust")
    args = ap.parse_args()
    if args.chinese_table:
        write_chinese_table(args.chinese_table, args.chinese_swift, args.chinese_rust)
        print(f"wrote {args.chinese_swift} and {args.chinese_rust}")
        if not args.out and not args.fallback_swift:
            return
    if args.fallback_swift:
        write_fallback(args.fallback, args.fallback_swift, args.fallback_rust)
        print(f"wrote {args.fallback_swift} and {args.fallback_rust}")
        if not args.out:
            return
    markers = [m for m in args.markers.split(",") if m]
    for m in markers:
        if m not in MARKERS:
            raise SystemExit(f"Unknown marker {m!r}. Known markers: {', '.join(MARKERS)}")
    fb = Fallback(args.fallback)
    keep_locales = None
    if args.locales != "all":
        keep_locales = set()
        for loc in args.locales.split(","):
            keep_locales.update(fb.chain(loc))
    attributes = set(a for a in args.attributes.split(",") if a)
    if os.path.exists(args.out) and os.listdir(args.out):
        if not args.replace:
            raise SystemExit(f"The output folder {args.out} is not empty. Use a new folder, or --replace.")
        others = set(os.listdir(args.out)) - {"swift", "rust", "markers.json", "stats.json"}
        if others:
            raise SystemExit(f"--replace: {args.out} has files that the generator did not write: {sorted(others)}")
    os.makedirs(os.path.join(args.out, "swift"), exist_ok=True)
    os.makedirs(os.path.join(args.out, "rust"), exist_ok=True)
    note = f"Locales: {args.locales}. Attributes: {','.join(sorted(attributes)) or 'all'}."
    registry, stats, rust = {}, {}, ["// Generated by generator/generate.py. Do not edit.", f"// {note}", "use crate::data_markers::{BakedDataMarker, BakedTables};", "use crate::format::*;"]
    for marker in markers:
        entries = read_marker(args.fs, marker)
        layout = MARKERS[marker][2]
        if keep_locales is not None and layout != "singleton" and layout != "digits":
            entries = {k: v for k, v in entries.items() if k[0] in keep_locales}
        if attributes and layout == "attr":
            entries = {k: v for k, v in entries.items() if k[1] in attributes}
        if layout == "digits" and keep_locales is not None:
            # Keep only the numbering systems of the kept decimal symbols.
            symbols = read_marker(args.fs, "DecimalSymbolsV1")
            numsys = {v["strings"]["numsys"] for (loc, _), v in symbols.items() if loc in keep_locales}
            entries = {k: v for k, v in entries.items() if k[1] in numsys}
        t = build(marker, entries)
        write_swift(os.path.join(args.out, "swift"), marker, t, note)
        rust.append(rust_tables(marker, t, note))
        registry[marker] = {"hash": fnv1a32(marker.encode()), "tag": marker_tag(marker).hex(" ")}
        stats[marker] = {"keys": len(t["keys"]), "values": len(t["valueStarts"]) - 1, "words": len(t["words"]), "pool_bytes": len(t["pool"]), "table_bytes": table_bytes(t)}
        print(f"{marker}: {len(t['keys'])} keys, {len(t['valueStarts']) - 1} values, {table_bytes(t)} bytes of tables")
    rust.append(write_conformances(os.path.join(args.out, "swift"), set(markers)))
    open(os.path.join(args.out, "rust", "data.rs"), "w", encoding="utf-8").write("\n".join(rust))
    json.dump({"tag": TAG.decode(), "markers": registry}, open(os.path.join(args.out, "markers.json"), "w"), indent=1)
    json.dump(stats, open(os.path.join(args.out, "stats.json"), "w"), indent=1)
    print(f"total: {sum(s['table_bytes'] for s in stats.values())} bytes of tables")


if __name__ == "__main__":
    main()
