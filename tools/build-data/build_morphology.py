#!/usr/bin/env python3
"""Build the Spanish surface -> (lemma, POS, features) table.

This replaces NLTagger's `.lemma`, which research 03 and 10 both left UNVERIFIED
for Spanish and which Apple documents as returning a "stem" form rather than a
citation form. A bundled table is deterministic, auditable, and answers
`llegare -> llegar, indicative future 1sg` rather than `lleg`.

Output is a set of flat binary files designed to be `mmap`'d read-only. Clean
file-backed pages are evictable and are not charged to `phys_footprint` the way
dirty anonymous pages are, which is what makes the data affordable inside a
25 MB keyboard extension. Never decode this into a dictionary at runtime.

Format is documented in format.md and verified by check_morphology.py.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import struct
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

MAGIC = b"KLMO"           # keylang morphology
VERSION = 1

# UniMorph's POS tags, mapped to a byte. Order is stable and must not be
# renumbered without bumping VERSION.
POS_CODES = {"V": 1, "N": 2, "ADJ": 3}

# Coarse POS from the frequency list's own tagging, for readings that UniMorph
# does not cover. Numbered above the UniMorph range so the two never collide.
USAGE_POS_CODES = {
    "v": 1, "n": 2, "adj": 3,
    "adv": 10, "pron": 11, "prep": 12, "conj": 13, "determiner": 14,
    "art": 15, "num": 16, "interj": 17, "prop": 18, "contraction": 19,
}

# A reading's provenance. UniMorph readings carry full morphological features;
# usage readings carry lemma and POS only and must not drive paradigm items.
SOURCE_UNIMORPH = 0
SOURCE_USAGE = 1


def normalize(text: str) -> str:
    """NFC, lowercased.

    NFC is non-negotiable: iOS hands you decomposed and precomposed accents
    depending on whether text was typed, pasted, or autocorrected, and the two
    are different bytes for the same word. Accents are NOT stripped: esta/esta,
    papa/papa, si/si and el/el are different words.
    """
    return unicodedata.normalize("NFC", text).lower()


def load_frequency(path: Path) -> dict[str, int]:
    """Lemma -> occurrence count, from the OpenSubtitles-derived list."""
    freq: dict[str, int] = {}
    with io.open(path, encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            lemma = normalize(row["spanish"])
            count = int(row["count"])
            freq[lemma] = max(freq.get(lemma, 0), count)
    return freq


def load_usage_forms(path: Path) -> list[tuple[str, str, str]]:
    """(lemma, surface, pos) from the frequency list's `usage` column.

    This exists because UniMorph spa is missing 45% of the top-100 Spanish
    lemmas, including `tener`, `venir`, `poner`, `escribir` and `recibir`, and
    carries only V, N and ADJ, so every adverb, pronoun, preposition,
    conjunction and determiner is absent. Measured, not assumed: see
    `coverage` in the manifest.

    The trade is explicit. UniMorph gives full morphological features
    (`llegare -> llegar, IND;FUT;1;SG`). This gives lemma and POS only
    (`tengo -> tener, v`). A reading tagged `source: "usage"` therefore cannot
    drive a `CELL:` paradigm item, only a `LEM:` one. Better than the alternative,
    which is silently failing to lemmatise the sixteenth most common verb.
    """
    triples: list[tuple[str, str, str]] = []
    with io.open(path, encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            lemma = normalize(row["spanish"])
            pos = (row.get("pos") or "").strip().lower()
            usage = row.get("usage") or ""
            for chunk in usage.split("|"):
                if ":" not in chunk:
                    continue
                _, _, surface = chunk.partition(":")
                surface = normalize(surface.strip())
                if surface:
                    triples.append((lemma, surface, pos))
    return triples


def load_unimorph(path: Path) -> list[tuple[str, str, str]]:
    """(lemma, surface, features) triples. Malformed lines are counted, not guessed at."""
    triples: list[tuple[str, str, str]] = []
    malformed = 0
    with io.open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            parts = line.split("\t")
            if len(parts) != 3:
                malformed += 1
                continue
            lemma, surface, feats = parts
            triples.append((normalize(lemma), normalize(surface), feats))
    if malformed:
        print(f"  warning: {malformed} malformed UniMorph lines skipped", file=sys.stderr)
    return triples


def build(sources: Path, out: Path, top_lemmas: int) -> dict:
    print("loading frequency...")
    freq = load_frequency(sources / "es-frequency.csv")
    print(f"  {len(freq)} lemmas with frequency")

    print("loading unimorph...")
    triples = load_unimorph(sources / "spa-unimorph.tsv")
    print(f"  {len(triples)} triples")

    # UniMorph's verb row count is exactly 1048576 (2^20), which is almost
    # certainly a generation cap rather than a natural total. Record it so the
    # coverage claim stays honest rather than implied.
    verb_rows = sum(1 for _, _, f in triples if f.split(";")[0] == "V")
    capped = verb_rows == 2 ** 20

    # Keep only lemmas the user is plausibly going to meet. Ranking by corpus
    # frequency is the crude version; once there are ~5000 tokens of the user's
    # own writing, personal frequency should be blended in and this rebuilt.
    ranked = sorted(freq.items(), key=lambda kv: -kv[1])
    keep = {lemma for lemma, _ in ranked[:top_lemmas]}
    print(f"keeping top {top_lemmas} lemmas by frequency")

    kept = [t for t in triples if t[0] in keep]
    print(f"  {len(kept)} triples survive")

    print("loading usage forms (covers what UniMorph omits)...")
    usage = load_usage_forms(sources / "es-frequency.csv")
    usage_kept = [t for t in usage if t[0] in keep]
    print(f"  {len(usage_kept)} usage triples for kept lemmas")

    # Measure the hole rather than asserting it. This number is the reason the
    # second source exists and belongs in the manifest.
    unimorph_lemmas = {lemma for lemma, _, _ in triples}
    coverage = {}
    for n in (100, 500, 1000, 3000, 5000):
        head = [lemma for lemma, _ in ranked[:n]]
        absent = sum(1 for lemma in head if lemma not in unimorph_lemmas)
        coverage[f"top_{n}"] = {
            "lemmas": n,
            "absent_from_unimorph": absent,
            "percent": round(100 * absent / n, 1),
        }
    print(f"  UniMorph misses {coverage['top_100']['percent']}% of the top 100 lemmas")

    # Intern the three string vocabularies. Feature combinations repeat heavily,
    # so a combo table costs a few KB and saves megabytes.
    lemmas: dict[str, int] = {}
    featsets: dict[str, int] = {}
    by_surface: dict[str, list[tuple[int, int, int]]] = defaultdict(list)

    # UniMorph first, so its fully-featured readings sort ahead of the coarse ones.
    for lemma, surface, feats in kept:
        pos_tag = feats.split(";")[0]
        pos_code = POS_CODES.get(pos_tag)
        if pos_code is None:
            continue
        lemma_id = lemmas.setdefault(lemma, len(lemmas))
        feat_id = featsets.setdefault(feats, len(featsets))
        entry = (lemma_id, pos_code, feat_id, SOURCE_UNIMORPH)
        if entry not in by_surface[surface]:
            by_surface[surface].append(entry)

    # Then the usage forms, but only where UniMorph said nothing about that
    # (surface, lemma) pair. UniMorph's features always win when both have it.
    featsets.setdefault("", 0) if not featsets else None
    unknown_feats = featsets.setdefault("_", len(featsets))
    for lemma, surface, pos in usage_kept:
        pos_code = USAGE_POS_CODES.get(pos)
        if pos_code is None:
            continue
        lemma_id = lemmas.setdefault(lemma, len(lemmas))
        already = any(e[0] == lemma_id for e in by_surface.get(surface, ()))
        if already:
            continue
        entry = (lemma_id, pos_code, unknown_feats, SOURCE_USAGE)
        if entry not in by_surface[surface]:
            by_surface[surface].append(entry)

    if len(featsets) > 0xFFFF:
        raise SystemExit(f"featset table overflows u16: {len(featsets)}")

    surfaces = sorted(by_surface)
    print(f"  {len(surfaces)} unique surfaces, {len(lemmas)} lemmas, "
          f"{len(featsets)} feature combinations")

    ambiguous = sum(1 for s in surfaces if len(by_surface[s]) > 1)
    print(f"  {ambiguous} surfaces are ambiguous "
          f"({100 * ambiguous / max(1, len(surfaces)):.1f}%)")

    out.mkdir(parents=True, exist_ok=True)

    def write_string_table(names: list[str], stem: str) -> tuple[int, int]:
        blob = io.BytesIO()
        offsets = []
        for name in names:
            offsets.append(blob.tell())
            blob.write(name.encode("utf-8"))
        offsets.append(blob.tell())
        (out / f"{stem}.blob").write_bytes(blob.getvalue())
        (out / f"{stem}.idx").write_bytes(
            struct.pack(f"<{len(offsets)}I", *offsets))
        return blob.tell(), len(offsets) * 4

    # Surfaces are sorted so the reader can binary-search the offset index and
    # compare into the blob without materialising anything.
    write_string_table(surfaces, "surfaces")
    write_string_table([l for l, _ in sorted(lemmas.items(), key=lambda kv: kv[1])], "lemmas")
    write_string_table([f for f, _ in sorted(featsets.items(), key=lambda kv: kv[1])], "featsets")

    # Entries, run-length addressed: entry_index[i] .. entry_index[i+1] are the
    # readings of surfaces[i].
    entry_index = []
    entries = io.BytesIO()
    for surface in surfaces:
        entry_index.append(entries.tell() // 8)
        for lemma_id, pos_code, feat_id, source in by_surface[surface]:
            entries.write(struct.pack("<IBBH", lemma_id, pos_code, source, feat_id))
    entry_index.append(entries.tell() // 8)

    (out / "entries.bin").write_bytes(entries.getvalue())
    (out / "entries.idx").write_bytes(
        struct.pack(f"<{len(entry_index)}I", *entry_index))

    # Zipf frequency per lemma, parallel to the lemma table.
    # Zipf = log10(occurrences per billion) + 3, the standard scale.
    total = sum(freq.values())
    zipf = []
    for lemma, _ in sorted(lemmas.items(), key=lambda kv: kv[1]):
        count = freq.get(lemma, 0)
        if count and total:
            import math
            value = math.log10(count / total * 1e9) + 3.0
        else:
            value = 0.0
        zipf.append(max(0.0, value))
    (out / "zipf.bin").write_bytes(struct.pack(f"<{len(zipf)}f", *zipf))

    sizes = {p.name: p.stat().st_size for p in sorted(out.glob("*.bin"))}
    sizes.update({p.name: p.stat().st_size for p in sorted(out.glob("*.blob"))})
    sizes.update({p.name: p.stat().st_size for p in sorted(out.glob("*.idx"))})

    manifest = {
        "format": "keylang-morphology",
        "version": VERSION,
        "magic": MAGIC.decode(),
        "counts": {
            "surfaces": len(surfaces),
            "lemmas": len(lemmas),
            "featsets": len(featsets),
            "entries": entry_index[-1],
            "ambiguous_surfaces": ambiguous,
        },
        "build": {
            "top_lemmas": top_lemmas,
            "unimorph_triples_total": len(triples),
            "unimorph_triples_kept": len(kept),
            "unimorph_verb_rows_capped_at_2^20": capped,
            "usage_triples_kept": len(usage_kept),
        },
        "coverage": coverage,
        "bytes": sizes,
        "bytes_total": sum(sizes.values()),
        "sources": [
            {"name": "unimorph/spa", "licence": "CC BY-SA 3.0"},
            {"name": "doozan/spanish_data frequency.csv", "licence": "CC BY-SA 3.0"},
        ],
        "notes": [
            "Surfaces are NFC-normalised and lowercased. Accents are preserved:"
            " esta/esta, papa/papa, si/si and el/el are distinct words.",
            "mmap these read-only. Do not decode into a dictionary at runtime.",
            "Ambiguity is real and represented: a surface may carry several"
            " readings. An ambiguous resolution must never write a graded"
            " learning event, only a low-weight exposure.",
            "Readings carry a source byte. 0 = UniMorph, with full morphological"
            " features. 1 = the frequency list's usage column, lemma and POS only,"
            " which exists because UniMorph omits 45 percent of the top 100 lemmas"
            " including tener and venir. A source-1 reading must not drive a"
            " paradigm-cell item, only a lemma item.",
            "Ambiguity coverage is incomplete and the gap is one-directional."
            " The frequency list pre-disambiguates: 0 of its 159097 surfaces map"
            " to more than one lemma. So where it assigned a surface to one lemma"
            " and UniMorph does not cover the other, the second reading is lost."
            " `vino` resolves to the noun (wine) and not to the preterite of"
            " `venir` (came). A surface resolving to exactly one lemma is"
            " therefore NOT proof that only one reading exists. Break ties with"
            " NLTagger's context-sensitive tag, or with the translator-alignment"
            " check: translate the focus word alone and see whether it appears in"
            " the sentence translation.",
        ],
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, default=Path("build/sources"))
    parser.add_argument("--out", type=Path, default=Path("build/morphology"))
    parser.add_argument("--top-lemmas", type=int, default=5000,
                        help="how many lemmas to keep, ranked by corpus frequency")
    args = parser.parse_args()

    manifest = build(args.sources, args.out, args.top_lemmas)
    total = manifest["bytes_total"]
    print()
    print(f"total {total:,} bytes ({total / 1_048_576:.2f} MB) in {args.out}")
    for name, size in sorted(manifest["bytes"].items(), key=lambda kv: -kv[1]):
        print(f"  {size:>10,}  {name}")


if __name__ == "__main__":
    main()
