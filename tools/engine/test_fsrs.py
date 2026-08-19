#!/usr/bin/env python3
"""Property tests for the memory model.

These assert the behaviours the design depends on, not the arithmetic. If any
of them fails, a specific documented failure mode has come back.

Self-contained: no pytest, so it runs anywhere.
"""
from __future__ import annotations

import math
import sys

import fsrs
from fsrs import Channel, Grade, Modality

DAY = fsrs.SECONDS_PER_DAY
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


def approx(a: float, b: float, tol: float = 1e-9) -> bool:
    return abs(a - b) <= tol


# --------------------------------------------------------------- retrievability

check("R is 1.0 at zero elapsed time", approx(fsrs.retrievability(5.0, 0.0), 1.0))

decreasing = all(fsrs.retrievability(5.0, t) > fsrs.retrievability(5.0, t + 1)
                 for t in range(0, 200))
check("R decreases monotonically with elapsed time", decreasing)

check("R at t == S is 0.9 (the FSRS definition of stability)",
      approx(fsrs.retrievability(5.0, 5.0), 0.9, tol=1e-6),
      f"got {fsrs.retrievability(5.0, 5.0)}")

check("a more stable trace is always more retrievable",
      all(fsrs.retrievability(10.0, t) > fsrs.retrievability(2.0, t) for t in range(1, 100)))


# --------------------------------------------------------------- spacing effect

# The property that makes it safe to feed noisy exposures into a model built for
# graded reviews: a repetition of something you already know gains almost nothing.
gain_when_known = fsrs.stability_after_exposure(10.0, 5.0, r=0.999, eta=1.0) - 10.0
gain_when_faded = fsrs.stability_after_exposure(10.0, 5.0, r=0.700, eta=1.0) - 10.0
check("spacing effect: gain collapses as R approaches 1",
      gain_when_known < gain_when_faded * 0.05,
      f"known {gain_when_known:.4f} vs faded {gain_when_faded:.4f}")

check("spacing effect holds for graded reviews too",
      (fsrs.stability_after_success(10.0, 5.0, 0.999, Grade.GOOD) - 10.0)
      < (fsrs.stability_after_success(10.0, 5.0, 0.700, Grade.GOOD) - 10.0) * 0.05)


# --------------------------------------------------------------- exposure weight

graded = fsrs.stability_after_success(2.0, 5.0, 0.8, Grade.GOOD) - 2.0
glanced = fsrs.stability_after_exposure(2.0, 5.0, 0.8, fsrs.ETA[Channel.EXPOSE_GLANCED]) - 2.0
dwelled = fsrs.stability_after_exposure(2.0, 5.0, 0.8, fsrs.ETA[Channel.EXPOSE_DWELLED]) - 2.0
tapped = fsrs.stability_after_exposure(2.0, 5.0, 0.8, fsrs.ETA[Channel.TAPPED]) - 2.0

check("a glance is worth far less than a graded recall",
      glanced < graded * 0.05, f"{glanced:.4f} vs {graded:.4f}")
check("efficacy is ordered: glance < dwell < tap < graded",
      glanced < dwelled < tapped < graded)
check("about ten dwelled exposures approximate one graded review",
      2.0 < graded / dwelled < 20.0, f"ratio {graded / dwelled:.1f}")


# --------------------------------------------------------------- trace routing

item = fsrs.new_item("LEM:llegar|VERB|0", zipf=9.0, cognate_max=0.3, now=0.0)
production_before = item.traces[int(Modality.PRODUCTION)].stability

for day in range(1, 21):
    fsrs.observe(item, Channel.EXPOSE_DWELLED, now=day * DAY)

check("exposures never move the production trace",
      approx(item.traces[int(Modality.PRODUCTION)].stability, production_before),
      "production stability changed from exposure alone")
check("exposures do move the recognition trace",
      item.traces[int(Modality.RECOGNITION)].effective_reps > 0)
