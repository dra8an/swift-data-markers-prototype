"""Measures the size apps (DESIGN.md, decision 9): sizes by section, and the markers whose data is in each binary.

Usage: python3 -I -B measure.py <markers.json> <binary> [<binary> ...]
Code is __text. Data is every __const section (in __TEXT and in __DATA_CONST). Other is every other section except __LINKEDIT.
Markers: the tags dmk1 of the Swift and Rust copy data. For ICU4X binaries, use icu4x-datagen --markers-for-bin instead.
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
    found, i = set(), 0
    tag = registry["tag"].encode()
    while True:
        i = data.find(tag, i)
        if i < 0:
            break
        name = by_hash.get(data[i + 4:i + 8])
        if name:
            found.add(name)
        i += 4
    return sorted(found)


def main():
    registry = json.load(open(sys.argv[1]))
    print("binary\tcode\tdata\tother\ttotal\tmarkers\tmarker names")
    for binary in sys.argv[2:]:
        code, const, other = sections(binary)
        found = tags(binary, registry)
        name = "/".join(binary.split("/")[-2:])
        print(f"{name}\t{code}\t{const}\t{other}\t{code + const + other}\t{len(found)}\t{','.join(found)}")


if __name__ == "__main__":
    main()
