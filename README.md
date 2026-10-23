# swift-data-markers-prototype

A work folder for one question: can Swift use the data architecture of ICU4X, where each kind of locale data is its own type ("marker"), so that the linker removes the data an app does not use?

Made on 2026-10-23. Dragan does all git work. The `.gitignore` keeps the large downloaded and rebuilt parts out of the repository (see "Rebuild after a fresh clone").

## Start here

1. Run `. ./env.sh` in a shell. It sets `RUSTUP_HOME`, `CARGO_HOME`, `PATH`, `TMPDIR`, and the paths `ICU4X_SRC`, `CLDR_ROOT` and `TZDB_ROOT`.
2. Read the results of the prototype: `prototype/PROTOTYPE-RESULTS.md`, then `prototype/DESIGN.md` and `prototype/QUICK_GUIDE.md`.
3. Read the background in `docs/`:
   * `DATA-SLICING.md`: how the date data of PR #2330 slices for a small Embedded Swift app.
   * `ICU4X-COMPARISON.md`: how #2330 compares with ICU4X.
   * `ICU4X-DATA-GUIDE.md`: a step by step guide to how ICU4X stores, finds and cuts its data, with the results of real runs.
   * `RESULTS.md`: the first Embedded Swift measurement of #2330, including why FoundationEssentials does not build in Embedded mode yet.

`docs/` is a copy of `/Users/draganm4/Projects/dra8an/Docs/pr-2330-deep-review/embedded-20261020/`, made on 2026-10-23, without the two `SWIFT-MARKERS-*` files (they are copies of files in `prototype/`) and without `scripts.zip` (a zip of `docs/scripts/`). If one of the two copies changes, copy it again.

## Rebuild after a fresh clone

The repository has the sources, the generated data, the results and the logs. These parts are not in it, and a rebuild needs them:

| Part | Where it goes | Source |
|---|---|---|
| Rust 1.99.1 | `docs/` | The background documents and their tools (see "Start here"). |
| `tools/rust/` | `rustup-init` from `https://static.rust-lang.org/rustup/dist/aarch64-apple-darwin/rustup-init`, run with `RUSTUP_HOME` and `CARGO_HOME` from `env.sh`, and `-y --no-modify-path --profile minimal --default-toolchain stable` |
| ICU4X | `tools/icu4x-src/` | `github.com/unicode-org/icu4x` at commit `747356078891d513c1f731320e3d0e1ee9912e33` |
| `icu4x-datagen` | `tools/bin/` | `cargo build --release -p icu4x-datagen` in `tools/icu4x-src`, once with and once without `--features unstable` |
| CLDR 49.0.0-BETA4 | `data/cldr-49.0.0-BETA4/` | `cldr-49.0.0-BETA4-json-full.zip` from the releases of `github.com/unicode-org/cldr-json`, unpacked into `full/` |
| tzdata 2026e | `data/tzdata-2026e/` | `https://www.iana.org/time-zones/repository/releases/tzdata2026e.tar.gz`, unpacked into `root/` |
| Embedded Swift | `/Library/Developer/Toolchains/` | `swift-DEVELOPMENT-SNAPSHOT-2026-06-24-a` from swift.org |
| Normal Swift | | the toolchain of Xcode 8 (Swift 6.5) |

The scripts use absolute paths to `/Users/draganm4/Projects/dra8an/swift-data-markers-prototype`. In a clone at another path, change `PROTO` in `env.sh` and the paths at the top of the scripts.

**Licenses.** The generated tables in `prototype/data/` and `icu4x-experiments/runs/` contain CLDR data, and `icu4x-experiments/guide-tools/decode.py` is a port of ICU4X code. Both are under the Unicode License. Add its notice before the repository becomes public.

## What is in this folder

| Folder | Content |
|---|---|
| `prototype/` | The Swift prototype, done on 2026-10-23. Start with `prototype/PROTOTYPE-RESULTS.md`, then `prototype/DESIGN.md`. `prototype/QUICK_GUIDE.md` compares Rust and Swift in four tables. `prototype/data/full-duplicate/` is a copy of `data/full` made by mistake, and it can be deleted. |
| `tools/rust/` | Rust 1.99.1 (stable, minimal profile), from `rustup-init` for `aarch64-apple-darwin`. The SHA-256 of `rustup-init` matched the published one. `cargo/registry` holds every crate that the builds below need, so they work with `--offline`. |
| `tools/bin/` | Two builds of `icu4x-datagen` from `tools/icu4x-src`: `icu4x-datagen` (default features) and `icu4x-datagen-unstable` (`--features unstable`, needed for some datetime markers). |
| `tools/icu4x-src/` | A shallow clone of `github.com/unicode-org/icu4x` at commit `747356078891d513c1f731320e3d0e1ee9912e33`. |
| `data/cldr-49.0.0-BETA4/` | The CLDR JSON data that this ICU4X commit is tested with: the zip from the `cldr-json` releases on GitHub, and the unpacked files in `full/`. Use `--cldr-root $CLDR_ROOT`. |
| `data/tzdata-2026e/` | The IANA time zone database, release 2026e: the archive, and the unpacked files in `root/`. Use `--tzdb-root $TZDB_ROOT`. |
| `icu4x-experiments/apps/` | Two Rust apps that print the wide Korean month names of the Japanese calendar. `app-a` uses the built-in data of ICU4X. `app-b` uses its own provider with generated data for one marker. `build.sh` builds them. |
| `icu4x-experiments/runs/` | The output and logs of `icu4x-datagen` runs. `ko-japanese-wide-sep/` is the data that `app-b` uses. `ko-app-a-markers-tz/` is the data for the 80 markers of `app-a`, used with `ICU4X_DATA_DIR`. `run6.sh` makes it. |
| `icu4x-experiments/guide-tools/` | `decode.py`: a Python port of the ICU4X reader code. It decodes a `.rs.data` file. |

`copy.sh` and `copy.log` record how this folder was filled from `/tmp/deep-review/`. The originals in `/tmp/deep-review/` were left in place. macOS removes them on its own.

`icu4x-experiments/apps-src-tmp/` is an empty folder that was left by the copy. It can be deleted.

## Examples

```
. ./env.sh

# Generate the wide Korean month names of the Japanese calendar
icu4x-datagen-unstable --cldr-root $CLDR_ROOT --markers DatetimeNamesMonthJapaneseV1 --locales ko \
  --attribute-filter datetime_month_length=/5/ --format baked --use-separate-crates --out /some/new/folder

# Build and run app B with that data
cd icu4x-experiments/apps/app-b
APP_B_DATA=/some/new/folder/mod.rs cargo build --release --offline
LOCALE=ko target/release/app-b      # prints 9월

# Decode a data file
python3 -I icu4x-experiments/guide-tools/decode.py /some/new/folder/datetime_names_month_japanese_v1.rs.data ko/5
```

## Notes

1. `icu4x-datagen` cannot download through the sandbox proxy. Always pass `--cldr-root` and, for time zone data, `--tzdb-root`.
2. `--pretty` needs the `rustfmt` component, which is not installed. Leave it out.
3. `icu4x-datagen` does not write into an output folder that is not empty. Use a new folder.
4. The builds work with `--offline`. The domains `sh.rustup.rs`, `static.rust-lang.org`, `index.crates.io` and `static.crates.io` are only needed for new crates or a new toolchain.
