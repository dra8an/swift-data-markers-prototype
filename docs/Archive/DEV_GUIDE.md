# Developer guide: from CLDR to an app with only the data it needs

> **Archived on 2026-10-28. Superseded by [`FOUNDATION-DATA-ARCHITECTURE-PLAN.md`](../FOUNDATION-DATA-ARCHITECTURE-PLAN.md).** Its steps 5 to 7 follow the rejected design of `DESIGN-DATA-KINDS.md`. Kept for the record only.

**Status:** a design, 2026-10-26. Steps 1 to 4 exist today for list data and date data, in Christopher Chapman's tools (`utils/update-list-format-data` and `utils/build-list-format-data` from PR #1991, and the date data tools of the open PR #2330). This guide uses general names for them (`update-locale-data`, `build-locale-data`), which would cover every kind of data. Steps 5 to 7 are proposed and not built. The design behind these steps is in `DESIGN-DATA-KINDS.md`.

**The example:** an app that formats Gregorian dates and lists, in French and German.

## A. The Foundation team, once for each CLDR release

1. **Get CLDR.** Download the CLDR release and point `CLDR_PATH` to it.
2. **Make the intermediate data.** Run `utils/update-locale-data`. For each kind of data in the registry `utils/data-kinds.json`, the tool:
   * reads CLDR,
   * resolves the inheritance, so that every locale has a complete entry,
   * stores identical values once,
   * writes one JSON file for each kind, with all locales, into `Sources/_FoundationInternationalizationData/JSON/`.
3. **Make the full tables.** Run `utils/build-locale-data` with no options. It writes:
   * the Swift tables for all kinds and all locales, into `Generated/`,
   * the marker types, into `Markers.swift`,
   * the versions, into `DataVersion.json`.

   It also checks that the table of every locale matches the CLDR resolution of that locale.
4. **Review and commit.** The JSON files and the full tables go into the repository, and they ship with Foundation.

## B. The app developer, once

5. **Choose the settings,** in the package of the app, in plain words:
   * `locales`: `fr`, `de` (or the `.lproj` folders of the app),
   * `features`: `dates`, `lists`,
   * `calendars`: `gregorian`.

## C. Every build of the app (automatic)

6. **Cut the data.** A build plugin runs `build-locale-data` with these settings, on the JSON files of step 4. It keeps:
   * the kinds of the chosen features, and the kinds that they need (for example digits and plural rules),
   * only the Gregorian kinds,
   * only the rows of `fr`, `de` and the root, and only the values that these rows use.

   It writes the cut tables into the build folder, not into the repository.
7. **Compile and link.** The compiler builds Foundation with the cut tables. Then the linker removes the code and the tables of every feature that the app never calls. This needs a build that puts Foundation into the app (Embedded Swift, WASM, static Linux), and the 3 linker flags in normal Swift (`-Xfrontend -internalize-at-link -Xfrontend -conditional-runtime-records -lto=llvm-full`).

## D. When the app runs

8. **Make a formatter,** for example a date format style for `fr_CA`. Foundation resolves the locale once: `fr_CA` is not in the data, so Foundation follows the redirect or drops the region, and finds `fr`.
9. **Format.** The month name comes directly from the `fr` row of the Gregorian month names table. There is no further lookup.
10. **A locale that was cut,** for example `ja`, resolves to the root data. The app shows root text, such as `M10`, and gives no error.

## On Apple platforms

Steps 5 to 7 do not apply. All apps share one Foundation, which keeps the full data of step 4.