check("exposures leave difficulty untouched (seeing is not evidence of hardness)",
      approx(item.traces[int(Modality.RECOGNITION)].difficulty,
             fsrs.difficulty_prior(9.0, 0.3)))


# --------------------------------------------------------------- THE anti-F3 test

# Research 06's most dangerous failure mode: exposure counted as learning, so
# assistance fades for a word the learner never actually learned, and the system
# stops collecting the evidence that would correct it.
crammed = fsrs.new_item("LEM:quedar|VERB|0", zipf=8.0, cognate_max=0.2, now=0.0)
for i in range(100):
    fsrs.observe(crammed, Channel.EXPOSE_DWELLED, now=i * DAY)

check("100 exposures alone NEVER suppress the item",
      not fsrs.should_suppress(crammed, now=100 * DAY),
      "exposure-only item was suppressed, which is failure mode F3")
check("100 exposures leave production evidence at exactly zero",
      approx(crammed.traces[int(Modality.PRODUCTION)].effective_reps, 0.0))

# Two real recalls, on the other hand, should be able to earn silence.
earned = fsrs.new_item("LEM:llegar|VERB|0", zipf=9.0, cognate_max=0.3, now=0.0)
fsrs.observe(earned, Channel.RECALL, now=1 * DAY, grade=Grade.GOOD)
fsrs.observe(earned, Channel.RECALL, now=2 * DAY, grade=Grade.GOOD)
check("two successful recalls can earn suppression",
      fsrs.should_suppress(earned, now=2 * DAY + 60),
      f"R={earned.traces[1].retrievability(2 * DAY + 60):.3f} "
      f"evidence={earned.traces[1].effective_reps}")


# --------------------------------------------------------------- insert is free

inserted = fsrs.new_item("LEM:sobre|PREP|0", zipf=9.5, cognate_max=0.9, now=0.0)
before = (inserted.traces[0].stability, inserted.traces[1].stability,
          inserted.traces[0].effective_reps)
moved = fsrs.observe(inserted, Channel.INSERTED, now=DAY)
after = (inserted.traces[0].stability, inserted.traces[1].stability,
         inserted.traces[0].effective_reps)
check("tapping Insert moves nothing at all (copying is not producing)",
      moved == [] and before == after)


# --------------------------------------------------------------- production credits recognition

produced = fsrs.new_item("LEM:hablar|VERB|0", zipf=9.2, cognate_max=0.3, now=0.0)
recognition_before = produced.traces[int(Modality.RECOGNITION)].effective_reps
fsrs.observe(produced, Channel.PRODUCED, now=DAY, grade=Grade.GOOD)
check("producing a word credits recognition at partial weight",
      0 < produced.traces[int(Modality.RECOGNITION)].effective_reps - recognition_before < 1.0)
check("producing a word grades production in full",
      produced.traces[int(Modality.PRODUCTION)].effective_reps == 1.0)


# --------------------------------------------------------------- failure

lapsed = fsrs.new_item("LEM:coger|VERB|0", zipf=8.5, cognate_max=0.2, now=0.0)
fsrs.observe(lapsed, Channel.RECALL, now=DAY, grade=Grade.GOOD)
fsrs.observe(lapsed, Channel.RECALL, now=10 * DAY, grade=Grade.GOOD)
strong = lapsed.traces[int(Modality.PRODUCTION)].stability
fsrs.observe(lapsed, Channel.RECALL, now=20 * DAY, grade=Grade.AGAIN)
check("a failed recall reduces stability", lapsed.traces[1].stability < strong)
check("a failed recall counts a lapse", lapsed.traces[1].lapses == 1)
check("a failed recall un-suppresses the item",
      not fsrs.should_suppress(lapsed, now=20 * DAY + 60))


# --------------------------------------------------------------- cold start

easy = fsrs.difficulty_prior(zipf=8.0, cognate_max=1.0)
hard = fsrs.difficulty_prior(zipf=3.0, cognate_max=0.0)
trap = fsrs.difficulty_prior(zipf=6.0, cognate_max=1.0, false_friend=True)
plain = fsrs.difficulty_prior(zipf=6.0, cognate_max=1.0)

