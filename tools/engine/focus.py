#!/usr/bin/env python3
"""Choose what to teach in one sentence.

Replaces the PRD's threshold ladder, which was monotone in a single number while
its own stated requirements were multi-objective, and which handed the LEAST
effective gloss format to the newest items.

    value = learning_gain x need x readiness - intrusion

Deterministic on purpose. Research 10 argued this is one of three capabilities
that are BETTER without a model: a scoring function can be ablated, and
reproducibility is what makes the project's evaluation criteria answerable at
all. You cannot ablate an LLM's choice of focus word, and if it picks
differently on identical input the A/B arms stop meaning anything.
"""
from __future__ import annotations

import json
import re
import unicodedata
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import fsrs
from fsrs import Channel, Item, Modality
from lexicon import Reading, Tables


@lru_cache(maxsize=1)
def interference() -> dict[str, dict]:
    """The curated false-friend list, keyed by Spanish lemma.

    This is the AUTHORITY on what is a false friend. The orthographic
    `cognate_it` score is not, and must never be used as one: it is
    semantics-free by design, and 90% of common Spanish lemmas score high on it
    for an Italian speaker. Treating "looks Italian" as "means something else"
    flags `llegar`~`legare` and `comprar`~`comprare`, which are true cognates and
    exactly the words a learner gets for free.
    """
    path = Path(__file__).resolve().parents[2] / "data" / "interference.json"
    if not path.exists():
        return {}
    payload = json.loads(path.read_text())
    out: dict[str, dict] = {}
    for group in ("italian", "english"):
        for row in payload.get(group, []):
            out.setdefault(unicodedata.normalize("NFC", row["es"]).lower(),
                           {**row, "language": group})
    return out

# At most one vocabulary concept and one grammar note per sentence. Kept from
# the PRD, which was right about this and stricter than most products.
BUDGET_VOCABULARY = 1
BUDGET_GRAMMAR = 1

# Below this, teach nothing.
#
# PRD section 25: "The learning UI should disappear when it has nothing useful to
# teach." That is the single best line in the visual-design section and it needs
# a number to be real. Without a floor the selector always returns its
# best-of-a-bad-lot, so a sentence containing only words the learner already
# knows still gets annotated, and the bar becomes something to ignore. Research
# 06 predicts banner blindness within weeks; a bar that is silent most of the
# time is what buys attention when it does speak.
MIN_TEACHING_VALUE = 0.85

WORD = re.compile(r"[^\W\d_]+", re.UNICODE)

# Never teach these. Function words carry the grammar, not the vocabulary, and a
# learner does not need `de` glossed.
SKIP_POS = {"PREP", "CONJ", "DET", "ART", "PRON", "PROP", "NUM", "CONTR"}

# A paradigm cell is only worth a grammar note when the cell itself carries a
# lesson. "masculine singular noun" is not a lesson; "first person singular
# present subjunctive" is. Without this filter every sentence produces a grammar
# note about noun gender, which is noise and burns the one-note budget.
TEACHABLE_CELL_TAGS = {
    "IND", "SBJV", "IMP", "COND", "FUT", "PST", "PRS", "IPFV", "PFV",
    "V.CVB", "V.PTCP", "NFIN",
}

# Above this Zipf a word is acquired from exposure alone and does not need the
# teaching budget spent on it. `ser`, `estar`, `que` and `de` are not vocabulary
# lessons however common they are.
FREE_BY_EXPOSURE_ZIPF = 6.6


@dataclass
class Candidate:
    surface: str
    reading: Reading
    key: str
    score: float
    reason: str
    kind: str          # "vocabulary" or "grammar"


def tokenize(sentence: str) -> list[str]:
    return WORD.findall(unicodedata.normalize("NFC", sentence))


def pick_reading(readings: list[Reading]) -> tuple[Reading, bool]:
    """Choose one reading, and say whether the choice was ambiguous.

    Ambiguity is 26.6% of surfaces, and it matters downstream: research 06's rule
    is that an ambiguous resolution must never write a graded learning event,
    only a low-weight exposure. So the flag travels with the reading rather than
    being quietly dropped.

    The heuristic is most-frequent-lemma, which is the honest baseline. The real
    disambiguators are NLTagger's context-sensitive tag and the
    translator-alignment check, neither of which exists off-device.
    """
    if not readings:
        raise ValueError("no readings")
    best = max(readings, key=lambda r: (r.zipf, r.has_features))
    distinct_lemmas = {r.lemma for r in readings}
    return best, len(distinct_lemmas) > 1


