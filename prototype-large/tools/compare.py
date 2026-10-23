"""Compares the output of a Check app with the output of icu4x-apps/reference (DESIGN.md, decision 7).

Usage: python3 -I -B compare.py <reference.tsv> <other.tsv> [<name>]
Prints the number of lines that are the same, the lines that are outside the range of the Chinese table (decision 6), and the first differences.
"""
import sys


def main():
    ref = open(sys.argv[1], encoding="utf-8").read().splitlines()
    other = open(sys.argv[2], encoding="utf-8").read().splitlines()
    name = sys.argv[3] if len(sys.argv) > 3 else sys.argv[2]
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
