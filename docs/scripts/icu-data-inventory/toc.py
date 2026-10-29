# Reads the ICU data array of swift-foundation-icu and prints its size by category.
# Usage: python3 -I -B toc.py <swift-foundation-icu>/icuSources/common <output folder>
# Writes <output folder>/icudt.dat (the data as bytes, about 34 MB) and <output folder>/items.tsv (size and name of each item).
# Used on swift-foundation-icu e8538d2593 (ICU 76): 33,976,096 bytes, 4,855 items.
import re, struct, collections, sys, os
src, out = sys.argv[1], sys.argv[2]
b = bytearray()
for i in range(4):
    text = open(os.path.join(src, 'icu_packaged_main_data.%d.inc.h' % i)).read()
    b += bytes(int(x, 16) for x in re.findall(r'0x([0-9a-fA-F]{1,2})', text))
open(os.path.join(out, 'icudt.dat'), 'wb').write(b)
# ICU common data format: a header, then the table of contents (count, then name offset and data offset per item).
hs = struct.unpack_from('<H', b, 0)[0]
count = struct.unpack_from('<I', b, hs)[0]
ents = [struct.unpack_from('<II', b, hs + 4 + 8 * i) for i in range(count)]
names = []
for no, do in ents:
    s = hs + no
    e = b.index(0, s)
    names.append((b[s:e].decode(), hs + do))
items = []
for i, (n, o) in enumerate(names):
    end = names[i + 1][1] if i + 1 < len(names) else len(b)
    items.append((n, end - o))
pre = items[0][0].split('/')[0]
print('total', len(b), 'items', count, 'prefix', pre)
cat = collections.Counter()
cnt = collections.Counter()
for n, s in items:
    rest = n[len(pre) + 1:]
    parts = rest.split('/')
    k = parts[0] + '/' if len(parts) > 1 else ('locale data (root level *.res)' if rest.endswith('.res') else 'root level ' + rest.rsplit('.', 1)[-1])
    cat[k] += s
    cnt[k] += 1
for k, s in cat.most_common():
    print(f"{s:>10}  {cnt[k]:5}  {k}")
open(os.path.join(out, 'items.tsv'), 'w').write('\n'.join(f"{s}\t{n}" for n, s in items))
