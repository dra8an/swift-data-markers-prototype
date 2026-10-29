# Estimates the share of each data group in the PR #2330 date data (all locales).
# Usage: python3 -I -B group-share.py <PR 2330 files at 80ebeafa3d>/Sources/_FoundationInternationalizationData/DateFormatData.json
# The estimate counts the 4 byte entries of the distinct sub-blocks of each group, and the text longer than 3 bytes,
# before the pool shares text across groups. Result on 2026-10-27: months 43%, weekdays 28%, quarters 15%, eras 8%, dayPeriods 5%, the rest 2%.
import json, sys
d = json.load(open(sys.argv[1]))
size = {"numbers": 7, "months": 12, "weekdays": 7, "quarters": 4, "eras": 2, "dayPeriods": 3, "gmt": 2, "capitalization": 10}
tot = 0
res = {}
for g, s in size.items():
    subs = set()
    text = set()
    for blk in d['groupBlocks'][g]:
        for i in range(0, len(blk), s):
            sb = tuple(blk[i:i + s])
            subs.add(sb)
            for v in sb:
                if v and len(v.encode()) > 3:
                    text.add(v)
    entries = len(subs) * s * 4
    tb = sum(len(t.encode()) for t in text)
    res[g] = (len(subs), entries, tb)
    tot += entries + tb
for g, (n, e, t) in res.items():
    print(f"{g:15} sub-blocks {n:5}  entries {e:6} B  long text {t:6} B  share {100 * (e + t) / tot:4.1f}%")
print("sum", tot, "B")
