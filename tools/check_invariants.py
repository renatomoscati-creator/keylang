#!/usr/bin/env python3
"""Mechanical checks on the Swift that no Swift compiler here can make.

These are the invariants that are easy to break by accident and expensive to
notice: they all look like working code. Grep is a blunt instrument and these
are deliberately conservative, preferring a false alarm to a miss.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

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


def swift_files(*roots: str) -> list[Path]:
    out: list[Path] = []
    for root in roots:
        base = ROOT / root
        if base.exists():
            out.extend(sorted(p for p in base.rglob("*.swift")
                              if ".build" not in p.parts))
    return out


sources = swift_files("LinguaKeyCore", "LinguaKeyApp", "Probe")
check("there are Swift sources to check", len(sources) > 0, f"found {len(sources)}")


# --------------------------------------------------------- the Translation boundary

# `TranslationSession` cannot be constructed outside SwiftUI's `.translationTask`,
# cannot be unit-tested, and does not exist in the Simulator. The whole point of
# the protocol is that exactly one file knows that.
# StudySystem IS the boundary, so the whole module may import it. Probe/ is the
# throwaway phase 01 harness and is exempt by design.
TRANSLATION_ALLOWED_PREFIXES = (
    "LinguaKeyApp/Sources/StudySystem/",
    "Probe/",
)
importers = {
    str(p.relative_to(ROOT))
    for p in sources
    if re.search(r"^\s*import\s+Translation\b", p.read_text(encoding="utf-8"), re.M)
}
stray = sorted(i for i in importers
               if not i.startswith(TRANSLATION_ALLOWED_PREFIXES))
check("only StudySystem imports Translation", not stray, f"stray: {stray}")
check("StudySystem actually is the boundary, and still exists",
      any(i.startswith("LinguaKeyApp/Sources/StudySystem/") for i in importers))

# And the boundary only works in one direction: the engine and the study surface
# must not reach back through it, or the "testable without the framework" claim
# quietly stops being true.
back_references = sorted(
    str(p.relative_to(ROOT))
    for p in swift_files("LinguaKeyApp/Sources/StudyKit", "LinguaKeyApp/Sources/StudyUI",
                         "LinguaKeyCore/Sources")
    if re.search(r"^\s*import\s+StudySystem\b", p.read_text(encoding="utf-8"), re.M)
)
check("StudyKit, StudyUI and LinguaKeyCore do not import StudySystem",
      not back_references, f"{back_references}")


# --------------------------------------------------------- mastery is never stored

# A stored float cannot decay. This is the exact mistake the stress test found in
# the PRD, and it would come back as a "cache" the moment someone profiled a list.
store_paths = swift_files("LinguaKeyCore/Sources", "LinguaKeyApp/Sources")
STORED_MASTERY = re.compile(r"\b(var|let)\s+\w*[Mm]astery\w*\s*[:=]")
offenders = []
for path in store_paths:
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if STORED_MASTERY.search(line):
            offenders.append(f"{path.relative_to(ROOT)}:{number}")
check("mastery is never a stored property", not offenders, f"{offenders}")

check("mastery is computed, and still exists",
      any("func mastery(" in p.read_text(encoding="utf-8") for p in store_paths))


# --------------------------------------------------------- the arm hash

# Swift's Hasher is seeded per process. Using it here reassigns arms on every
# launch while looking like working code.
arm_file = ROOT / "LinguaKeyApp/Sources/StudyKit/ArmAssignment.swift"
if arm_file.exists():
    text = arm_file.read_text(encoding="utf-8")
    body = "\n".join(l for l in text.splitlines() if not l.strip().startswith("//"))
    check("arm assignment does not use Hasher or hashValue",
          "Hasher" not in body and ".hashValue" not in body)
    check("arm assignment uses the FNV-1a constants",
          "14695981039346656037" in body and "1099511628211" in body)
else:
    check("ArmAssignment.swift exists", False, str(arm_file))


# --------------------------------------------------------- the wire format

# The Python reference writes the log and the Swift reads it. If a Channel raw
# value or a Grade number differs by one character the golden vectors catch it,
# but only for the channels the vectors happen to use. This catches all of them.
fsrs_swift = (ROOT / "LinguaKeyCore/Sources/LinguaKeyCore/Memory/FSRS.swift")
fsrs_python = (ROOT / "tools/engine/fsrs.py")
if fsrs_swift.exists() and fsrs_python.exists():
    swift_text = fsrs_swift.read_text(encoding="utf-8")
    python_text = fsrs_python.read_text(encoding="utf-8")

    swift_channels = set(re.findall(r'case\s+\w+\s*=\s*"([A-Z_]+)"', swift_text))
    python_channels = set(re.findall(r"^\s{4}([A-Z_]+)\s*=\s*", python_text, re.M))
    # Only the ones that are actually Channel members on the Python side.
    channel_block = re.search(r"class Channel\b.*?(?=\nclass |\n@|\ndef )",
                              python_text, re.S)
    if channel_block:
        python_channels = set(re.findall(r"^\s{4}([A-Z_]+)\s*=",
                                         channel_block.group(0), re.M))
    check("Channel raw values match between the Swift and the reference",
          swift_channels == python_channels,
          f"swift only: {sorted(swift_channels - python_channels)}, "
          f"python only: {sorted(python_channels - swift_channels)}")

    # The Swift declares all four on one `case` line, so match the whole enum
    # body rather than one case at a time.
    grade_body = re.search(r"public enum Grade[^{]*\{(.*?)\}", swift_text, re.S)
    swift_grades = dict(re.findall(r"(again|hard|good|easy)\s*=\s*(\d)",
                                   grade_body.group(1) if grade_body else ""))
    python_grades = dict(re.findall(r"^\s{4}(AGAIN|HARD|GOOD|EASY)\s*=\s*(\d)",
                                    python_text, re.M))
    check("Grade numbers match the reference",
          swift_grades == {k.lower(): v for k, v in python_grades.items()}
          and len(swift_grades) == 4,
          f"swift {swift_grades}, python {python_grades}")

    check("Arm raw values are the single letters the reference writes",
          set(re.findall(r'case\s+\w+\s*=\s*"([ABC])"',
                         (ROOT / "LinguaKeyApp/Sources/StudyKit/Event.swift")
                         .read_text(encoding="utf-8"))) == {"A", "B", "C"})


# --------------------------------------------------------- one App Group identifier

# The app and the extension are two processes sharing one container. A single
# character of drift between the two entitlements gives each of them its own
# empty container and looks exactly like "the extension is not saving anything".
# The pattern deliberately allows build-setting variables, because the identifier
# is derived from BUNDLE_PREFIX rather than written out.
group_ids: dict[str, list[str]] = {}
plists = [p for p in list(ROOT.rglob("*.entitlements")) + list(ROOT.rglob("Info.plist"))
          if ".build" not in p.parts and "DerivedData" not in p.parts]
for path in plists:
    for match in re.findall(r"group\.[^<\s]+", path.read_text(encoding="utf-8")):
        group_ids.setdefault(match, []).append(str(path.relative_to(ROOT)))
check("exactly one App Group identifier across the repo",
      len(group_ids) == 1, f"found {sorted(group_ids)}")

# It has to be in both entitlements files and in both Info.plists: the
# entitlement grants the container, and Storage reads the identifier from
# Info.plist rather than hardcoding it.
if len(group_ids) == 1:
    carriers = set(next(iter(group_ids.values())))
    for required in ("LinguaKeyApp/LinguaKey/LinguaKey.entitlements",
                     "LinguaKeyApp/LinguaKeyShare/LinguaKeyShare.entitlements",
                     "LinguaKeyApp/LinguaKey/Info.plist",
                     "LinguaKeyApp/LinguaKeyShare/Info.plist"):
        check(f"the App Group is declared in {required.split('/')[-1]} of "
              f"{required.split('/')[1]}", required in carriers, f"{sorted(carriers)}")


# --------------------------------------------------------- staged data matches the build

staged = ROOT / "build" / "LinguaKeyData"
if staged.exists():
    import filecmp
    same = True
    detail = ""
    for name in ("morphology", "lexicon"):
        comparison = filecmp.dircmp(ROOT / "build" / name, staged / name)
        if comparison.left_only or comparison.right_only or comparison.diff_files:
            same = False
            detail = f"{name}: {comparison.diff_files or comparison.left_only or comparison.right_only}"
    if not filecmp.cmp(ROOT / "data" / "interference.json",
                       staged / "interference.json", shallow=False):
        same = False
        detail = "interference.json differs"
    check("staged data root matches build/ and data/", same, detail)
else:
    print("  --  staged data root not present, run tools/stage-data.sh")


# --------------------------------------------------------- golden vectors are readable

for name in ("fsrs-golden.json", "arms-golden.json", "store-golden.json"):
    path = ROOT / "build" / "golden" / name
    check(f"{name} is present and parses",
          path.exists() and isinstance(json.loads(path.read_text()), dict))

# The event log vectors are deliberately not all valid JSON: three of the lines
# are the corruption the reader has to survive. What must hold is that the rest
# parse and that the file ends mid-record.
events = ROOT / "build" / "golden" / "store-events.jsonl"
if events.exists():
    lines = events.read_text(encoding="utf-8").split("\n")
    good = sum(1 for l in lines if l and l.startswith("{") and l.endswith("}"))
    check("store-events.jsonl carries a readable body", good > 20, f"{good} lines")
    check("store-events.jsonl ends with a torn line, which is the point",
          not events.read_text(encoding="utf-8").endswith("\n"))
else:
    check("store-events.jsonl is present", False)


print()
if failures:
    print(f"FAIL: {len(failures)} of {passed + len(failures)}")
    for failure in failures:
        print(f"  - {failure}")
    sys.exit(1)
print(f"PASS: {passed} invariants")
