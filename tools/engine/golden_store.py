#!/usr/bin/env python3
"""Emit a real event log and the state it must fold to.

Two files:

  build/golden/store-events.jsonl  byte for byte what EventLog would contain,
                                   including a torn final line and a record from
                                   a schema this build does not understand
  build/golden/store-golden.json   the fold, plus how many lines must be skipped

The Swift test copies the log into a temporary App Group, reads it back through
the real EventLog, folds it through the real ItemStore, and compares. That
exercises the JSON field names, the channel raw values, the absent-versus-null
rule for optionals, the torn-line tolerance and the fold arithmetic in one pass,
none of which are checkable on a machine with no Swift compiler.
"""
from __future__ import annotations

import json
from pathlib import Path

import fsrs
import store
from fsrs import Channel, Grade

DAY = fsrs.SECONDS_PER_DAY

# Deterministic, readable, and obviously not real UUIDs.
def uid(n: int) -> str:
    return f"00000000-0000-4000-8000-{n:012d}"


def build() -> tuple[list[store.Event], list[str], dict]:
    events: list[store.Event] = []
    n = 0

    def add(**kwargs) -> None:
        nonlocal n
        n += 1
        events.append(store.Event(id=uid(n), **kwargs))

    # A false friend, taught in arm A, then recalled, then failed, then relearned.
    # The failure matters: last_graded_failed vetoes suppression, and getting the
    # veto wrong is invisible until an item the learner just got wrong goes quiet.
    add(at=0.0, itemKey="LEM:vaso|N|0", channel=Channel.EXPOSE_GLANCED, arm="A",
        surface="vaso", sentenceHash=1234567890123456789,
        features=store.features(4.6, 1.0, false_friend=True, length=4),
        sourceApp="com.apple.mobilesafari")
    add(at=0.0, itemKey="LEM:vaso|N|0", channel=Channel.EXPOSE_DWELLED, arm="A",
        surface="vaso", sentenceHash=1234567890123456789)
    add(at=1 * DAY, itemKey="LEM:vaso|N|0", channel=Channel.RECALL, arm="A",
        surface="vaso", grade=Grade.GOOD, sentenceHash=1234567890123456789)
    add(at=4 * DAY, itemKey="LEM:vaso|N|0", channel=Channel.RECALL, arm="A",
        surface="vasos", grade=Grade.AGAIN, sentenceHash=222)
    add(at=4 * DAY + 600, itemKey="LEM:vaso|N|0", channel=Channel.RECALL, arm="A",
        surface="vaso", grade=Grade.HARD, sentenceHash=222)

    # Arm B: exposed, revealed without answering, then answered easily. The
    # reveal is a TAPPED and not a grade, and that difference is the whole basis
    # of the efficacy weighting.
    add(at=2 * DAY, itemKey="LEM:pan|N|0", channel=Channel.EXPOSE_GLANCED, arm="B",
        surface="pan", features=store.features(5.2, 0.9, false_friend=True, length=3))
    add(at=2 * DAY + 30, itemKey="LEM:pan|N|0", channel=Channel.TAPPED, arm="B",
        surface="pan")
    add(at=9 * DAY, itemKey="LEM:pan|N|0", channel=Channel.RECALL, arm="B",
        surface="pan", grade=Grade.EASY)

    # Arm C: exposure only, forever. This is the item that must NEVER reach a
    # state where the selector goes quiet about it.
    for day in range(0, 40, 2):
        add(at=day * DAY, itemKey="LEM:salir|V|0", channel=Channel.EXPOSE_GLANCED,
            arm="C", surface="salgo",
            features=store.features(5.8, 0.7) if day == 0 else None)

    # A paradigm cell, which is a construction and has no gloss of its own.
    add(at=3 * DAY, itemKey="CELL:V|IND,FUT,1,SG", channel=Channel.EXPOSE_DWELLED,
        arm="A", surface="llegaré".encode().decode(),
        features=store.features(6.05, 1.0, is_construction=True))
    add(at=10 * DAY, itemKey="CELL:V|IND,FUT,1,SG", channel=Channel.RECALL, arm="A",
        surface="llegaré", grade=Grade.GOOD)

    # An item whose LAST graded event was a failure. The suppression rule vetoes
    # on that flag alone, and getting the veto wrong is invisible until an item
    # the learner just got wrong goes quiet.
    add(at=1 * DAY, itemKey="LEM:pronto|ADV|0", channel=Channel.EXPOSE_DWELLED,
        arm="A", surface="pronto",
        features=store.features(5.5, 0.95, false_friend=True, length=6))
    for day in (2, 5, 12, 25):
        add(at=day * DAY, itemKey="LEM:pronto|ADV|0", channel=Channel.RECALL,
            arm="A", surface="pronto", grade=Grade.EASY)
    add(at=38 * DAY, itemKey="LEM:pronto|ADV|0", channel=Channel.RECALL, arm="A",
        surface="pronto", grade=Grade.AGAIN)

    # And one that is genuinely known, so the vector pins BOTH answers of the
    # suppression rule and not just the negative one.
    add(at=0.0, itemKey="LEM:agua|N|0", channel=Channel.EXPOSE_DWELLED, arm="B",
        surface="agua", features=store.features(5.9, 1.0, length=4))
    for day in (1, 3, 8, 20, 40):
        add(at=day * DAY, itemKey="LEM:agua|N|0", channel=Channel.RECALL, arm="B",
            surface="agua", grade=Grade.EASY)

    # An event with no features at all, from a build that stopped sending them.
    add(at=5 * DAY, itemKey="LEM:desconocido|N|0", channel=Channel.EXPOSE_DWELLED,
        arm="B", surface="desconocido")

    # INSERTED has efficacy zero: copying is not producing. The item must exist
    # and must not have moved.
    add(at=6 * DAY, itemKey="LEM:copiado|N|0", channel=Channel.EXPOSE_GLANCED,
        arm="A", surface="copiado", features=store.features(3.1, 0.2))
    add(at=6 * DAY + 5, itemKey="LEM:copiado|N|0", channel=Channel.INSERTED,
        arm="A", surface="copiado")

    # Lines the reader must skip without losing the rest.
    corrupt = [
        json.dumps({"schema": 99, "id": uid(999), "at": 0.0,
                    "itemKey": "LEM:futuro|N|0", "channel": "TELEPATHY",
                    "arm": "A", "surface": "futuro", "sentenceHash": 0}),
        "this line is not JSON at all",
        "",                       # blank lines are not corruption
        '{"schema":1,"id":"00000000-0000-4000-8000-000000000998","at":1.0,',
    ]
    return events, corrupt, {}


