#!/usr/bin/env python3
import sys
import re
import statistics


def parse(path):
    d = {}
    for line in open(path):
        m = re.match(r"^\s*(-?[\d.]+)s\s+(\S+)", line)
        if m:
            d[m.group(2)] = float(m.group(1))
    return d


def main():
    before = parse(sys.argv[1])
    after = parse(sys.argv[2])
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 10

    ratios = {}
    for name in sorted(before.keys() & after.keys()):
        ratios[name] = 100.0 * (after[name] / before[name] - 1.0)

    for name in sorted(ratios):
        print(f"{name}: {ratios[name]:+0.2f}%")

    vals = list(ratios.values())
    print(f"\nmean: {statistics.mean(vals):+0.2f}%")
    print(f"stddev: {statistics.stdev(vals):+0.2f}%")

    by_pct = sorted(ratios.items(), key=lambda kv: kv[1])
    print(f"\n-- greatest improvement (top {n}) --")
    for name, pct in by_pct[:n]:
        print(f"{name}: {pct:+0.2f}%")
    print(f"\n-- least improvement (bottom {n}) --")
    for name, pct in by_pct[-n:][::-1]:
        print(f"{name}: {pct:+0.2f}%")

    total_before = sum(before[name] for name in ratios)
    total_after = sum(after[name] for name in ratios)
    print(
        f"\nTOTAL: {total_before:.2f}s -> {total_after:.2f}s : "
        f"{100.0 * (total_after / total_before - 1.0):+0.2f}%"
    )


if __name__ == "__main__":
    main()
