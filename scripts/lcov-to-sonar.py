#!/usr/bin/env python3
"""Converts coverage/swift.lcov into SonarQube's generic coverage XML at coverage/swift.xml.

Run from the repo root, after scripts/coverage.sh has written the lcov file. The paths are fixed
so the script reads and writes nowhere else.
"""
import os
import sys
from xml.sax.saxutils import quoteattr

SOURCE = "coverage/swift.lcov"
DESTINATION = "coverage/swift.xml"
KEEP = "Sources/"


def relative(path: str, root: str) -> str:
    return path[len(root):] if path.startswith(root) else path


def read_lcov(root: str) -> dict[str, dict[int, bool]]:
    """Covered state per line for each file under KEEP, with paths relative to the repo root."""
    files: dict[str, dict[int, bool]] = {}
    current = None
    with open(SOURCE, encoding="utf-8") as report:
        for raw in report:
            line = raw.strip()
            if line.startswith("SF:"):
                path = relative(line[3:], root)
                current = files.setdefault(path, {}) if path.startswith(KEEP) else None
            elif line.startswith("DA:") and current is not None:
                number, hits = line[3:].split(",")[:2]
                # A line listed twice (generic code, inlined closures) is covered if any entry ran.
                current[int(number)] = current.get(int(number), False) or int(hits) > 0
    return files


def write_xml(files: dict[str, dict[int, bool]]) -> None:
    with open(DESTINATION, "w", encoding="utf-8") as output:
        output.write('<coverage version="1">\n')
        for path in sorted(files):
            output.write(f"  <file path={quoteattr(path)}>\n")
            for number in sorted(files[path]):
                covered = "true" if files[path][number] else "false"
                output.write(f'    <lineToCover lineNumber="{number}" covered="{covered}"/>\n')
            output.write("  </file>\n")
        output.write("</coverage>\n")


def main() -> int:
    files = read_lcov(os.getcwd() + os.sep)
    write_xml(files)
    lines = sum(len(entries) for entries in files.values())
    covered = sum(sum(entries.values()) for entries in files.values())
    print(f"{DESTINATION}: {len(files)} files, {covered}/{lines} lines covered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
