# Build-time data pipeline

The iPhone 13 cannot run Foundation Models, so the teaching layer is **data authored at build
time** rather than a model prompted at runtime (research 10 §5). This is where that data is
built. It runs on a Mac or Linux box, never on device.

Nothing downloaded is committed. The build outputs are, each with provenance and licence in
`manifest.json`.

```bash
tools/build-data/fetch.sh                                   # download sources
python3 tools/build-data/build_morphology.py --top-lemmas 5000
python3 tools/build-data/check_morphology.py                # must exit 0
```

## Why this exists

`NLTagger`'s `.lemma` for Spanish is UNVERIFIED across research 03 and 10, and Apple documents it
as returning a *"stem"* form rather than a citation form. `llegaré → lleg` is useless; you need
`llegaré → llegar, indicative future 1sg`. A bundled table is deterministic, auditable, and
does not depend on a probe outcome.

## Measured results

Top 5000 lemmas by corpus frequency:

| | |
|---|---|
| Surfaces | 130,175 |
| Lemmas | 4,645 |
| Feature combinations | 162 |
| **Total on disk** | **3.67 MB** |
| Ambiguous surfaces | 26.6% |

Against a 25 MB extension budget, `mmap`'d read-only so clean file-backed pages stay evictable
and are not charged to `phys_footprint` the way dirty anonymous pages are. **Probe P2b in Phase 01
verifies that accounting; until it does, the budget headroom is LIKELY, not CONFIRMED.**

Pruning curve, if the size ever needs to move:

| Lemmas kept | Surfaces | UniMorph rows |
|---|---|---|
| 3,000 | 80,239 | 111,381 |
| 5,000 | 119,555 | 166,179 |
| 10,000 | 198,604 | 275,302 |
| 25,000 | 362,608 | 499,709 |

## Three findings the build produced

**1. UniMorph misses 45% of the top 100 Spanish lemmas.** Including `tener` (rank 16), `venir`,
`poner`, `escribir`, `recibir`. It also carries only `V`, `N` and `ADJ`, so every adverb,
pronoun, preposition, conjunction and determiner is absent. On device this would have shown up as
silently failing to lemmatise the sixteenth most common verb in the language.

The fix is a second source: the frequency list's `usage` column supplies surface → lemma for the
frequent words UniMorph omits. Every reading therefore carries a **source byte** — `0` UniMorph
with full features, `1` usage with lemma and POS only. **A source-1 reading must not drive a
`CELL:` paradigm item, only a `LEM:` one.**

**2. 26.6% of surfaces are genuinely ambiguous**, and the table represents that rather than
picking a winner. Research 06 measured the frequency list alone as pre-disambiguated with 0
ambiguous surfaces, which reads as clean data and is actually lost information. The rule from
research 06 is therefore load-bearing for roughly a quarter of tokens: **an ambiguous resolution
must never write a graded learning event, only a low-weight exposure.**

**3. Ambiguity coverage is incomplete, and the gap is one-directional.** Where the frequency list
pre-assigned a surface to one lemma and UniMorph does not cover the other, the second reading is
gone. `vino` resolves to the noun (wine) and never to the preterite of `venir` (came). So **a
surface resolving to exactly one lemma is not proof that only one reading exists.** The
self-check asserts this explicitly, and will fail if it ever improves, so the improvement gets
noticed rather than absorbed.

Mitigations, cheapest first: `NLTagger`'s context-sensitive tag as a tie-breaker; the
translator-alignment check from research 10 (translate the focus word alone, see whether it
appears in the sentence translation); or a third morphology source.

## Format

All files are `mmap`'d read-only. **Never decode into a dictionary at runtime.**

| File | Contents |
|---|---|
| `surfaces.blob` / `.idx` | Sorted UTF-8 surfaces, u32 offsets. Binary-search the index, compare into the blob |
| `entries.bin` / `.idx` | 8-byte readings `(lemma u32, pos u8, source u8, featset u16)`. `idx[i]..idx[i+1]` are the readings of `surfaces[i]` |
| `lemmas.blob` / `.idx` | Interned lemma strings |
| `featsets.blob` / `.idx` | Interned UniMorph feature strings. Only 162 combinations, so interning costs 4 KB and saves megabytes |
| `zipf.bin` | f32 per lemma, parallel to the lemma table. `log10(per billion) + 3` |
| `manifest.json` | Counts, byte sizes, coverage measurements, sources, licences, and the caveats above |

**Normalisation:** NFC and lowercased. NFC is non-negotiable, because iOS hands you decomposed
and precomposed accents depending on whether text was typed, pasted or autocorrected. **Accents
are preserved** — `esta`/`está`, `papa`/`papá`, `si`/`sí` and `el`/`él` are different words, and
folding them is the classic mistake.

## Licence

Sources are **CC BY-SA 3.0** (UniMorph, and the OpenSubtitles-derived frequency lists). CC BY-SA
is copyleft on the *data*, and a derived compiled table is plausibly an adaptation, so the
generated artifacts ship with attribution and are published alongside the app. **This does not
affect the app's own source licence.** Confirm before any public release.
