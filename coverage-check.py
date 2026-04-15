#!/usr/bin/env python3
"""Check coverage report and exit non-zero if any library file is below 100%.

Test files (tests/) are excluded from the 100% requirement.
When all library files pass, exits 0 and prints "Coverage: 100%".
"""
import re
import sys

content = open("coverage/index.html").read()

# Find all file rows in the HTML report
rows = re.findall(
    r'<a href="[^"]+\.html">([^<]+\.rkt)</a>.*?<td class="coverage-percentage">([\d.]+)</td>',
    content,
    re.DOTALL,
)

uncov_files = [
    (f, float(p))
    for f, p in rows
    if float(p) < 100 and not f.startswith("tests/")
]

if uncov_files:
    for f, p in uncov_files:
        print(f"  UNCOVERED: {f} ({p}%)", file=sys.stderr)
    print("Coverage: FAILED (library files below 100%)", file=sys.stderr)
    sys.exit(1)

print("Coverage: 100%")
