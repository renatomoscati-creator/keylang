#!/usr/bin/env python3
"""Properties of arm assignment."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import arms

HERE = Path(__file__).resolve().parent

failures: list[str] = []
passed = 0


def check(name: str, condition: bool, detail: str = "") -> None:
    global passed
    if condition:
        passed += 1
        print(f"  ok  {name}")
    else:
        failures.append(f"{name}{': ' + detail if detail else ''}")
        print(f"  FAIL {name} {detail}")


# The published FNV-1a 64 test vectors.
check("fnv1a64('') is the offset basis", arms.fnv1a64("") == 0xCBF29CE484222325)
check("fnv1a64('a')", arms.fnv1a64("a") == 0xAF63DC4C8601EC8C)
check("fnv1a64('foobar')", arms.fnv1a64("foobar") == 0x85944171F73967E8)

check("the hash is 64 bit", all(0 <= arms.fnv1a64(str(i)) < 2**64 for i in range(1000)))

# The failure this whole file exists to prevent: a hash that changes between
# processes. Python's own hash() is salted per process by default, so running
# this in a subprocess proves the reference is not accidentally using it.
here = subprocess.run(
    [sys.executable, "-c",
     "import arms; print(arms.arm('salt-1', 'LEM:vaso|N|0'))"],
    capture_output=True, text=True, cwd=HERE)
check("assignment is identical in a separate process",
      here.stdout.strip() == arms.arm("salt-1", "LEM:vaso|N|0"),
      f"subprocess said {here.stdout.strip()!r}, we say {arms.arm('salt-1', 'LEM:vaso|N|0')!r}")

check("the same salt and key always give the same arm",
      all(arms.arm("s", "k") == arms.arm("s", "k") for _ in range(100)))

# A new install must reshuffle, otherwise every user would see the same word in
# the same arm and the item-level design would collapse into a between-subjects
# one with n=1.
reshuffled = sum(arms.arm("salt-1", k) != arms.arm("salt-2", k)
                 for k in (f"LEM:w{i}|N|0" for i in range(3_000)))
check("a different salt reshuffles about two thirds of items",
      0.60 < reshuffled / 3_000 < 0.73, f"{reshuffled} of 3000 moved")

# The separator matters: without it these two inputs would be the same string.
check("the separator keeps salt and key apart",
      arms.fnv1a64("ab\x01c") != arms.fnv1a64("a\x01bc"))

# Deterministic, so a threshold that passes now passes forever. 100k keys put
# one standard deviation at 0.45% of a third, so 1% is a real bound and not a
# rubber stamp.
keys = [f"LEM:word{i}|N|0" for i in range(100_000)]
counts = {a: 0 for a in arms.ARMS}
for key in keys:
    counts[arms.arm("distribution-salt", key)] += 1
third = len(keys) / 3
for a, n in sorted(counts.items()):
    check(f"arm {a} is within 1% of a third ({n})", abs(n - third) / third < 0.01,
          f"{n} of {len(keys)}")

check("every arm is reachable", all(n > 0 for n in counts.values()))

print()
if failures:
    print(f"FAIL: {len(failures)} of {passed + len(failures)}")
    for failure in failures:
        print(f"  - {failure}")
    sys.exit(1)
print(f"PASS: {passed} properties")
