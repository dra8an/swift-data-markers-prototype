"""Decodes an ICU4X baked data file (.rs.data): the ZeroTrieSimpleAscii lookup table and the MonthNames values.

The trie code is a line-by-line port of utils/zerotrie/src/reader.rs and varint.rs at ICU4X commit 7473560788.
Usage: python3 -I decode.py <file.rs.data> [key ...]   (a key is written as locale/attribute, for example ko/5)
"""
import sys


# --- utils/zerotrie/src/varint.rs ---
def read_varint_meta2(start, rest, pos):
    value = start & 0b00011111
    if start & 0b00100000:
        while True:
            nxt = rest[pos]; pos += 1
            value = (value << 7) + (nxt & 0b01111111) + 32
            if not nxt & 0b10000000:
                break
    return value, pos


def read_varint_meta3(start, rest, pos):
    value = start & 0b00001111
    if start & 0b00010000:
        while True:
            nxt = rest[pos]; pos += 1
            value = (value << 7) + (nxt & 0b01111111) + 16
            if not nxt & 0b10000000:
                break
    return value, pos


# --- utils/zerotrie/src/reader.rs ---
def byte_type(b):
    top = b & 0b11100000
    if top == 0b10000000: return "value"
    if top == 0b10100000: return "span"
    if top in (0b11000000, 0b11100000): return "branch"
    return "ascii"


def branch_slice(trie, pos, end, i, n, w):
    # get_branch: offset table of n - 1 entries per byte of width, high bytes first
    p = q = 0
    for _ in range(w + 1):
        indices = trie[pos:pos + n - 1]; pos += n - 1
        p = (p << 8) + (0 if i == 0 else indices[i - 1])
        q = (q << 8) + indices[i] if i < len(indices) else None
    rest_len = end - pos
    if q is None:
        q = rest_len
    return pos + p, pos + q


def read_node(trie, pos):
    b = trie[pos]; pos += 1
    t = byte_type(b)
    if t == "value":
        x, pos = read_varint_meta3(b, trie, pos)
    elif t == "branch":
        x, pos = read_varint_meta2(b, trie, pos)
    elif t == "span":
        raise ValueError("span node in an ASCII trie")
    else:
        x = 0
    return b, t, x, pos


def get(trie, key, pos=0, end=None):
    """Port of get_parameterized for ZeroTrieSimpleAscii (binary search branches only)."""
    end = len(trie) if end is None else end
    key = bytes(key)
    while pos < end:
        b, t, x, pos = read_node(trie, pos)
        if key:
            c = key[0]
            if t == "ascii":
                if b != c:
                    return None
                key = key[1:]
                continue
            if t == "value":
                continue
            n, w = (x & 0xFF, x >> 8) if x >= 256 else (x, 0)
            n = 256 if n == 0 else n
            search = trie[pos:pos + n]; pos += n
            if c not in search:
                return None
            i = search.index(c)
            pos, end = branch_slice(trie, pos, end, i, n, w & 0x3)
            key = key[1:]
            continue
        return x if t == "value" else None
    return None


def entries(trie, pos=0, end=None, prefix=b""):
    """All (key, value) pairs, by walking every node (the same walk as get, for every branch edge)."""
    end = len(trie) if end is None else end
    out = []
    while pos < end:
        b, t, x, pos = read_node(trie, pos)
        if t == "ascii":
            prefix += bytes([b])
        elif t == "value":
            out.append((prefix, x))
        else:
            n, w = (x & 0xFF, x >> 8) if x >= 256 else (x, 0)
            n = 256 if n == 0 else n
            search = trie[pos:pos + n]; pos += n
            for i, c in enumerate(search):
                s, e = branch_slice(trie, pos, end, i, n, w & 0x3)
                out += entries(trie, s, e, prefix + bytes([c]))
            return out
    return out


# --- utils/zerovec VarZeroVec16: u16 length, then (length - 1) u16 start offsets, then the UTF-8 text ---
def varzerovec16(data):
    if not data:
        return []
    n = int.from_bytes(data[0:2], "little")
    starts = [0] + [int.from_bytes(data[2 + 2 * k:4 + 2 * k], "little") for k in range(n - 1)]
    things = data[2 + 2 * (n - 1):]
    ends = starts[1:] + [len(things)]
    return [things[s:e].decode("utf-8") for s, e in zip(starts, ends)]


# --- reading the .rs.data file ---
def rust_bytes(text, start):
    """Parses the Rust byte string literal b"..." that starts at text[start] == 'b'."""
    assert text[start:start + 2] == 'b"'
    i = start + 2; out = bytearray()
    simple = {"n": 10, "r": 13, "t": 9, "0": 0, "\\": 92, '"': 34, "'": 39}
    while text[i] != '"':
        ch = text[i]
        if ch == "\\":
            nxt = text[i + 1]
            if nxt == "x":
                out.append(int(text[i + 2:i + 4], 16)); i += 4; continue
            out.append(simple[nxt]); i += 2; continue
        out += ch.encode("utf-8"); i += 1
    return bytes(out), i + 1


