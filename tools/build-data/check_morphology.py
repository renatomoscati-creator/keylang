#!/usr/bin/env python3
"""Self-check for the morphology table.

Reads the built artifacts exactly the way the Swift reader will: mmap, binary
search over the sorted offset index, no decoding of the whole table. If this
passes, the format is implementable on device. If it fails, the build is wrong.

Smallest thing that fails if the logic breaks. No framework.
"""
from __future__ import annotations

import json
import mmap
import struct
import sys
import unicodedata
from pathlib import Path


class Morphology:
    """Read-only mmap'd reader. Mirrors the intended Swift implementation."""

    def __init__(self, root: Path):
        self.root = root
        self.manifest = json.loads((root / "manifest.json").read_text())
        self._maps: list[mmap.mmap] = []

        self.surfaces_blob = self._map("surfaces.blob")
        self.surfaces_idx = self._map("surfaces.idx")
        self.lemmas_blob = self._map("lemmas.blob")
        self.lemmas_idx = self._map("lemmas.idx")
        self.featsets_blob = self._map("featsets.blob")
        self.featsets_idx = self._map("featsets.idx")
        self.entries = self._map("entries.bin")
        self.entries_idx = self._map("entries.idx")
        self.zipf = self._map("zipf.bin")

        self.count = self.manifest["counts"]["surfaces"]

    def _map(self, name: str) -> mmap.mmap:
        handle = open(self.root / name, "rb")
        mapped = mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ)
        self._maps.append(mapped)
        return mapped

    @staticmethod
    def _offset(idx: mmap.mmap, i: int) -> int:
        return struct.unpack_from("<I", idx, i * 4)[0]

    def _string(self, blob: mmap.mmap, idx: mmap.mmap, i: int) -> str:
        start = self._offset(idx, i)
        end = self._offset(idx, i + 1)
        return blob[start:end].decode("utf-8")

    def surface(self, i: int) -> str:
        return self._string(self.surfaces_blob, self.surfaces_idx, i)

    def lemma(self, i: int) -> str:
        return self._string(self.lemmas_blob, self.lemmas_idx, i)

    def featset(self, i: int) -> str:
        return self._string(self.featsets_blob, self.featsets_idx, i)

    def lemma_zipf(self, i: int) -> float:
        return struct.unpack_from("<f", self.zipf, i * 4)[0]

    def lookup(self, word: str) -> list[dict]:
        """Binary search for a surface form. Returns every reading, ambiguity included."""
        needle = unicodedata.normalize("NFC", word).lower()
        low, high = 0, self.count - 1
        found = -1
        while low <= high:
            mid = (low + high) // 2
            candidate = self.surface(mid)
            if candidate == needle:
                found = mid
                break
            if candidate < needle:
                low = mid + 1
            else:
                high = mid - 1
        if found < 0:
            return []

        start = self._offset(self.entries_idx, found)
        end = self._offset(self.entries_idx, found + 1)
        readings = []
        pos_names = {1: "V", 2: "N", 3: "ADJ"}
        for slot in range(start, end):
            lemma_id, pos_code, source, feat_id = struct.unpack_from(
                "<IBBH", self.entries, slot * 8)
            readings.append({
                "lemma": self.lemma(lemma_id),
                "pos": pos_names.get(pos_code, f"c{pos_code}"),
                "feats": self.featset(feat_id),
                "source": "unimorph" if source == 0 else "usage",
                "zipf": round(self.lemma_zipf(lemma_id), 2),
            })
        return readings


# Surfaces that must resolve, with the lemma the frequency list supplies but
# UniMorph does not. These exercise the merged second source: UniMorph omits
# tener, venir, poner and escribir entirely despite tener being the 16th most
# common lemma in Spanish.
USAGE_ONLY = [
    ("tengo",   "tener"),
    ("vengo",   "venir"),
    ("pongo",   "poner"),
    ("escribo", "escribir"),
]

# (surface, expected lemma, a feature substring that must appear)
CASES = [
    ("llegaré",  "llegar", "FUT"),
    ("llegué",   "llegar", "PST"),
    ("llegando", "llegar", "V.CVB"),
    ("hablaré",  "hablar", "FUT"),
    ("comeré",   "comer",  "FUT"),
    ("soy",      "ser",    "PRS"),
    ("estoy",    "estar",  "PRS"),

    ("dijo",     "decir",  "PST"),
]

# Surfaces that MUST resolve to more than one reading. Ambiguity is real Spanish
# and the table represents it rather than silently picking a winner. An ambiguous
# resolution must never write a graded learning event.
AMBIGUOUS = ["como", "sobre", "nada"]

