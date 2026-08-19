#!/usr/bin/env python3
"""Behaviour tests for focus selection, against the real built tables."""
from __future__ import annotations

import sys
from pathlib import Path

import focus
import fsrs
from fsrs import Channel, Grade
from lexicon import Tables

ROOT = Path(__file__).resolve().parents[2]
tables = Tables(ROOT / "build" / "morphology", ROOT / "build" / "lexicon")

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


def pick(sentence: str, state=None, now: float = 0.0):
    return focus.select(sentence, tables, state or {}, now=now)


def keys(chosen) -> set[str]:
    return {c.key for c in chosen}


# --------------------------------------------------------- false friends win

for sentence, lemma in [
    ("Voy a comprar mantequilla y pan", "pan"),
    ("El problema es que salgo muy tarde", "salir"),
    ("Quiero un vaso de agua", "vaso"),
    ("Espero que vengas pronto", "pronto"),
]:
    chosen = pick(sentence)
    check(f"false friend {lemma!r} is chosen from {sentence[:28]!r}...",
          any(c.reading.lemma == lemma and "false friend" in c.reason for c in chosen),
          f"got {[(c.surface, c.reason[:24]) for c in chosen]}")


# --------------------------------------------------------- true cognates do not

# The bug this replaced: using the orthographic score as if it were semantic
# flagged `llegar`~`legare` and `comprar`~`comprare`, which are true cognates and
# exactly the words a learner gets for free.
for sentence, lemma in [("Probablemente llegaré sobre las ocho", "llegar"),
                        ("Voy a comprar pan", "comprar"),
                        ("Tengo que estudiar", "estudiar")]:
    chosen = pick(sentence)
    check(f"true cognate {lemma!r} is NOT called a false friend",
          not any(c.reading.lemma == lemma and "false friend" in c.reason for c in chosen))


# --------------------------------------------------------- the budget

for sentence in ["Probablemente llegaré sobre las ocho y quiero comprar pan y vino",
                 "El problema es que salgo muy tarde y tengo mucha prisa"]:
    chosen = pick(sentence)
    check(f"at most one vocabulary note for {sentence[:26]!r}...",
          sum(1 for c in chosen if c.kind == "vocabulary") <= 1)
    check(f"at most one grammar note for {sentence[:26]!r}...",
          sum(1 for c in chosen if c.kind == "grammar") <= 1)
    check("vocabulary and grammar notes never land on the same word",
          len({c.surface for c in chosen}) == len(chosen))


# --------------------------------------------------------- silence

check("a sentence of only function words teaches nothing",
      pick("y de la que en el a") == [])
check("nonsense teaches nothing", pick("qwertz asdfgh zxcvbn") == [])
check("an empty string teaches nothing", pick("") == [])


# --------------------------------------------------------- state changes the answer

# Once an item is known, the selector should move on to something else. This is
# the behaviour the PRD promised and its threshold ladder could not deliver,
# because a stored float cannot decay and exposure alone would have satisfied it.
sentence = "Quiero un vaso de agua"
before = pick(sentence)
vaso_key = "LEM:vaso|N|0"
check("vaso is taught when unknown", vaso_key in keys(before))

state = {vaso_key: fsrs.new_item(vaso_key, zipf=4.6, cognate_max=1.0, now=0.0)}
for day in (1, 3, 8):
    fsrs.observe(state[vaso_key], Channel.RECALL, now=day * fsrs.SECONDS_PER_DAY,
                 grade=Grade.GOOD)
after = pick(sentence, state, now=8 * fsrs.SECONDS_PER_DAY)
check("vaso is dropped once genuinely known", vaso_key not in keys(after),
      f"still chose {sorted(keys(after))}")

# But exposure alone must NOT buy that silence. Same failure mode as F3.
exposed = {vaso_key: fsrs.new_item(vaso_key, zipf=4.6, cognate_max=1.0, now=0.0)}
for day in range(1, 41):
    fsrs.observe(exposed[vaso_key], Channel.EXPOSE_DWELLED,
                 now=day * fsrs.SECONDS_PER_DAY)
still = pick(sentence, exposed, now=40 * fsrs.SECONDS_PER_DAY)
check("40 exposures do NOT buy silence for vaso", vaso_key in keys(still),
      f"chose {sorted(keys(still))}")


# --------------------------------------------------------- repetition within a session

counts = {"LEM:vaso|N|0": 3}
damped = focus.select(sentence, tables, {}, now=0.0, session_counts=counts)
check("an item already shown this session is damped",
      "LEM:vaso|N|0" not in keys(damped),
      f"chose {sorted(keys(damped))}")


# --------------------------------------------------------- grammar notes are teachable

chosen = pick("Probablemente llegaré sobre las ocho")
grammar = [c for c in chosen if c.kind == "grammar"]
check("the future-tense form gets the grammar note",
      any("FUT" in c.reading.feats for c in grammar),
      f"got {[c.key for c in grammar]}")
check("noun gender and number never become a grammar note",
      not any(c.key.startswith("CELL:N|") for c in pick("Quiero un vaso de agua")))


print()
if failures:
    print(f"FAIL: {len(failures)} of {passed + len(failures)}")
    for failure in failures:
        print(f"  - {failure}")
    sys.exit(1)
print(f"PASS: {passed} behaviours")
