#!/usr/bin/env python3
"""Self-check for the gloss, gender and cognate tables.

Reads the artifacts the way the device will and asserts the things the teaching
layer depends on. Smallest thing that fails if the logic breaks.
"""
from __future__ import annotations

import json
import mmap
import re
import struct
import sys
from pathlib import Path


class Lexicon:
    def __init__(self, morphology: Path, lexicon: Path):
        self.manifest = json.loads((lexicon / "manifest.json").read_text())
        self._maps = []

        blob = (morphology / "lemmas.blob").read_bytes()
        idx = (morphology / "lemmas.idx").read_bytes()
        n = len(idx) // 4 - 1
        offsets = struct.unpack(f"<{n + 1}I", idx)
        self.lemmas = [blob[offsets[i]:offsets[i + 1]].decode("utf-8") for i in range(n)]
        self.index = {lemma: i for i, lemma in enumerate(self.lemmas)}

        self.gloss_blob, self.gloss_idx = self._strings(lexicon, "glosses")
        self.look_blob, self.look_idx = self._strings(lexicon, "italian_lookalike")
        self.gender = self._map(lexicon / "gender.bin")
        self.cog_en = self._map(lexicon / "cognate_en.bin")
        self.cog_it = self._map(lexicon / "cognate_it.bin")

    def _map(self, path: Path) -> mmap.mmap:
        handle = open(path, "rb")
        mapped = mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ)
        self._maps.append(mapped)
        return mapped

    def _strings(self, root: Path, stem: str):
        return self._map(root / f"{stem}.blob"), self._map(root / f"{stem}.idx")

    def _string(self, blob, idx, i: int) -> str:
        start = struct.unpack_from("<I", idx, i * 4)[0]
        end = struct.unpack_from("<I", idx, (i + 1) * 4)[0]
        return blob[start:end].decode("utf-8")

    def entry(self, lemma: str) -> dict | None:
        i = self.index.get(lemma)
        if i is None:
            return None
        return {
            "gloss": self._string(self.gloss_blob, self.gloss_idx, i),
            "gender": {0: "", 1: "m", 2: "f"}[self.gender[i]],
            "cog_en": round(struct.unpack_from("<f", self.cog_en, i * 4)[0], 2),
            "cog_it": round(struct.unpack_from("<f", self.cog_it, i * 4)[0], 2),
            "it_lookalike": self._string(self.look_blob, self.look_idx, i),
        }


# Words that must read as free for an English speaker. If the cold-start prior
# does not know these are easy, the per-sentence teaching budget gets spent on
# `hotel` instead of on something the learner does not know.
FREE_IN_ENGLISH = ["hotel", "taxi", "internet", "problema", "importante", "posible"]

# Nouns whose gender must be known, because gender agreement is the single
# highest-value deterministic correction rule for an EN or IT speaker.
# `problema` is the classic trap: it looks feminine and is masculine.
GENDER = [("problema", "m"), ("mano", "f"), ("agua", "f"), ("día", "m"), ("casa", "f")]

# Documented Italian false friends (research 06). Each must score HIGH on
# cognate_it, because that field is orthographic by design: it answers "does this
# look familiar", not "does it mean the same". These scoring high is the feature
# working correctly, and it is exactly why a curated false-friend list has to sit
# on top before cognate_it is used to LOWER the difficulty of a meaning.
FALSE_FRIENDS_IT = ["burro", "salir", "largo", "topo", "gamba", "caldo", "vaso", "carta"]


def main() -> int:
    morphology = Path(sys.argv[1] if len(sys.argv) > 1 else "build/morphology")
    lexicon = Path(sys.argv[2] if len(sys.argv) > 2 else "build/lexicon")
    lex = Lexicon(morphology, lexicon)
    failures: list[str] = []

    print("  free-for-an-English-speaker (cold start must not teach these):")
    for word in FREE_IN_ENGLISH:
        entry = lex.entry(word)
        if entry is None:
            failures.append(f"{word}: not in the lemma table")
            continue
        if entry["cog_en"] < 0.7:
            failures.append(f"{word}: cog_en {entry['cog_en']} is too low, should read as free")
        else:
            print(f"    ok  {word:<12} cog_en {entry['cog_en']:<5} "
                  f"cog_it {entry['cog_it']:<5} \"{entry['gloss'][:44]}\"")

    print("  noun gender (drives the agreement correction rule):")
    for word, expected in GENDER:
        entry = lex.entry(word)
        if entry is None:
            failures.append(f"{word}: not in the lemma table")
        elif entry["gender"] != expected:
            failures.append(f"{word}: gender {entry['gender']!r}, expected {expected!r}")
        else:
            note = " (looks feminine, is masculine)" if word == "problema" else ""
            print(f"    ok  {word:<12} {expected}{note}")

    print("  Italian false friends must score HIGH (orthographic by design):")
    for word in FALSE_FRIENDS_IT:
        entry = lex.entry(word)
        if entry is None:
            failures.append(f"{word}: not in the lemma table")
            continue
        if entry["cog_it"] < 0.7:
            failures.append(
                f"{word}: cog_it {entry['cog_it']} is too low. A false friend that does not"
                f" look familiar is not a false friend, so either the scoring or the"
                f" example is wrong.")
        else:
            print(f"    ok  {word:<12} cog_it {entry['cog_it']:<5} "
                  f"~ {entry['it_lookalike']:<12} \"{entry['gloss'][:40]}\"")

    print("  glosses are present and are not Wiktionary pointer entries:")
    pointers = 0
    for lemma in lex.lemmas:
        gloss = (lex.entry(lemma) or {}).get("gloss", "").lower()
        if re.match(r"^(obsolete|alternative|archaic|dated|nonstandard|superseded|"
                    r"pronunciation|abbreviation|misspelling|inflection|feminine|"
                    r"masculine|plural|singular|clipping|synonym)\b[^.]{0,30}\b"
                    r"(form|spelling|of)\b", gloss):
            pointers += 1
    if pointers:
        failures.append(f"{pointers} glosses are pointer entries and define nothing")
    else:
        print(f"    ok  0 pointer entries across {len(lex.lemmas)} lemmas")

    coverage = lex.manifest["coverage"]
    if coverage["with_gloss_pct"] < 95:
        failures.append(f"gloss coverage {coverage['with_gloss_pct']}% is below 95%")
    else:
        print(f"    ok  gloss coverage {coverage['with_gloss_pct']}%")

    print()
    if failures:
        print(f"FAIL: {len(failures)} problem(s)")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    total = lex.manifest["bytes_total"]
    print(f"PASS: {lex.manifest['lemmas']:,} lemmas, {total / 1024:.0f} KB, "
          f"{coverage['cognate_it_over_0.7_pct']}% look Italian, "
          f"{coverage['cognate_en_over_0.7_pct']}% look English")
    return 0


if __name__ == "__main__":
    sys.exit(main())
