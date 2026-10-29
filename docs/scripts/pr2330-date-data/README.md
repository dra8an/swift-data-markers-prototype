# Scripts of the PR #2330 date data study

These files support `docs/FOUNDATION-DATE-DATA-ARCHITECTURE.md` (2026-10-27).

| File | What it is |
|---|---|
| `make-cuts.sh` | Builds the date tables for 6 locale cuts with the PR's own build tool. |
| `make-cuts.log` | Its output on 2026-10-28. It reproduces the numbers of 2026-10-27. |
| `compile-and-size.sh` | Compiles the date data files into one object per cut, and prints `size -m`. |
| `compile-and-size.log` | Its output on 2026-10-27. |
| `group-share.py` | Estimates the share of each data group (months, weekdays and so on). |

## How to run them again

1. Get the PR files at `80ebeafa3d`, for example with `gh api "repos/swiftlang/swift-foundation/contents/<path>?ref=80ebeafa3def9f54975c24a70aa889eae5d37af6" -H "Accept: application/vnd.github.raw"` for each file of `gh pr view 2330 --json files`.
2. Run `make-cuts.sh <PR folder> <output folder>`.
3. Edit the paths at the top of `compile-and-size.sh`, then run it. It needs `-package-name`, because the lookup uses `package` access.

## The first layout of the PR (the 352 KB)

The PR text gives the size of the first commit `9dda818323`. To measure it, get `DateFormatData.swift` and `DateFormatLookup.swift` at that commit, then compile them as in `compile-and-size.sh` (there is no `DataLocaleIdentifier.swift` at that commit):

```
swiftc -O -wmo -parse-as-library -module-name DFData -package-name FoundationData -D FOUNDATION_DATE_FORMAT_SWIFT -enable-experimental-feature Lifetimes -c DateFormatData.swift DateFormatLookup.swift -o old.o
size -m old.o
```

Result on 2026-10-27: `__TEXT,__const` 326,064, total 352,208.
