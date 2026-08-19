#!/usr/bin/env python3
"""Reference implementation of A/B/C arm assignment.

The Swift is in LinguaKeyApp/Sources/StudyKit/ArmAssignment.swift and is pinned
to this by golden vectors, because this function has a silent failure mode: a
process-seeded hash reassigns arms on every launch while looking like working
code, and nothing downstream would notice until the experiment was over and the
data was worthless.
"""
from __future__ import annotations

ARMS = ("A", "B", "C")

FNV_OFFSET = 14695981039346656037
FNV_PRIME = 1099511628211
MASK = (1 << 64) - 1


def fnv1a64(text: str) -> int:
    """FNV-1a, 64 bit, over UTF-8. Not Python's hash(), which is salted."""
    h = FNV_OFFSET
    for byte in text.encode("utf-8"):
        h ^= byte
        h = (h * FNV_PRIME) & MASK
    return h


def arm(salt: str, item_key: str) -> str:
    # A separator that cannot occur in either half, so salt "ab" + key "c" and
    # salt "a" + key "bc" are different inputs.
    return ARMS[fnv1a64(f"{salt}\x01{item_key}") % 3]
