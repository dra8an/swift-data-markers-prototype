"""Measures the apps of the prototype: sizes, the marker tags in each binary, and the marker tables in its symbols.

Usage: python3 -I measure.py <markers.json> <binary> [<binary> ...]
"""
import json
import re
import subprocess
import sys


def sections(binary):
    out = subprocess.run(["size", "-m", binary], capture_output=True, text=True).stdout
    code = const = other = 0
    segment = ""
    for line in out.splitlines():
        m = re.match(r"\s*Segment (\S+):", line)
        if m:
            segment = m.group(1)
            continue
        m = re.match(r"\s*Section (\S+): (\d+)", line)
        if m and segment != "__LINKEDIT":
            name, n = m.group(1), int(m.group(2))
            if name == "__text":
                code += n
            elif name == "__const":
                const += n
            else:
                other += n
    return code, const, other


def tags(binary, registry):
    by_hash = {bytes.fromhex(v["tag"].replace(" ", ""))[4:]: k for k, v in registry["markers"].items()}
    data = open(binary, "rb").read()
    found, i = [], 0
    tag = registry["tag"].encode()
    while True:
        i = data.find(tag, i)
        if i < 0:
            break
        found.append(by_hash.get(data[i + 4:i + 8], "unknown " + data[i + 4:i + 8].hex()))
        i += 4
    return found


def table_symbols(binary, registry):
    out = subprocess.run(["xcrun", "nm", "-m", binary], capture_output=True, text=True).stdout
    demangled = subprocess.run(["xcrun", "swift-demangle", "--simplified"], input=out, capture_output=True, text=True).stdout
    present = {}
    for marker in registry["markers"]:
        present[marker] = sorted(set(re.findall(rf"static {marker}\.(pool|keys|keyLists|listStarts|names)\b", demangled)))
    return present


def main():
    registry = json.load(open(sys.argv[1]))
    for binary in sys.argv[2:]:
        code, const, other = sections(binary)
        found = tags(binary, registry)
        symbols = table_symbols(binary, registry)
        name = "/".join(binary.split("/")[-2:])
        print(f"{name}")
        print(f"  code {code}  const {const}  other {other}  total {code + const + other}")
        print(f"  tags: {', '.join(found) if found else 'none'}")
        print(f"  table symbols: " + "; ".join(f"{m}: {','.join(s) if s else '-'}" for m, s in symbols.items()))


if __name__ == "__main__":
    main()
