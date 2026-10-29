# Scripts and raw data of the ICU data inventory

These files support part 1 of `docs/FOUNDATION-DATA-ARCHITECTURE-PLAN.md` (2026-10-27 and 2026-10-28).

| File | What it is |
|---|---|
| `toc.py` | Reads the ICU data array of swift-foundation-icu and prints its size by category. Writes `icudt.dat` and `items.tsv`. |
| `items.tsv` | The size and name of each of the 4,855 items of the ICU 76 data (swift-foundation-icu `e8538d2593`). |
| `cnv.c` | Resolves encoding names to ICU converters with the system ICU of macOS. |
| `icu-call-map.sh` | Prints each ICU function family with the files and functions that call it. |
| `swift-foundation-icu-call-map.tsv` | The output of `icu-call-map.sh` on swift-foundation `main` `bfbded0f70` (`Sources/`). |
| `darwin-icu-calls.txt` | Every ICU call in the Darwin Foundation checkout `1e2ed46155`, with file and line. ICU's own source (in `.build/`), tests, benchmarks and fuzzing are left out. |
| `darwin-icu-family-files.tsv` | The ICU families of `darwin-icu-calls.txt`, with the files that call them. |

## How to run them again

1. Get swift-foundation-icu. A `swift build` of swift-foundation puts it in `.build/checkouts/swift-foundation-icu/`.
2. Run `python3 -I -B toc.py <swift-foundation-icu>/icuSources/common <output folder>`. It takes about 1 minute. The output is about 34 MB.
3. Build `cnv.c` with `clang -w cnv.c -licucore -o cnv`, and run it with the encoding names from the comment at the top of the file.
4. Run `icu-call-map.sh <swift-foundation>/Sources` for the call map.

## The checks behind section 1.5 of the plan (unused data)

These checks read ICU's source in swift-foundation-icu (`icuSources/`):
* Break iterators in formatting: `i18n/smpdtfmt.cpp`, `i18n/reldatefmt.cpp`, `i18n/reldtfmt.cpp` create them. `common/ustr_titlecase_brkiter.cpp` makes a word break iterator for titlecasing when the caller gives none.
* `capitalized(with:)` calls `ucasemap_utf8ToTitle` with no break iterator (`Sources/FoundationInternationalization/ICU/ICU+CaseMap.swift`, lines 29 and 89).
* Spellout rules from numbering systems: `i18n/smpdtfmt.cpp` and `i18n/numfmt.cpp` use `RuleBasedNumberFormat`.
* ISO-2022-JP: `common/ucnv2022.cpp` loads `Shift-JIS` for version 0 (line 516). It loads `jisx-212` only for a higher version (line 519). Foundation opens version 0.
* CoreFoundation builds converter names from its encoding database at run time (`CoreFoundation/StringEncodings.subproj/CFICUConverters.c`), so a text search does not find them.