def top_level_items(text, start):
    """Splits the Rust slice literal &[ ... ] that starts at text[start] == '[' into its top-level items."""
    depth = 0; i = start; items = []; cur = start + 1
    while True:
        ch = text[i]
        if ch == "b" and text[i + 1] == '"':
            _, i = rust_bytes(text, i); continue
        if ch in "([{": depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                items.append(text[cur:i].strip()); return [x for x in items if x]
        elif ch == "," and depth == 1:
            items.append(text[cur:i].strip()); cur = i + 1
        i += 1


def load(path):
    import re
    text = open(path, encoding="utf-8").read()
    # The files of ICU4X are formatted (store: b"..."). Files written without --pretty have spaces between tokens (store : b"...").
    trie, _ = rust_bytes(text, re.search(r'store\s*:\s*b"', text).end() - 2)
    vstart = re.search(r"const\s+VALUES", text).start()
    values = top_level_items(text, re.compile(r"=\s*&\s*\[").search(text, vstart).end() - 1)
    decoded = []
    for item in values:
        variant = item.split("(")[0].split("::")[-1].strip()
        if 'b"' in item:
            raw, _ = rust_bytes(item, item.index('b"'))
            decoded.append((variant, varzerovec16(raw) if variant == "Linear" else raw))
        else:
            decoded.append((variant, None))
    return text, trie, decoded


def self_test():
    example = bytes([0b10000000, 0b11000010, ord("a"), ord("b"), 13, 0b11000011, ord("x"), ord("y"), ord("z"), 3, 5,
                     ord("b"), 0b10010000, 0x54, ord("c"), 0b10000010, ord("d"), 0b10000011, ord("x"), ord("e"), 0b10000100,
                     0b11000010, ord("f"), ord("i"), 7, 0b11000010, ord("g"), ord("h"), 2, 0b10010011, 0x64, 0b10000110,
                     0b10000111, ord("k"), ord("l"), 0b10001000])
    expected = {b"": 0, b"axb": 100, b"ayc": 2, b"azd": 3, b"bxe": 4, b"bxefg": 500, b"bxefh": 6, b"bxei": 7, b"bxeikl": 8}
    for k, v in expected.items():
        assert get(example, k) == v, (k, get(example, k), v)
    assert dict(entries(example)) == expected, entries(example)
    for k in [b"a", b"b", b"axc", b"bxeik"]:
        assert get(example, k) is None, k
    print("self test: the port gives the 9 values and the 4 misses of the example in reader.rs")


if __name__ == "__main__":
    self_test()
    if len(sys.argv) > 1:
        text, trie, values = load(sys.argv[1])
        all_entries = entries(trie)
        print(f"trie: {len(trie)} bytes, {len(all_entries)} keys; values: {len(values)} entries")
        bad = [k for k, v in all_entries if get(trie, k) != v]
        print(f"every key found again by get(): {not bad}")
        for arg in sys.argv[2:]:
            loc, _, attr = arg.partition("/")
            key = loc.encode() + (b"\x1e" + attr.encode() if attr else b"")
            idx = get(trie, key)
            print(f"{arg!r:12} key {key!r:18} -> index {idx} -> {values[idx] if idx is not None else 'not in the table'}")


def trace(trie, key):
    """Like get(), but prints every node it reads, with its position in the store."""
    pos, end, key = 0, len(trie), bytes(key)
    while pos < end:
        at = pos
        b, t, x, pos = read_node(trie, pos)
        if key and t == "ascii":
            print(f"  byte {at:5}: 0x{b:02X} ASCII '{chr(b)}'  matches '{chr(key[0])}'" if b == key[0] else f"  byte {at:5}: ASCII mismatch"); key = key[1:]; continue
        if key and t == "value":
            print(f"  byte {at:5}: 0x{b:02X} value {x} for a shorter key, skipped"); continue
        if key and t == "branch":
            n, w = (x & 0xFF, x >> 8) if x >= 256 else (x, 0)
            n = 256 if n == 0 else n
            search = trie[pos:pos + n]
            i = search.index(key[0])
            s, e = branch_slice(trie, pos + n, end, i, n, w & 0x3)
            shown = "".join(chr(c) if 32 <= c < 127 else f"\\x{c:02x}" for c in search)
            edge = chr(key[0]) if key[0] >= 32 else "0x1E"
            print(f"  byte {at:5}: 0x{b:02X} branch of {n} bytes '{shown[:60]}', width {w}; '{edge}' is edge {i}, jump to bytes {s}..{e}")
            pos, end, key = s, e, key[1:]; continue
        print(f"  byte {at:5}: 0x{b:02X} value {x}  <- the result" if t == "value" else f"  byte {at:5}: no match"); return
