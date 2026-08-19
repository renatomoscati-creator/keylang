#!/usr/bin/env python3
"""Emit golden vectors for arm assignment.

Separate from fsrs-golden.json on purpose: the memory model and the experiment
design change for different reasons and at different times, and a single file
would make a change to either look like a change to both.
"""
from __future__ import annotations

import json
from pathlib import Path

import arms

SALTS = ["", "salt-1", "8B0F2C11-3A4D-4E5F-9A7B-1C2D3E4F5A6B", "ñ-acentuado"]

KEYS = [
    "LEM:vaso|N|0",
    "LEM:pan|N|0",
    "LEM:salir|V|0",
    "LEM:pronto|ADV|0",
    "LEM:llegar|V|0",
    "CELL:V|IND,FUT,1,SG",
    "CELL:V|SBJV,PRS,2,SG",
    "CELL:N|MASC,SG",
    "",
    "unicode:ñ|N|0",
]


def main() -> None:
    hashes = {text: str(arms.fnv1a64(text)) for text in [
        "", "a", "foobar", "LEM:vaso|N|0", "salt-1\x01LEM:vaso|N|0", "ñ",
    ]}
    assignments = [
        {"salt": salt, "key": key, "arm": arms.arm(salt, key)}
        for salt in SALTS for key in KEYS
    ]

    # A distribution the Swift can assert without carrying 100k rows.
    bulk_keys = [f"LEM:word{i}|N|0" for i in range(10_000)]
    distribution = {a: 0 for a in arms.ARMS}
    for key in bulk_keys:
        distribution[arms.arm("distribution-salt", key)] += 1

    payload = {
        "_comment": (
            "Arm assignment must be byte-identical across processes, launches and"
            " implementations. Hashes are decimal strings because JSON numbers"
            " cannot carry a UInt64 exactly. Regenerate with"
            " tools/engine/golden_arms.py."
        ),
        "arms": list(arms.ARMS),
        "fnv1a64": hashes,
        "assignments": assignments,
        "distribution": {
            "salt": "distribution-salt",
            "key_format": "LEM:word{i}|N|0",
            "count": len(bulk_keys),
            "counts": distribution,
        },
    }
    repo_root = Path(__file__).resolve().parents[2]
    out = repo_root / "build" / "golden" / "arms-golden.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, indent=1) + "\n")
    print(f"{len(assignments)} assignments -> {out}")


if __name__ == "__main__":
    main()