def score(reading: Reading, item: Item | None, now: float,
          *, ambiguous: bool, seen_this_session: int = 0) -> tuple[float, str]:
    """Teaching value of one candidate, and why."""
    # Learning gain. Desirable difficulty falls straight out of the memory model:
    # a prompt at R around 0.85 has near-maximal expected gain, one at R near
    # 0.99 has almost none. No separate "mastery < 0.95" rule needed.
    if item is None:
        difficulty = fsrs.difficulty_prior(reading.zipf, reading.cognate_max)
        stability = fsrs.stability_prior(reading.cognate_max)
        r = 1.0
        evidence = 0.0
    else:
        trace = item.traces[int(Modality.PRODUCTION)]
        difficulty, stability = trace.difficulty, trace.stability
        r = trace.retrievability(now)
        evidence = trace.effective_reps

    gain = fsrs._growth(stability, difficulty, r) if item is not None else 1.0
    readiness = 1.0 - abs(r - 0.85) / 0.85 if item is not None else 0.6

    # Will they need it again. Corpus frequency is the crude proxy; once ~5000
    # tokens of the user's own writing exist, personal frequency should be
    # blended in and weighted at least as heavily.
    need = min(1.0, reading.zipf / 7.0)

    # Is it actually new to them. For an English-plus-Italian speaker this does
    # more work than a CEFR level would: 90% of common Spanish lemmas look
    # familiar to an Italian speaker, so the ones that do not are the real
    # vocabulary load.
    novelty = 1.0 - reading.cognate_max

    # A false friend is worth teaching precisely BECAUSE it looks familiar, so
    # this is the one place similarity raises the score. Membership in the
    # curated list is the test, NOT the orthographic score.
    trap = interference().get(reading.lemma)
    trap_bonus = 0.9 if trap else 0.0

    # Very common words are acquired from exposure without help. Spending the
    # one-per-sentence budget on `ser` teaches nothing and trains the learner to
    # ignore the bar.
    if reading.zipf >= FREE_BY_EXPOSURE_ZIPF and not trap:
        need *= 0.15

    # Intrusion. Repeating within one session is the fastest route to the bar
    # being learned-ignored.
    intrusion = 0.35 * seen_this_session
    if ambiguous:
        # Teaching the wrong sense is worse than teaching nothing.
        intrusion += 0.4

    value = (0.45 * gain + 0.25 * need + 0.20 * novelty + 0.10 * readiness
             + trap_bonus - intrusion)

    if trap:
        reason = (f"false friend: looks like {trap.get('it_lookalike') or trap['trap']!r}, "
                  f"actually means {trap['means']!r}")
    elif reading.zipf >= FREE_BY_EXPOSURE_ZIPF:
        reason = "very common, acquired from exposure"
    elif novelty > 0.6:
        reason = "not a cognate, genuinely new"
    elif evidence > 0 and r < 0.85:
        reason = "due for review"
    elif need > 0.8:
        reason = "very common"
    else:
        reason = "useful"
    return value, reason


def select(sentence: str, tables: Tables, state: dict[str, Item], now: float,
           *, session_counts: dict[str, int] | None = None) -> list[Candidate]:
    """Pick at most one vocabulary item and one grammar note for this sentence."""
    session_counts = session_counts or {}
    vocabulary: list[Candidate] = []
    grammar: list[Candidate] = []

    def suppressed(key: str) -> bool:
        """Ask the memory model whether to stay quiet about this item.

        This is the link between the two layers, and it has to be a hard veto
        rather than a score adjustment. A false friend carries a large constant
        teaching bonus, so without a veto a trap the learner has demonstrably
        mastered would keep being taught forever, which is precisely the
        "assistance never fades" complaint the adaptive design exists to fix.

        `should_suppress` requires real production evidence, so exposure alone
        can never buy this silence.
        """
        item = state.get(key)
        return item is not None and fsrs.should_suppress(item, now)

    for surface in tokenize(sentence):
        readings = tables.lookup(surface)
        if not readings:
            continue
        reading, ambiguous = pick_reading(readings)
        if reading.pos in SKIP_POS:
            continue

        key = reading.lemma_key()
        if suppressed(key):
            continue
        value, reason = score(reading, state.get(key), now, ambiguous=ambiguous,
                              seen_this_session=session_counts.get(key, 0))
        vocabulary.append(Candidate(surface, reading, key, value, reason, "vocabulary"))

        cell = reading.cell_key()
        if (cell and not suppressed(cell)
                and any(tag in TEACHABLE_CELL_TAGS for tag in reading.feats.split(";")[1:])):
            cell_value, cell_reason = score(
                reading, state.get(cell), now, ambiguous=ambiguous,
                seen_this_session=session_counts.get(cell, 0))
            # A paradigm cell is worth teaching when the FORM is the new thing,
            # which is exactly when the lemma itself is already familiar.
            cell_value += 0.3 * reading.cognate_max
            grammar.append(Candidate(surface, reading, cell, cell_value,
                                     cell_reason, "grammar"))

    vocabulary.sort(key=lambda c: -c.score)
    grammar.sort(key=lambda c: -c.score)

    chosen = [c for c in vocabulary if c.score >= MIN_TEACHING_VALUE][:BUDGET_VOCABULARY]
    # Never let the grammar note land on the same word as the vocabulary note.
    # Two annotations on one token reads as clutter and violates the budget's
    # intent even while satisfying its letter.
    taken = {c.surface for c in chosen}
    chosen += [c for c in grammar
               if c.surface not in taken and c.score >= MIN_TEACHING_VALUE][:BUDGET_GRAMMAR]
    return chosen
