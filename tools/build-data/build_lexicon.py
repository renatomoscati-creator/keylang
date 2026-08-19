#!/usr/bin/env python3
"""Build the gloss, gender and cognate-distance tables.

Three artifacts, all derived at build time and all `mmap`'d read-only on device:

  glosses   lemma -> a short English gloss. Most-frequent-sense baseline, which
            is roughly 60-70% correct on all-words WSD and better on the
            high-frequency lemmas in short sentences that this product sees.
            Research 10's translator-alignment check is the runtime mitigation.

  gender    noun -> masculine or feminine. Feeds the single highest-value
            deterministic correction rule for an English or Italian speaker:
            `*la problema` is caught, `el problema grande` is left alone.

  cognate   how much a Spanish lemma looks like something the learner already
            knows, separately for English and Italian. This is the cold-start
            difficulty prior, and research 10 argued it is a better feature than
            CEFR level for this specific user: a B2-labelled Latinate word may be
            free, while an A1 word like `pero`/`però` or `salir`/`salire` is a trap.

The cognate signal is deliberately orthographic and semantics-free. High
orthographic similarity plus a matching gloss is a true cognate and should lower
difficulty. High similarity WITHOUT a matching gloss is exactly the false-friend
shape, and research 06 found false cognates are easier on FORM and harder on
MEANING, which is why the two traces are scored separately.
"""
from __future__ import annotations

import argparse
import io
import json
import math
import re
import struct
import unicodedata
from collections import defaultdict
from pathlib import Path

VERSION = 1

# Romance and Latinate affix correspondences. Normalising these before measuring
# edit distance is what makes `nación`/`nation`/`nazione` read as one word rather
# than three. Order matters: longest first.
AFFIX_RULES = [
    ("ción", "tion"), ("cion", "tion"), ("zione", "tion"), ("sión", "sion"),
    ("dad", "ity"), ("tà", "ity"), ("tad", "ity"),
    ("mente", "ly"),
    ("ancia", "ance"), ("encia", "ence"), ("anza", "ance"), ("enza", "ence"),
    ("oso", "ous"), ("osa", "ous"),
    ("ario", "ary"), ("aria", "ary"),
    ("ismo", "ism"), ("ista", "ist"),
    ("izar", "ize"), ("izzare", "ize"),
    ("ar", ""), ("er", ""), ("ir", ""),       # Spanish infinitives
    ("are", ""), ("ere", ""), ("ire", ""),    # Italian infinitives
]

STOP_GLOSS_WORDS = {
    "a", "an", "the", "to", "of", "or", "and", "any", "some", "that", "this",
    "used", "form", "forms", "obsolete", "archaic", "alternative", "spelling",
}


def strip_accents(text: str) -> str:
    decomposed = unicodedata.normalize("NFD", text)
    return "".join(c for c in decomposed if unicodedata.category(c) != "Mn")


def skeleton(word: str) -> str:
    """Collapse a word to a cross-language comparable form.

    Accent-stripped, affix-normalised, and with the orthographic differences that
    are purely conventional between these three languages folded away: Spanish
    `ph` never occurs where English has it, `qu`/`c`/`k` alternate, double
    consonants are Italian-conventional, and `y`/`i` alternate freely.
    """
    word = strip_accents(word.lower())
    for src, dst in AFFIX_RULES:
        if word.endswith(src) and len(word) - len(src) >= 3:
            word = word[: -len(src)] + dst
            break
    word = word.replace("ph", "f").replace("qu", "k").replace("ch", "k")
    word = word.replace("cc", "c").replace("ll", "l").replace("tt", "t")
    word = word.replace("ss", "s").replace("zz", "z").replace("mm", "m")
    word = word.replace("nn", "n").replace("pp", "p").replace("ff", "f")
    word = word.replace("y", "i").replace("k", "c").replace("z", "s")
    word = re.sub(r"[^a-z]", "", word)
    return word


def similarity(a: str, b: str) -> float:
    """Normalised Levenshtein similarity in [0, 1] over skeletons."""
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    if abs(len(a) - len(b)) / max(len(a), len(b)) > 0.5:
        return 0.0
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1,
                               previous[j - 1] + (ca != cb)))
        previous = current
    return 1.0 - previous[-1] / max(len(a), len(b))


