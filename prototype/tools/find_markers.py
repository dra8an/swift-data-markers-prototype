"""Lists the markers used by a built app, like --markers-for-bin of icu4x-datagen.

It searches the binary for the tag "dmk1", reads the 4 bytes of hash after it, and maps the hash to a marker name with markers.json.
It finds a marker only if the data of that marker is still in the binary, so it is right only when the build removed unused markers.
Usage: python3 -I find_markers.py <markers.json> <binary>   (prints a comma-separated list for generate.py --markers)
"""
import json
import sys

registry = json.load(open(sys.argv[1]))
by_hash = {bytes.fromhex(v["tag"].replace(" ", ""))[4:]: k for k, v in registry["markers"].items()}
data = open(sys.argv[2], "rb").read()
tag = registry["tag"].encode()
found, i = set(), 0
while (i := data.find(tag, i)) >= 0:
    name = by_hash.get(data[i + 4:i + 8])
    if name:
        found.add(name)
    i += 4
print(",".join(sorted(found)))
