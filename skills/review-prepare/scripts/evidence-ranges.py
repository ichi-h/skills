#!/usr/bin/env python3
"""Print the changed regions of a file with line numbers, for evidence.md.

Numbers in front of the text let a reviewer jump to the line a prompt refers to
(`docs/architecture.md:174-178`) without opening the file, which would be a tool

call and would re-read the entire context.

Reads the unified diff for one file on stdin and prints the new-side lines that
the diff touches, expanded by `--pad` lines on each side, with the new-file line
number in front of every line. Regions that are far apart are printed separately
with a marker in between, so the reader can tell that lines were skipped.

Usage:
  git diff --no-color "$BASE...HEAD" -- "$path" | evidence-ranges.py --file "$path" --pad 25
  evidence-ranges.py --file "$path" --pad 25 --ranges "120:12 340:4"   # no diff available

Exit status 2 means "nothing to print" (the diff had no hunks and no ranges were
given); the caller should fall back to the full text or to a pointer.
"""

import argparse
import re
import sys

HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")


def parse_ranges(patch_text):
    """New-file (start, end) pairs touched by the hunks. Deletions give a point."""
    ranges = []
    for line in patch_text.splitlines():
        m = HUNK.match(line)
        if not m:
            continue
        start = int(m.group(1))
        count = int(m.group(2)) if m.group(2) is not None else 1
        if count == 0:
            # Pure deletion: the hunk has no new-side lines. Anchor on the
            # line the deletion sits after so the reader still sees context.
            ranges.append((start, start))
        else:
            ranges.append((start, start + count - 1))
    return ranges


def parse_explicit(spec):
    """`--ranges "120:12 340:4"` -> [(120,131), (340,343)] (1-based, inclusive)."""
    ranges = []
    for item in spec.split():
        start, _, count = item.partition(":")
        start = int(start)
        count = int(count) if count else 1
        ranges.append((start, start + max(count, 1) - 1))
    return ranges


def merge(ranges, pad, total):
    """Expand by `pad`, clamp to 1..total, and merge anything that now touches."""
    merged = []
    for start, end in sorted(ranges):
        start = max(1, start - pad)
        end = min(total, end + pad)
        if start > end:
            continue
        if merged and start <= merged[-1][1] + 1:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    return merged


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True, help="path of the file being described")
    ap.add_argument("--pad", type=int, default=25, help="context lines around each hunk")
    ap.add_argument("--ranges", default="", help="explicit 'start:count' spec, used when there is no diff")
    ap.add_argument("--min-gap", type=int, default=8,
                    help="skipped runs shorter than this are printed instead of elided")
    args = ap.parse_args()

    with open(args.file, "r", encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    total = len(lines)

    ranges = parse_ranges(sys.stdin.read())
    if args.ranges:
        ranges.extend(parse_explicit(args.ranges))
    if not ranges:
        return 2

    ranges = merge(ranges, args.pad, total)
    if not ranges:
        return 2

    width = len(str(total))
    print(f"<!-- {args.file}: {total} lines; showing {len(ranges)} changed region(s) with {args.pad} lines of context -->")
    print()
    for idx, (start, end) in enumerate(ranges):
        if idx > 0:
            prev_end = ranges[idx - 1][1]
            gap = start - prev_end - 1
            if gap > 0:
                if gap <= args.min_gap:
                    # Short gap: print it rather than break the reader's flow.
                    for n in range(prev_end + 1, start):
                        print(f"{n:>{width}}| {lines[n - 1]}")
                    continue
                print(f"~~~ (omitted lines {prev_end + 1}-{start - 1}) ~~~")
        for n in range(start, end + 1):
            print(f"{n:>{width}}| {lines[n - 1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