def parse_wiktionary(path: Path) -> tuple[dict[str, dict[str, str]], dict[str, str]]:
    """Return (lemma -> {pos: first gloss}, noun -> gender)."""
    glosses: dict[str, dict[str, str]] = defaultdict(dict)
    genders: dict[str, str] = {}

    headword = None
    pos = None
    with io.open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if line == "_____":
                headword, pos = None, None
                continue
            if headword is None:
                headword = unicodedata.normalize("NFC", line.strip()).lower()
                continue
            if line.startswith("pos: "):
                pos = line[5:].strip()
                continue
            stripped = line.strip()
            if stripped.startswith("g: ") and pos == "n" and headword not in genders:
                value = stripped[3:].strip()
                if value in ("m", "f"):
                    genders[headword] = value
            elif stripped.startswith("gloss: ") and pos and pos not in glosses[headword]:
                gloss = stripped[7:].strip()
                # Skip pointer entries; they define nothing on their own.
                lowered = gloss.lower()
                # Pointer entries define nothing. `alternative case form of
                # "internet"` is not a gloss, it is a redirect, and showing it to
                # a learner is worse than showing nothing.
                if re.match(r"^(obsolete|alternative|archaic|rare|dated|nonstandard|"
                            r"informal|superseded|eye dialect|pronunciation|"
                            r"abbreviation|misspelling|inflection|feminine|masculine|"
                            r"plural|singular|clipping|contraction|apocopic|"
                            r"syncopic|synonym|ellipsis)\b[^.]{0,30}\b(form|spelling|"
                            r"of)\b", lowered):
                    continue
                glosses[headword][pos] = gloss
    return glosses, genders


def gloss_headword(gloss: str) -> str:
    """The content word an English gloss is really about.

    `(transitive) to arrive somewhere` -> `arrive`. Used only for cognate
    scoring, never shown to the user.
    """
    gloss = re.sub(r"\([^)]*\)", " ", gloss)
    gloss = re.sub(r"\"[^\"]*\"", " ", gloss)
    for word in re.findall(r"[a-zA-Z]+", gloss):
        lowered = word.lower()
        if lowered not in STOP_GLOSS_WORDS and len(lowered) > 2:
            return lowered
    return ""


def load_word_list(path: Path, limit: int) -> list[str]:
    words = []
    with io.open(path, encoding="utf-8") as handle:
        for line in handle:
            parts = line.split()
            if parts:
                words.append(unicodedata.normalize("NFC", parts[0]).lower())
            if len(words) >= limit:
                break
    return words