def main() -> None:
    events, corrupt, _ = build()
    now = 45 * DAY
    items = store.fold(events)

    log = store.to_lines(events)
    # The last entry is a torn line with no trailing newline, exactly what a
    # jetsam kill part-way through a write leaves behind.
    log += corrupt[0] + "\n" + corrupt[1] + "\n" + corrupt[2] + "\n" + corrupt[3]

    payload = {
        "_comment": (
            "The Swift must read store-events.jsonl through the real EventLog,"
            " fold it through the real ItemStore, and reproduce this. Regenerate"
            " with tools/engine/golden_store.py."
        ),
        "tolerance": 1e-9,
        "now": now,
        "event_count": len(events),
        # A blank line is not corruption and must not be counted.
        "skipped_lines": 3,
        "complete_byte_count": len(store.to_lines(events).encode("utf-8"))
                               + len((corrupt[0] + "\n" + corrupt[1] + "\n"
                                      + corrupt[2] + "\n").encode("utf-8")),
        "items": {
            key: {
                "recognition": store.snapshot(item.traces[0], now),
                "production": store.snapshot(item.traces[1], now),
                "mastery": fsrs.mastery(item, now),
                "suppress": fsrs.should_suppress(item, now),
            }
            for key, item in sorted(items.items())
        },
    }

    root = Path(__file__).resolve().parents[2] / "build" / "golden"
    root.mkdir(parents=True, exist_ok=True)
    (root / "store-events.jsonl").write_text(log, encoding="utf-8")
    (root / "store-golden.json").write_text(json.dumps(payload, indent=1) + "\n",
                                            encoding="utf-8")
    print(f"{len(events)} events, {len(payload['items'])} items -> {root}")


if __name__ == "__main__":
    main()
