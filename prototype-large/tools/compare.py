"""Compares the output of a Check app with the output of icu4x-apps/reference (DESIGN.md, decision 7).

Usage: python3 -I -B compare.py [--keyed] <reference.tsv> <other.tsv> [<name>]
With --keyed, the other file can have a subset of the cases, in any order.
Prints the number of lines that are the same, the lines that are outside the range of the Chinese table (decision 6), and the first differences.
"""
import sys


def main():
    args = [a for a in sys.argv[1:] if a != "--keyed"]
    ref = open(args[0], encoding="utf-8").read().splitlines()
    other = open(args[1], encoding="utf-8").read().splitlines()
    name = args[2] if len(args) > 2 else args[1]
    if "--keyed" in sys.argv:
        # The other file has a subset of the cases, in any order: match each line by its first 5 fields.
        by_key = {tuple(l.split("\t")[:5]): l for l in ref}
        missing = [l for l in other if tuple(l.split("\t")[:5]) not in by_key]
        if missing:
            print(f"{name}: {len(missing)} lines have no case in the reference, for example {missing[0]}")
        ref = [by_key[tuple(l.split("\t")[:5])] for l in other if tuple(l.split("\t")[:5]) in by_key]
        other = [l for l in other if tuple(l.split("\t")[:5]) in by_key]
    if len(ref) != len(other):
        print(f"{name}: {len(other)} lines, the reference has {len(ref)}")
    same = out_of_range = 0
    diffs = []
    for a, b in zip(ref, other):
        fa, fb = a.split("\t"), b.split("\t")
        if fa[:5] != fb[:5]:
            diffs.append((a, b))
        elif fa[5] == fb[5]:
            same += 1
        elif fb[5] == "<out of range>":
            out_of_range += 1
        else:
            diffs.append((a, b))
    print(f"{name}: {same} same, {out_of_range} outside the Chinese table, {len(diffs)} different")
    for a, b in diffs[:10]:
        print(f"  ICU4X: {a}\n  this:  {b}")


if __name__ == "__main__":
    main()