def build(sources: Path, out: Path, morphology: Path) -> dict:
    manifest_path = morphology / "manifest.json"
    if not manifest_path.exists():
        raise SystemExit(f"run build_morphology.py first (no {manifest_path})")

    # The lemma table is the join key: build lexicon entries for exactly the
    # lemmas the morphology table can resolve to, in the same order, so the
    # device can index both with one id.
    lemma_blob = (morphology / "lemmas.blob").read_bytes()
    lemma_idx = (morphology / "lemmas.idx").read_bytes()
    count = len(lemma_idx) // 4 - 1
    offsets = struct.unpack(f"<{count + 1}I", lemma_idx)
    lemmas = [lemma_blob[offsets[i]:offsets[i + 1]].decode("utf-8") for i in range(count)]
    print(f"joining against {len(lemmas)} lemmas from the morphology build")

    print("parsing wiktionary...")
    glosses, genders = parse_wiktionary(sources / "es-en.data")
    print(f"  {len(glosses)} headwords with a gloss, {len(genders)} nouns with gender")

    print("loading english and italian frequency lists...")
    english = load_word_list(sources / "en-forms-50k.txt", 30000)
    italian = load_word_list(sources / "it-forms-50k.txt", 30000)

    # A trigram inverted index over the Italian vocabulary. Comparing every
    # Spanish lemma against all 30,000 Italian words is quadratic and takes
    # minutes; requiring two shared trigrams first cuts each search to a few
    # dozen candidates and costs one pass to build.
    def trigrams(word: str) -> set[str]:
        padded = f"^{word}$"
        return {padded[i:i + 3] for i in range(len(padded) - 2)}

    italian_index: dict[str, list[int]] = defaultdict(list)
    italian_skeletons: list[tuple[str, str]] = []
    for word in italian:
        skel = skeleton(word)
        if len(skel) < 3:
            continue
        position = len(italian_skeletons)
        italian_skeletons.append((word, skel))
        for gram in trigrams(skel):
            italian_index[gram].append(position)
    print(f"  indexed {len(italian_skeletons)} italian skeletons "
          f"over {len(italian_index)} trigrams")
    english_skeletons = {}
    for word in english:
        skel = skeleton(word)
        if len(skel) >= 3:
            english_skeletons.setdefault(skel, word)

    print("scoring...")
    gloss_out: list[str] = []
    gender_out: list[int] = []      # 0 unknown, 1 masculine, 2 feminine
    cog_en_out: list[float] = []
    cog_it_out: list[float] = []
    it_match_out: list[str] = []

    for lemma in lemmas:
        entry = glosses.get(lemma, {})
        # Prefer the POS most likely to be the teachable sense.
        gloss = ""
        for pos in ("v", "n", "adj", "adv", "prep", "pron", "conj", "num", "interj"):
            if pos in entry:
                gloss = entry[pos]
                break
        if not gloss and entry:
            gloss = next(iter(entry.values()))
        gloss_out.append(gloss[:120])

        gender = genders.get(lemma, "")
        gender_out.append({"m": 1, "f": 2}.get(gender, 0))

        skel = skeleton(lemma)

        # English: compare against the headword of the lemma's own gloss, which
        # is a real translation pair rather than a coincidence.
        head = gloss_headword(gloss)
        cog_en = similarity(skel, skeleton(head)) if head else 0.0
        # A Spanish word that IS an English word (hotel, taxi, internet) is free.
        if skel in english_skeletons:
            cog_en = max(cog_en, 0.95)
        cog_en_out.append(round(cog_en, 3))

        # Italian: no ES->IT dictionary is available, so this measures whether the
        # word LOOKS like something an Italian speaker knows. That is the right
        # question for a difficulty prior, and it deliberately does not check
        # meaning, so false friends score high here by design.
        best, best_word = 0.0, ""
        if len(skel) >= 3:
            hits: dict[int, int] = defaultdict(int)
            for gram in trigrams(skel):
                for position in italian_index.get(gram, ()):
                    hits[position] += 1
            # Two shared trigrams is the floor for a plausible cognate. Anything
            # below that cannot reach the 0.7 threshold this feeds.
            candidates = [p for p, n in hits.items() if n >= 2]
            for position in candidates:
                word, candidate = italian_skeletons[position]
                score = similarity(skel, candidate)
                if score > best:
                    best, best_word = score, word
                    if best == 1.0:
                        break
        cog_it_out.append(round(best, 3))
        it_match_out.append(best_word if best >= 0.7 else "")

    out.mkdir(parents=True, exist_ok=True)

    def write_strings(values: list[str], stem: str) -> None:
        blob = io.BytesIO()
        offsets = []
        for value in values:
            offsets.append(blob.tell())
            blob.write(value.encode("utf-8"))
        offsets.append(blob.tell())
        (out / f"{stem}.blob").write_bytes(blob.getvalue())
        (out / f"{stem}.idx").write_bytes(struct.pack(f"<{len(offsets)}I", *offsets))

    write_strings(gloss_out, "glosses")
    write_strings(it_match_out, "italian_lookalike")
    (out / "gender.bin").write_bytes(bytes(gender_out))
    (out / "cognate_en.bin").write_bytes(struct.pack(f"<{len(cog_en_out)}f", *cog_en_out))
    (out / "cognate_it.bin").write_bytes(struct.pack(f"<{len(cog_it_out)}f", *cog_it_out))

    with_gloss = sum(1 for g in gloss_out if g)
    with_gender = sum(1 for g in gender_out if g)
    strong_en = sum(1 for c in cog_en_out if c >= 0.7)
    strong_it = sum(1 for c in cog_it_out if c >= 0.7)

    sizes = {p.name: p.stat().st_size
             for p in sorted(out.iterdir()) if p.suffix in (".bin", ".blob", ".idx")}
    manifest = {
        "format": "keylang-lexicon",
        "version": VERSION,
        "lemmas": len(lemmas),
        "coverage": {
            "with_gloss": with_gloss,
            "with_gloss_pct": round(100 * with_gloss / len(lemmas), 1),
            "with_gender": with_gender,
            "cognate_en_over_0.7": strong_en,
            "cognate_en_over_0.7_pct": round(100 * strong_en / len(lemmas), 1),
            "cognate_it_over_0.7": strong_it,
            "cognate_it_over_0.7_pct": round(100 * strong_it / len(lemmas), 1),
        },
        "bytes": sizes,
        "bytes_total": sum(sizes.values()),
        "sources": [
            {"name": "doozan/spanish_data es-en.data (Wiktionary)", "licence": "CC BY-SA"},
            {"name": "hermitdave FrequencyWords en/it", "licence": "CC BY-SA 3.0"},
        ],
        "notes": [
            "Glosses are a most-frequent-sense baseline, roughly 60-70% correct on"
            " all-words WSD. Mitigate at runtime with the translator-alignment"
            " check: translate the focus word alone and see whether it appears in"
            " the sentence translation. If it does not, show the sentence pair"
            " rather than a gloss.",
            "cognate_it is orthographic and semantics-free by design. It answers"
            " 'does this look like a word the learner knows', which is the right"
            " question for a difficulty prior. False friends therefore score HIGH."
            " Pair it with a curated false-friend list before using it to lower"
            " the difficulty of a meaning.",
            "Arrays are parallel to the morphology lemma table and share its ids.",
        ],
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, default=Path("build/sources"))
    parser.add_argument("--morphology", type=Path, default=Path("build/morphology"))
    parser.add_argument("--out", type=Path, default=Path("build/lexicon"))
    args = parser.parse_args()

    manifest = build(args.sources, args.out, args.morphology)
    print()
    coverage = manifest["coverage"]
    print(f"  gloss coverage    {coverage['with_gloss']:,} / {manifest['lemmas']:,} "
          f"({coverage['with_gloss_pct']}%)")
    print(f"  noun gender       {coverage['with_gender']:,}")
    print(f"  cognate en >=0.7  {coverage['cognate_en_over_0.7']:,} "
          f"({coverage['cognate_en_over_0.7_pct']}%)")
    print(f"  cognate it >=0.7  {coverage['cognate_it_over_0.7']:,} "
          f"({coverage['cognate_it_over_0.7_pct']}%)")
    total = manifest["bytes_total"]
    print(f"  total             {total:,} bytes ({total / 1_048_576:.2f} MB)")


if __name__ == "__main__":
    main()
