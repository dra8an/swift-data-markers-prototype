# Internal notes

Notes for the people who work in this repository. They are not needed to understand or to rebuild the prototypes. The main documentation starts in `README.md`.

## Work rules

* Dragan does all git work: commits, pushes and branches.
* The repository has its own `.git/config`, with `commit.gpgsign false` and the identity `dra8an <chonbey@hotmail.com>`. The global `~/.gitconfig` signs with another tool and must not change.

## The Mac where the prototypes were made

* The folder is `/Users/draganm4/Projects/dra8an/swift-data-markers-prototype`. The scripts and the `Cargo.toml` files use this absolute path (see `README.md`, "Paths").
* The work ran in a sandbox:
  * `icu4x-datagen` could not download through the sandbox proxy. So the commands always pass `--cldr-root` and, for time zone data, `--tzdb-root`.
  * Only the domains `sh.rustup.rs`, `static.rust-lang.org`, `index.crates.io` and `static.crates.io` were open, and only for the first setup. The builds work with `cargo --offline`.
  * Deletes were not allowed. So the generator writes over its own output only with `--replace`, and the leftovers below are still there.
  * SwiftPM needed `--disable-sandbox`, and Python ran with `-I -B`.
* `--pretty` of `icu4x-datagen` needs the `rustfmt` component, which is not installed.

## Where the files came from

* `copy.sh` and `copy.log` record how this folder was filled from `/tmp/deep-review/` on 2026-10-23. The originals there were left in place, and macOS removes them on its own.
* `docs/` is a copy of `/Users/draganm4/Projects/dra8an/Docs/pr-2330-deep-review/embedded-20261020/`, made on 2026-10-23, without the two `SWIFT-MARKERS-*` files (copies of files in `prototype/`) and without `scripts.zip` (a zip of `docs/scripts/`). If one of the two copies changes, copy it again.

## Decide before you share the repository

* `docs/` has notes from our review of PR #2330 in swift-foundation (by Chris Chapman). Decide if they belong in a shared repository.
* Add the license notices of `README.md`, "Licenses".

## Leftovers that can be deleted

| Path | What it is |
|---|---|
| `prototype/data/full-duplicate/` | A copy of `prototype/data/full`, made by mistake |
| `icu4x-experiments/apps-src-tmp/` | An empty folder, left by the copy |
| `prototype-large/explore/` | Scratch runs (122 MB) |
| `prototype-large/generator/__pycache__/` | Made by one test import |
| `prototype-large/data/cut-fr-chinese/`, `prototype-large/data/cut-fr-all/` | Two cuts made to answer questions on 2026-10-23 |
| `prototype-large/icu4x-apps/*/target/`, `prototype-large/rust-copy/target/`, `prototype-large/out/` | Build output |

## Open items

* The Embedded Swift snapshot crashes with `-O` (`prototype-large/RESULTS.md`, "Open problems"). No small reproduction yet. It could be worth a report to the Swift project.
* Check if PR #2330 takes `.span` of its `static let` `InlineArray` tables (`prototype-large/RESULTS.md`, "The copy of InlineArray").