# Known limitation, asserted so a future improvement is noticed rather than
# silently absorbed.
#
# `vino` is both the noun (wine) and the 3sg preterite of `venir` (came). Neither
# source can express that. UniMorph omits `venir` entirely, and the frequency
# list pre-disambiguates: 0 of its 159,097 surfaces map to more than one lemma,
# so it assigned `vino` to the noun and dropped it from `venir`'s form list.
#
# The mitigations, in order of cost: NLTagger's context-sensitive tag as a
# tie-breaker; the translator-alignment check from research 10 (translate the
# focus word alone and see whether it appears in the sentence translation); or a
# third morphology source. Until then, a surface that resolves to exactly one
# lemma is not proof that only one reading exists.
KNOWN_LOSSY = [("vino", "vino", "venir")]


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "build/morphology")
    if not (root / "manifest.json").exists():
        print(f"FAIL: no build at {root}")
        return 1

    morph = Morphology(root)
    failures: list[str] = []

    for word, expected_lemma, expected_feat in CASES:
        readings = morph.lookup(word)
        if not readings:
            failures.append(f"{word}: not found")
            continue
        lemmas = {r["lemma"] for r in readings}
        if expected_lemma not in lemmas:
            failures.append(f"{word}: lemma {sorted(lemmas)} does not include {expected_lemma}")
            continue
        matching = [r for r in readings if r["lemma"] == expected_lemma]
        if not any(expected_feat in r["feats"] for r in matching):
            failures.append(
                f"{word}: no reading with {expected_feat}, got "
                f"{[r['feats'] for r in matching]}")
            continue
        best = next(r for r in matching if expected_feat in r["feats"])
        print(f"  ok  {word:<10} -> {best['lemma']:<10} {best['feats']:<34} "
              f"zipf {best['zipf']}"
              + (f"  ({len(readings)} readings)" if len(readings) > 1 else ""))

    for word, expected_lemma in USAGE_ONLY:
        readings = morph.lookup(word)
        lemmas = {r["lemma"] for r in readings}
        if expected_lemma not in lemmas:
            failures.append(
                f"{word}: expected {expected_lemma} from the usage source, got {sorted(lemmas)}")
        else:
            reading = next(r for r in readings if r["lemma"] == expected_lemma)
            print(f"  ok  {word:<10} -> {reading['lemma']:<10} "
                  f"[source: {reading['source']}, features unavailable]")

    for word in AMBIGUOUS:
        readings = morph.lookup(word)
        if len(readings) < 2:
            failures.append(f"{word}: expected ambiguity, got {len(readings)} reading(s)")
        else:
            lemmas = sorted({r["lemma"] for r in readings})
            print(f"  ok  {word:<10} -> ambiguous across {lemmas}")

    for word, resolves_to, missing in KNOWN_LOSSY:
        readings = morph.lookup(word)
        lemmas = {r["lemma"] for r in readings}
        if missing in lemmas:
            failures.append(
                f"{word}: now resolves to {missing} too. That is an IMPROVEMENT, not a"
                f" regression. Move it out of KNOWN_LOSSY and update the manifest note.")
        elif lemmas != {resolves_to}:
            failures.append(f"{word}: expected only {resolves_to}, got {sorted(lemmas)}")
        else:
            print(f"  ok  {word:<10} -> {resolves_to} only "
                  f"(known lossy: {missing} unrecoverable from these sources)")

    # A word that is genuinely not in the table must return nothing rather than
    # a wrong guess. Silence is a valid answer.
    if morph.lookup("qwertzuiop"):
        failures.append("nonsense input resolved to something")
    else:
        print("  ok  unknown word resolves to nothing, as it should")

    # Sorted-order invariant: binary search is only correct if this holds.
    previous = ""
    for i in range(min(morph.count, 5000)):
        current = morph.surface(i)
        if current < previous:
            failures.append(f"surfaces out of order at {i}: {previous!r} > {current!r}")
            break
        previous = current
    else:
        print(f"  ok  surface table sorted (checked {min(morph.count, 5000)})")

    print()
    if failures:
        print(f"FAIL: {len(failures)} problem(s)")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    total = morph.manifest["bytes_total"]
    counts = morph.manifest["counts"]
    print(f"PASS: {counts['surfaces']:,} surfaces, {counts['lemmas']:,} lemmas, "
          f"{total / 1_048_576:.2f} MB, "
          f"{100 * counts['ambiguous_surfaces'] / counts['surfaces']:.1f}% ambiguous")
    return 0


if __name__ == "__main__":
    sys.exit(main())
