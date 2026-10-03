#!/usr/bin/env python3
"""Converts an lcov report into SonarQube's generic coverage XML, with paths relative to the repo root.

Usage: lcov-to-sonar.py <lcov file> <output xml> [path prefix to keep, default "Sources/"]
"""
import os
import sys
from xml.sax.saxutils import quoteattr


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    source, destination = sys.argv[1], sys.argv[2]
    keep = sys.argv[3] if len(sys.argv) > 3 else "Sources/"
    root = os.getcwd() + os.sep

    files: dict[str, dict[int, bool]] = {}
    current = None
    with open(source, encoding="utf-8") as report:
        for raw in report:
            line = raw.strip()
            if line.startswith("SF:"):
                path = line[3:]
                path = path[len(root):] if path.startswith(root) else path
                current = files.setdefault(path, {}) if path.startswith(keep) else None
            elif line.startswith("DA:") and current is not None:
                number, hits = line[3:].split(",")[:2]
                # A line listed twice (generic code, inlined closures) is covered if any entry ran.
                current[int(number)] = current.get(int(number), False) or int(hits) > 0

    with open(destination, "w", encoding="utf-8") as output:
        output.write('<coverage version="1">\n')
        for path in sorted(files):
            output.write(f"  <file path={quoteattr(path)}>\n")
            for number in sorted(files[path]):
                covered = "true" if files[path][number] else "false"
                output.write(f'    <lineToCover lineNumber="{number}" covered="{covered}"/>\n')
            output.write("  </file>\n")
        output.write("</coverage>\n")

    lines = sum(len(entries) for entries in files.values())
    covered = sum(sum(entries.values()) for entries in files.values())
    print(f"{destination}: {len(files)} files, {covered}/{lines} lines covered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
