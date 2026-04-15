#!/usr/bin/env python3
"""Check coverage report and exit non-zero if any library file is below 100%."""
import re
import sys

content = open("coverage/index.html").read()
m = re.search(r"Total Project Coverage: ([\d.]+)%", content)
if not m:
    print("ERROR: Could not find coverage percentage", file=sys.stderr)
    sys.exit(1)

pct = float(m.group(1))
print(f"Coverage: {pct}%")

# Find all rows: <tr><td class="..."><a href="file.html">file.rkt</a></td>...<td class="coverage-percentage">NN.N</td>
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

for f, p in uncov_files:
    print(f"  UNCOVERED: {f} ({p}%)", file=sys.stderr)

if uncov_files:
    sys.exit(1)
