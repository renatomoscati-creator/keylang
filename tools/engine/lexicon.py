#!/usr/bin/env python3
"""Read-only reader over the built tables.

Mirrors the intended Swift implementation exactly: mmap, binary search, no
decoding of the whole table into memory. If a change here cannot be expressed
the same way in Swift against `mmap`'d bytes, it is the wrong change.
"""
from __future__ import annotations

import json
import mmap
import struct
import unicodedata
from dataclasses import dataclass
from pathlib import Path

POS_NAMES = {1: "V", 2: "N", 3: "ADJ", 10: "ADV", 11: "PRON", 12: "PREP",
             13: "CONJ", 14: "DET", 15: "ART", 16: "NUM", 17: "INTERJ",
             18: "PROP", 19: "CONTR"}

SOURCE_UNIMORPH, SOURCE_USAGE = 0, 1


@dataclass(frozen=True)
class Reading:
    lemma: str
    lemma_id: int
    pos: str
    feats: str
    has_features: bool
    zipf: float
    gloss: str
    gender: str
    cognate_en: float
    cognate_it: float
    italian_lookalike: str

    @property
    def cognate_max(self) -> float:
        return max(self.cognate_en, self.cognate_it)

    def lemma_key(self) -> str:
        return f"LEM:{self.lemma}|{self.pos}|0"

    def cell_key(self) -> str | None:
        """The paradigm-cell item, lemma-independent, so seeing `hablaré` gives
        partial credit toward `llegaré`.

        Only exists for readings that carry real morphological features. A
        reading recovered from the frequency list has a lemma and a POS and
        nothing else, and inventing a cell for it would put noise into the
        model.
        """
        if not self.has_features:
            return None
        tags = [t for t in self.feats.split(";")[1:] if t]
        return f"CELL:{self.pos}|{','.join(tags)}" if tags else None


class Tables:
    def __init__(self, morphology: Path, lexicon: Path):
        self.morphology_manifest = json.loads((morphology / "manifest.json").read_text())
        self.lexicon_manifest = json.loads((lexicon / "manifest.json").read_text())
        self._maps: list[mmap.mmap] = []

        self.surfaces_blob = self._map(morphology / "surfaces.blob")
        self.surfaces_idx = self._map(morphology / "surfaces.idx")
        self.lemmas_blob = self._map(morphology / "lemmas.blob")
        self.lemmas_idx = self._map(morphology / "lemmas.idx")
        self.featsets_blob = self._map(morphology / "featsets.blob")
        self.featsets_idx = self._map(morphology / "featsets.idx")
        self.entries = self._map(morphology / "entries.bin")
        self.entries_idx = self._map(morphology / "entries.idx")
        self.zipf = self._map(morphology / "zipf.bin")

        self.gloss_blob = self._map(lexicon / "glosses.blob")
        self.gloss_idx = self._map(lexicon / "glosses.idx")
        self.look_blob = self._map(lexicon / "italian_lookalike.blob")
        self.look_idx = self._map(lexicon / "italian_lookalike.idx")
        self.gender = self._map(lexicon / "gender.bin")
        self.cognate_en = self._map(lexicon / "cognate_en.bin")
        self.cognate_it = self._map(lexicon / "cognate_it.bin")

        self.surface_count = self.morphology_manifest["counts"]["surfaces"]

    def _map(self, path: Path) -> mmap.mmap:
        handle = open(path, "rb")
        mapped = mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ)
        self._maps.append(mapped)
        return mapped

    @staticmethod
    def _u32(buffer: mmap.mmap, i: int) -> int:
        return struct.unpack_from("<I", buffer, i * 4)[0]

    def _string(self, blob: mmap.mmap, idx: mmap.mmap, i: int) -> str:
        return blob[self._u32(idx, i):self._u32(idx, i + 1)].decode("utf-8")

    def lookup(self, word: str) -> list[Reading]:
        needle = unicodedata.normalize("NFC", word).lower()
        low, high, found = 0, self.surface_count - 1, -1
        while low <= high:
            mid = (low + high) // 2
            candidate = self._string(self.surfaces_blob, self.surfaces_idx, mid)
            if candidate == needle:
                found = mid
                break
            low, high = (mid + 1, high) if candidate < needle else (low, mid - 1)
        if found < 0:
            return []

        readings = []
        for slot in range(self._u32(self.entries_idx, found),
                          self._u32(self.entries_idx, found + 1)):
            lemma_id, pos_code, source, feat_id = struct.unpack_from(
                "<IBBH", self.entries, slot * 8)
            feats = self._string(self.featsets_blob, self.featsets_idx, feat_id)
            readings.append(Reading(
                lemma=self._string(self.lemmas_blob, self.lemmas_idx, lemma_id),
                lemma_id=lemma_id,
                pos=POS_NAMES.get(pos_code, f"P{pos_code}"),
                feats=feats,
                has_features=source == SOURCE_UNIMORPH and feats not in ("", "_"),
                zipf=struct.unpack_from("<f", self.zipf, lemma_id * 4)[0],
                gloss=self._string(self.gloss_blob, self.gloss_idx, lemma_id),
                gender={0: "", 1: "m", 2: "f"}[self.gender[lemma_id]],
                cognate_en=struct.unpack_from("<f", self.cognate_en, lemma_id * 4)[0],
                cognate_it=struct.unpack_from("<f", self.cognate_it, lemma_id * 4)[0],
                italian_lookalike=self._string(self.look_blob, self.look_idx, lemma_id),
            ))
        return readings
