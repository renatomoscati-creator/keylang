#!/usr/bin/env python3
"""Reference implementation of the event log and the fold over it.

The Swift is in LinguaKeyApp/Sources/StudyKit/{Event,EventLog,ItemStore}.swift.
This exists so the two can be pinned to each other by golden vectors, because
the interesting failures are not arithmetic: they are a field renamed on one
side, a channel raw value that does not match, or a nil optional encoded as
`null` where the other side expects it absent.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any

import fsrs
from fsrs import Channel, Grade

SCHEMA = 1

# Swift encodes a `Grade?` with `encodeIfPresent`, so nil is an ABSENT key and
# never `null`. Anything written here must follow the same rule or the Swift
# decoder will disagree about what an ungraded event looks like.
OPTIONAL_KEYS = ("grade", "features", "sourceApp")


@dataclass
class Event:
    id: str
    at: float
    itemKey: str
    channel: Channel
    arm: str
    surface: str
    grade: Grade | None = None
    features: dict[str, Any] | None = None
    sourceApp: str | None = None
    sentenceHash: int = 0
    schema: int = SCHEMA

    def to_json(self) -> dict:
        out = {
            "schema": self.schema,
            "id": self.id,
            "at": self.at,
            "itemKey": self.itemKey,
            "channel": self.channel.name,
            "arm": self.arm,
            "surface": self.surface,
            "sentenceHash": self.sentenceHash,
        }
        if self.grade is not None:
            out["grade"] = int(self.grade)
        if self.features is not None:
            out["features"] = self.features
        if self.sourceApp is not None:
            out["sourceApp"] = self.sourceApp
        return out


def features(zipf: float, cognate_max: float, *, false_friend: bool = False,
             is_construction: bool = False, irregular: bool = False,
             length: int = 0) -> dict:
    return {
        "zipf": zipf,
        "cognateMax": cognate_max,
        "falseFriend": false_friend,
        "isConstruction": is_construction,
        "irregular": irregular,
        "length": length,
    }


def fold(events: list[Event]) -> dict[str, fsrs.Item]:
    """Exactly what ItemStore.apply does, in the same order."""
    items: dict[str, fsrs.Item] = {}
    for event in events:
        item = items.get(event.itemKey)
        if item is None:
            # An event with no features still has to create a usable item, so
            # the defaults here and in the Swift must agree.
            f = event.features or {"zipf": 3.0, "cognateMax": 0.0}
            item = fsrs.new_item(
                event.itemKey,
                zipf=f.get("zipf", 3.0),
                cognate_max=f.get("cognateMax", 0.0),
                false_friend=f.get("falseFriend", False),
                length=f.get("length", 0),
                is_construction=f.get("isConstruction", False),
                irregular=f.get("irregular", False),
                now=event.at,
            )
            items[event.itemKey] = item
        fsrs.observe(item, event.channel, now=event.at,
                     grade=event.grade if event.grade is not None else Grade.GOOD)
    return items


def snapshot(trace: fsrs.Trace, now: float) -> dict:
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


def to_lines(events: list[Event]) -> str:
    return "".join(json.dumps(e.to_json(), separators=(",", ":")) + "\n"
                   for e in events)