check("a transparent cognate starts easy", easy < 2.5, f"D={easy:.2f}")
# Assert the ordering rather than an absolute threshold. The prior's job is to
# rank items against each other so the per-sentence budget goes to the right one,
# not to hit a particular number on a scale nobody calibrated.
check("a rare opaque word starts much harder than a transparent cognate",
      hard > easy + 2.5, f"rare D={hard:.2f} vs cognate D={easy:.2f}")
check("difficulty priors span a useful range across realistic inputs",
      max(fsrs.difficulty_prior(z, c) for z in (1, 4, 8) for c in (0.0, 1.0))
      - min(fsrs.difficulty_prior(z, c) for z in (1, 4, 8) for c in (0.0, 1.0)) > 3.0)
check("frequency lowers difficulty",
      fsrs.difficulty_prior(9.0, 0.5) < fsrs.difficulty_prior(4.0, 0.5))
check("a false friend is HARDER than the same word without the trap",
      trap > plain, f"{trap:.2f} vs {plain:.2f}")
check("cognates start with more initial stability",
      fsrs.stability_prior(1.0) > fsrs.stability_prior(0.0))
check("difficulty priors stay inside the model's bounds",
      all(1.0 <= fsrs.difficulty_prior(z, c) <= 10.0
          for z in (0, 3, 6, 9, 12) for c in (0.0, 0.5, 1.0)))


# --------------------------------------------------------------- mastery

fresh = fsrs.new_item("LEM:x|N|0", zipf=5.0, cognate_max=0.5, now=0.0)
check("mastery is in [0, 1]", 0.0 <= fsrs.mastery(fresh, now=0.0) <= 1.0)

recognised = fsrs.new_item("LEM:y|N|0", zipf=5.0, cognate_max=0.5, now=0.0)
producible = fsrs.new_item("LEM:z|N|0", zipf=5.0, cognate_max=0.5, now=0.0)
for i in range(10):
    fsrs.observe(recognised, Channel.EXPOSE_DWELLED, now=i * DAY)
fsrs.observe(producible, Channel.PRODUCED, now=DAY, grade=Grade.GOOD)
check("mastery weights production above recognition",
      fsrs.mastery(producible, now=11 * DAY) > fsrs.mastery(recognised, now=11 * DAY),
      f"produced {fsrs.mastery(producible, 11 * DAY):.3f} vs "
      f"recognised {fsrs.mastery(recognised, 11 * DAY):.3f}")

# Mastery must decay. A stored float cannot, which was the core defect in the
# PRD's original model.
mastery_now = fsrs.mastery(producible, now=DAY + 60)
mastery_later = fsrs.mastery(producible, now=DAY + 200 * DAY)
check("mastery decays with time (a stored float could not)",
      mastery_later < mastery_now, f"{mastery_later:.3f} vs {mastery_now:.3f}")


# --------------------------------------------------------------- invariants

check("stability never goes non-positive",
      all(fsrs.stability_after_failure(s, d, r) > 0
          for s in (0.01, 1.0, 100.0) for d in (1.0, 5.0, 10.0) for r in (0.0, 0.5, 1.0)))
difficulty = 5.0
for _ in range(50):
    difficulty = fsrs.next_difficulty(difficulty, Grade.AGAIN)
check("difficulty saturates at the ceiling rather than diverging",
      1.0 <= difficulty <= 10.0, f"D={difficulty:.3f}")

difficulty = 5.0
for _ in range(50):
    difficulty = fsrs.next_difficulty(difficulty, Grade.EASY)
check("difficulty saturates at the floor rather than diverging",
      1.0 <= difficulty <= 10.0, f"D={difficulty:.3f}")


print()
if failures:
    print(f"FAIL: {len(failures)} of {passed + len(failures)} properties")
    for failure in failures:
        print(f"  - {failure}")
    sys.exit(1)
print(f"PASS: {passed} properties")
