#!/usr/bin/env python3
"""Emit golden vectors for the Swift port.

The Swift implementation in LinguaKeyCore reads this file and asserts it
reproduces every value. Without it the two implementations drift silently and
the device behaves differently from everything validated here.

Deterministic: no clock, no randomness, no dictionary iteration order.
"""
from __future__ import annotations

import json
from pathlib import Path

import fsrs
from fsrs import Channel, Grade, Modality

DAY = fsrs.SECONDS_PER_DAY


def scalar_vectors() -> list[dict]:
    out = []
    for stability in (0.5, 1.0, 3.0, 10.0, 50.0):
        for elapsed in (0.0, 0.5, 1.0, 7.0, 30.0, 365.0):
            out.append({
                "fn": "retrievability",
                "stability": stability,
                "elapsed_days": elapsed,
                "expect": fsrs.retrievability(stability, elapsed),
            })
    for grade in Grade:
        out.append({"fn": "initial_stability", "grade": int(grade),
                    "expect": fsrs.initial_stability(grade)})
        out.append({"fn": "initial_difficulty", "grade": int(grade),
                    "expect": fsrs.initial_difficulty(grade)})
    for difficulty in (1.0, 3.5, 5.0, 8.0, 10.0):
        for grade in Grade:
            out.append({"fn": "next_difficulty", "difficulty": difficulty,
                        "grade": int(grade),
                        "expect": fsrs.next_difficulty(difficulty, grade)})
    for stability in (1.0, 5.0, 25.0):
        for difficulty in (2.0, 5.0, 9.0):
            for r in (0.3, 0.7, 0.95):
                for grade in (Grade.HARD, Grade.GOOD, Grade.EASY):
                    out.append({
                        "fn": "stability_after_success",
                        "stability": stability, "difficulty": difficulty, "r": r,
                        "grade": int(grade),
                        "expect": fsrs.stability_after_success(stability, difficulty, r, grade),
                    })
                out.append({
                    "fn": "stability_after_failure",
                    "stability": stability, "difficulty": difficulty, "r": r,
                    "expect": fsrs.stability_after_failure(stability, difficulty, r),
                })
                for eta in (0.03, 0.1, 0.3, 0.5, 1.0):
                    out.append({
                        "fn": "stability_after_exposure",
                        "stability": stability, "difficulty": difficulty, "r": r,
                        "eta": eta,
                        "expect": fsrs.stability_after_exposure(stability, difficulty, r, eta),
                    })
    for zipf in (0.0, 2.0, 4.0, 6.0, 7.7):
        for cognate in (0.0, 0.5, 1.0):
            for false_friend in (False, True):
                out.append({
                    "fn": "difficulty_prior", "zipf": zipf, "cognate_max": cognate,
                    "false_friend": false_friend,
                    "expect": fsrs.difficulty_prior(zipf, cognate, false_friend=false_friend),
                })
        out.append({"fn": "stability_prior", "cognate_max": zipf / 7.7,
                    "expect": fsrs.stability_prior(zipf / 7.7)})
    return out


SCENARIOS: list[tuple[str, dict, list[tuple[float, str, int]]]] = [
    ("exposure only never earns silence",
     {"zipf": 6.0, "cognate_max": 0.3},
     [(day, "EXPOSE_DWELLED", 3) for day in range(1, 41)]),

    ("two recalls earn silence",
     {"zipf": 6.0, "cognate_max": 0.3},
     [(1, "RECALL", 3), (3, "RECALL", 3)]),

    ("a lapse takes silence away",
     {"zipf": 6.0, "cognate_max": 0.3},
     [(1, "RECALL", 3), (3, "RECALL", 3), (20, "RECALL", 1)]),

    ("insert changes nothing",
     {"zipf": 7.0, "cognate_max": 0.9},
     [(1, "INSERTED", 3), (2, "INSERTED", 3), (3, "INSERTED", 3)]),

    ("a transparent cognate starts nearly known",
     {"zipf": 5.1, "cognate_max": 1.0},
     [(1, "EXPOSE_DWELLED", 3)]),

    ("a false friend starts harder than its form suggests",
     {"zipf": 4.1, "cognate_max": 1.0, "false_friend": True},
     [(1, "TAPPED", 3), (5, "RECALL", 1)]),

    ("production credits recognition, not the reverse",
     {"zipf": 6.0, "cognate_max": 0.2},
     [(1, "PRODUCED", 3), (8, "PRODUCED", 3)]),

    ("mixed real usage over a month",
     {"zipf": 6.05, "cognate_max": 0.4},
     [(1, "EXPOSE_GLANCED", 3), (2, "EXPOSE_DWELLED", 3), (4, "TAPPED", 3),
      (7, "RECALL", 2), (14, "RECALL", 3), (16, "INSERTED", 3),
      (21, "PRODUCED", 3), (30, "RECALL", 3)]),
]


def scenario_vectors() -> list[dict]:
    out = []
    for name, features, events in SCENARIOS:
        item = fsrs.new_item("golden", now=0.0, **features)
        steps = []
        for day, channel_name, grade in events:
            now = day * DAY
            fsrs.observe(item, Channel[channel_name], now=now, grade=Grade(grade))
            steps.append({
                "day": day, "channel": channel_name, "grade": grade,
                "recognition": _snapshot(item, Modality.RECOGNITION, now),
                "production": _snapshot(item, Modality.PRODUCTION, now),
                "mastery": fsrs.mastery(item, now),
                "suppress": fsrs.should_suppress(item, now),
            })
        out.append({"name": name, "features": features, "steps": steps})
    return out


def _snapshot(item: fsrs.Item, modality: Modality, now: float) -> dict:
    trace = item.traces[int(modality)]
    return {
        "stability": trace.stability,
        "difficulty": trace.difficulty,
        "reps": trace.reps,
        "lapses": trace.lapses,
        "exposures": trace.exposures,
        "effective_reps": trace.effective_reps,
        "last_graded_failed": trace.last_graded_failed,
        "retrievability": trace.retrievability(now),
    }


def main() -> None:
    payload = {
        "format": "keylang-fsrs-golden",
        "version": 1,
        "tolerance": 1e-6,
        "weights": list(fsrs.W),
        "eta": {channel.name: value for channel, value in fsrs.ETA.items()},
        "constants": {
            "decay": fsrs.DECAY,
            "factor": fsrs.FACTOR,
            "suppression_horizon_days": fsrs.SUPPRESSION_HORIZON_DAYS,
            "seconds_per_day": fsrs.SECONDS_PER_DAY,
        },
        "scalars": scalar_vectors(),
        "scenarios": scenario_vectors(),
        "_comment": (
            "The Swift implementation must reproduce every value here within"
            " `tolerance`. Regenerate with tools/engine/golden.py whenever the"
            " model changes, and treat a diff in this file as a deliberate"
            " model change requiring a note in STATE.md, never as noise."
        ),
    }
    # Repo-relative regardless of cwd, so running it from tools/engine does not
    # scatter a second build tree.
    repo_root = Path(__file__).resolve().parents[2]
    out = repo_root / "build" / "golden" / "fsrs-golden.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, indent=1, sort_keys=False) + "\n")
    print(f"{len(payload['scalars'])} scalar vectors, "
          f"{len(payload['scenarios'])} scenarios -> {out} "
          f"({out.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
