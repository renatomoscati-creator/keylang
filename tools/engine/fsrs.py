#!/usr/bin/env python3
"""FSRS-6 as a memory-state ESTIMATOR, with attenuated exposures.

Reference implementation. The Swift in `LinguaKeyCore` is tested against the
golden vectors this emits, so the two cannot drift silently.

Why not FSRS as a scheduler, which is what it was built for: the scheduler's
output is an optimal next interval, and this product cannot make the user
message someone about arriving late on day 12. Timing is exogenous. So FSRS is
used for exactly one question, `R(item, modality, now)`, and a separate policy
layer decides what to do about it.

Three departures from stock FSRS, each from research 06:

  Two traces per item. `recognition` (does the learner know what `llegaré`
  means) and `production` (can they produce it). Receptive knowledge
  systematically exceeds productive, and this product's stated goal is
  production, so a single trace would declare victory silently.

  Exposures are reviews with an efficacy weight, and touch recognition only.
  An incidental exposure is worth roughly a tenth of a graded recall
  (meta-analytic r = .34, ~12-17% of variance). Crucially the FSRS growth term
  already contains `(exp((1-R)*w10) - 1)`, which goes to zero as R goes to one,
  so ten exposures in one conversation are worth almost nothing for free. That
  property is what makes it safe to feed noisy signals in at all.

  Cold start from item features. Stock FSRS initialises from the first grade,
  which for incidental exposure is often no grade at all. Frequency and cognate
  distance give a real prior, and research 10 argued cognate distance is a
  better difficulty feature than CEFR level for an English-plus-Italian speaker.
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass, asdict, field
from enum import IntEnum

# FSRS-6 defaults, transcribed from fsrs-rs `src/model.rs`.
# Do not renumber. The Swift reads the same array.
W: tuple[float, ...] = (
    0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722,
    0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425,
    0.0912, 0.0658, 0.1542,
)

DECAY = -W[20]
FACTOR = math.exp(math.log(0.9) / DECAY) - 1.0

MIN_STABILITY = 0.001
MIN_DIFFICULTY, MAX_DIFFICULTY = 1.0, 10.0
SECONDS_PER_DAY = 86_400.0


class Modality(IntEnum):
    RECOGNITION = 0
    PRODUCTION = 1


class Grade(IntEnum):
    AGAIN = 1
    HARD = 2
    GOOD = 3
    EASY = 4


class Channel(IntEnum):
    """How the observation reached us. Determines efficacy and which trace moves."""
    EXPOSE_GLANCED = 0     # shown, no interaction, under 800 ms dwell
    EXPOSE_DWELLED = 1     # shown, visible >= 1.5 s, user kept typing
    TAPPED = 2             # user tapped for a breakdown, gloss or audio
    INSERTED = 3           # user tapped Insert. Copying is not producing.
    RECALL = 4             # answered a recall prompt
    PRODUCED = 5           # typed the Spanish unprompted, no assistance
    CORRECTED = 6          # a Mode E correction was accepted


# Efficacy weights. Priors to be FITTED from the event log, not facts.
# The ~10:1 exposure-to-review ratio operationalises the meta-analytic finding
# that repetition explains only 12-17% of variance in incidental learning.
#
# INSERTED is deliberately zero. The user needed the Spanish, the system supplied
# it without retrieval, and the log would otherwise record "sent a Spanish
# message" (the product's success metric) while no learning occurred.
ETA: dict[Channel, float] = {
    Channel.EXPOSE_GLANCED: 0.03,
    Channel.EXPOSE_DWELLED: 0.10,
    Channel.TAPPED: 0.30,
    Channel.INSERTED: 0.00,
    Channel.RECALL: 1.00,
    Channel.PRODUCED: 1.00,
    Channel.CORRECTED: 1.00,
}

GRADED_CHANNELS = {Channel.RECALL, Channel.PRODUCED, Channel.CORRECTED}


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def retrievability(stability: float, elapsed_days: float) -> float:
    """Probability of recall now. Power law, not exponential."""
    if elapsed_days <= 0:
        return 1.0
    return (elapsed_days / max(stability, MIN_STABILITY) * FACTOR + 1.0) ** DECAY


def interval_for(stability: float, desired_retention: float) -> float:
    """Days until retrievability falls to `desired_retention`."""
    return stability / FACTOR * (desired_retention ** (1.0 / DECAY) - 1.0)


def initial_stability(grade: Grade) -> float:
    return max(W[grade - 1], MIN_STABILITY)


def initial_difficulty(grade: Grade) -> float:
    return clamp(W[4] - math.exp(W[5] * (grade - 1)) + 1.0, MIN_DIFFICULTY, MAX_DIFFICULTY)


def _dampen(delta: float, difficulty: float) -> float:
    return (10.0 - difficulty) * delta / 9.0


def next_difficulty(difficulty: float, grade: Grade) -> float:
    moved = difficulty + _dampen(-W[6] * (grade - 3), difficulty)
    reverted = W[7] * (initial_difficulty(Grade.EASY) - moved) + moved
    return clamp(reverted, MIN_DIFFICULTY, MAX_DIFFICULTY)


def _growth(stability: float, difficulty: float, r: float) -> float:
    """The bracket shared by graded success and attenuated exposure.

    `(exp((1 - r) * W[10]) - 1)` is the spacing effect: it goes to zero as r goes
    to one, so a repetition of something you already know perfectly is worth
    almost nothing. This is why noisy exposures can be fed in safely.
    """
    return (math.exp(W[8]) * (11.0 - difficulty)
            * stability ** (-W[9]) * (math.exp((1.0 - r) * W[10]) - 1.0))


def stability_after_success(stability: float, difficulty: float, r: float,
                            grade: Grade) -> float:
    hard = W[15] if grade == Grade.HARD else 1.0
    easy = W[16] if grade == Grade.EASY else 1.0
    return max(stability * (_growth(stability, difficulty, r) * hard * easy + 1.0),
               MIN_STABILITY)


def stability_after_failure(stability: float, difficulty: float, r: float) -> float:
    long_term = (W[11] * difficulty ** (-W[12])
                 * ((stability + 1.0) ** W[13] - 1.0)
                 * math.exp((1.0 - r) * W[14]))
    short_term = stability / math.exp(W[17] * W[18])
    return max(min(long_term, short_term), MIN_STABILITY)


def stability_same_day(stability: float, grade: Grade) -> float:
    return max(stability * max(1.0, math.exp(W[17] * (grade - 3 + W[18]))
                               * stability ** (-W[19])), MIN_STABILITY)


def stability_after_exposure(stability: float, difficulty: float, r: float,
                             eta: float) -> float:
    """An ungraded exposure. Difficulty does NOT move: seeing a word is no
    evidence about how hard it is."""
    if eta <= 0.0:
        return stability
    return max(stability * (eta * _growth(stability, difficulty, r) + 1.0), MIN_STABILITY)


# ---------------------------------------------------------------- cold start

def difficulty_prior(zipf: float, cognate_max: float, *, false_friend: bool = False,
                     length: int = 0, is_construction: bool = False,
                     irregular: bool = False) -> float:
    """Difficulty before any evidence, from item features.

    The single cheapest high-value change in the design: without it, every unseen
    word starts at maximum difficulty and the per-sentence teaching budget gets
    spent explaining `hotel` and `taxi`.

    `false_friend` RAISES difficulty because the trap is in the meaning. Research
    06 found false cognates are easier on FORM and harder on MEANING, which is
    also why the two traces are scored separately.
    """
    value = (5.0
             - 0.45 * (zipf - 4.0)
             - 2.20 * cognate_max
             + 1.40 * (1.0 if false_friend else 0.0)
             + 0.30 * (1.0 if length > 9 else 0.0)
             + 0.60 * (1.0 if is_construction else 0.0)
             + 0.80 * (1.0 if irregular else 0.0))
    return clamp(value, MIN_DIFFICULTY, MAX_DIFFICULTY)


def stability_prior(cognate_max: float) -> float:
    """Cognates start stickier, because they already hook onto something known."""
    return clamp(0.4 * math.exp(1.1 * cognate_max), 0.4, 4.0)


# ---------------------------------------------------------------- trace

@dataclass
class Trace:
    stability: float
    difficulty: float
    last_event_at: float          # unix seconds
    reps: int = 0                 # graded events only
    lapses: int = 0
    exposures: int = 0            # diagnostic ONLY. Never feeds a threshold.
    effective_reps: float = 0.0   # sum of eta. The honest evidence count.
    last_graded_failed: bool = False

    def retrievability(self, now: float) -> float:
        return retrievability(self.stability, (now - self.last_event_at) / SECONDS_PER_DAY)


@dataclass
class Item:
    key: str
    traces: dict[int, Trace] = field(default_factory=dict)

    def trace(self, modality: Modality) -> Trace | None:
        return self.traces.get(int(modality))


def new_item(key: str, *, zipf: float, cognate_max: float,
             false_friend: bool = False, length: int = 0,
             is_construction: bool = False, irregular: bool = False,
             now: float = 0.0) -> Item:
    difficulty = difficulty_prior(zipf, cognate_max, false_friend=false_friend,
                                  length=length, is_construction=is_construction,
                                  irregular=irregular)
    stability = stability_prior(cognate_max)
    return Item(key=key, traces={
        int(Modality.RECOGNITION): Trace(stability, difficulty, now),
        int(Modality.PRODUCTION): Trace(stability, difficulty, now),
    })


def observe(item: Item, channel: Channel, now: float,
            grade: Grade = Grade.GOOD) -> list[Modality]:
    """Apply one observation. Returns which traces moved.

    Routing is the load-bearing part:
      exposures  -> recognition only, attenuated. Production is never inferred
                    from having been shown something.
      recall/produce/correct -> production graded in full, recognition credited
                    at half, because producing a word proves you recognise it.
      insert     -> nothing moves. Copying is not producing.
    """
    eta = ETA[channel]
    if eta <= 0.0:
        return []

    moved: list[Modality] = []

    if channel in GRADED_CHANNELS:
        effective_grade = Grade.AGAIN if grade == Grade.AGAIN else grade
        _apply_graded(item, Modality.PRODUCTION, effective_grade, now)
        moved.append(Modality.PRODUCTION)
        # Producing a word is strong evidence you recognise it, but it is
        # indirect, so it lands as a half-weight exposure rather than a grade.
        if effective_grade != Grade.AGAIN:
            _apply_exposure(item, Modality.RECOGNITION, 0.5, now)
            moved.append(Modality.RECOGNITION)
    else:
        _apply_exposure(item, Modality.RECOGNITION, eta, now)
        item.traces[int(Modality.RECOGNITION)].exposures += 1
        moved.append(Modality.RECOGNITION)

    return moved


def _apply_graded(item: Item, modality: Modality, grade: Grade, now: float) -> None:
    trace = item.traces[int(modality)]
    elapsed = (now - trace.last_event_at) / SECONDS_PER_DAY
    r = retrievability(trace.stability, elapsed)

    if trace.reps == 0 and trace.effective_reps == 0.0:
        trace.stability = initial_stability(grade)
        trace.difficulty = initial_difficulty(grade)
        trace.last_graded_failed = grade == Grade.AGAIN
        if grade == Grade.AGAIN:
            trace.lapses += 1
    elif grade == Grade.AGAIN:
        trace.stability = stability_after_failure(trace.stability, trace.difficulty, r)
        trace.difficulty = next_difficulty(trace.difficulty, grade)
        trace.lapses += 1
        trace.last_graded_failed = True
    elif elapsed < 1.0 / 24.0:
        trace.stability = stability_same_day(trace.stability, grade)
        trace.difficulty = next_difficulty(trace.difficulty, grade)
        trace.last_graded_failed = False
    else:
        trace.stability = stability_after_success(trace.stability, trace.difficulty, r, grade)
        trace.difficulty = next_difficulty(trace.difficulty, grade)
        trace.last_graded_failed = False

    trace.reps += 1
    trace.effective_reps += 1.0
    trace.last_event_at = now


def _apply_exposure(item: Item, modality: Modality, eta: float, now: float) -> None:
    trace = item.traces[int(modality)]
    elapsed = (now - trace.last_event_at) / SECONDS_PER_DAY
    r = retrievability(trace.stability, elapsed)
    trace.stability = stability_after_exposure(trace.stability, trace.difficulty, r, eta)
    # Difficulty deliberately untouched.
    trace.effective_reps += eta
    trace.last_event_at = now


def mastery(item: Item, now: float) -> float:
    """Derived for display only. NEVER a decision variable.

    Weighted toward production because that is the product's stated goal.
    """
    recognition = item.traces[int(Modality.RECOGNITION)].retrievability(now)
    production = item.traces[int(Modality.PRODUCTION)].retrievability(now)
    return 0.35 * recognition + 0.65 * production


# How far ahead to ask "will they still know this".
#
# One day is too short to see the damage a lapse does. After a failure that
# collapses stability from 20 days to 2.3, retrievability one day later is still
# 0.95, which reads as "known". Seven days matches how this product is actually
# used: you do not text someone about arriving late every single day, so the next
# time an item is genuinely needed is a week away, not tomorrow.
SUPPRESSION_HORIZON_DAYS = 7.0


def should_suppress(item: Item, now: float, *, threshold: float = 0.90,
                    min_evidence: float = 2.0,
                    horizon_days: float = SUPPRESSION_HORIZON_DAYS) -> bool:
    """Whether to stay quiet about this item.

    Three conditions, and each exists because of a specific failure.

    Retrievability is evaluated at a HORIZON, not at `now`. Immediately after any
    event `last_event_at == now`, so elapsed is zero and R is 1.0 by definition,
    including immediately after a FAILED recall. Asking "do they know it this
    instant" would therefore suppress the item the user just got wrong. The
    question that matters is "will they still know it when they next need it".

    Evidence must be real. This is the guard against research 06's failure mode
    F3: a word the learner has merely been SHOWN many times climbing to 'known',
    the assistance fading, and the learner never learning it while the system
    congratulates itself. Exposures contribute at most their efficacy weight, so
    reaching the floor by being glanced at takes an implausible number of glances.

    The most recent graded outcome being a failure is an outright veto. The
    arithmetic already reduces stability, but a fresh lapse is a direct statement
    that the learner could not produce this word, and no projected probability
    should be allowed to talk over it.
    """
    production = item.traces[int(Modality.PRODUCTION)]
    if production.last_graded_failed:
        return False
    future = now + horizon_days * SECONDS_PER_DAY
    elapsed = (future - production.last_event_at) / SECONDS_PER_DAY
    projected = retrievability(production.stability, elapsed)
    return projected >= threshold and production.effective_reps >= min_evidence
