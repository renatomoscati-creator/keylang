# Research 06 — Learning Science & Learning-Engine Design

> Source: research subagent, 2026-08-18. PRD §11, §13, §14, §21 under test.
> Evidence labels: **[C]** = primary source read directly (source code, dataset downloaded and
> measured, or verbatim quote). **[L]** = consistent paraphrase from a reliable secondary source or
> abstract. **[U]** = inference, no citation obtained.
> Publisher domains (Cambridge, OUP, ACM, CSAIL, ERIC, archive.org) were blocked by the sandbox proxy.

---

## 0. Bottom line

1. **The PRD has a priority inversion.** Its P0 features (Mode A passive translation, one-tap insert) are the *least* supported by the vocabulary-acquisition literature; its P1 features (Mode D active recall, Mode E correction, spaced repetition) are the *most* supported. In-text glosses are the **least effective** gloss type measured, multiple-choice glosses the **most** **[L]**. The "tap to insert the Spanish translation" button is, from a learning standpoint, actively harmful: it removes the *need* and *evaluation* components that predict retention **[L]**, and lets the user emit Spanish they cannot generate.
2. **The mastery model in §13 is not a memory model.** A stored float cannot decay, cannot distinguish "I recognise `llegaré`" from "I can produce `llegaré`", and conflates item difficulty with memory strength. Replace with a per-(item x modality) FSRS-6 DSR trace where `mastery` is *derived*, never stored.
3. **The core premise is half-right and the half that's wrong is the headline.** Micro-moments inside messaging *can* teach — WaitChatter's users learned ~57 words in two weeks **[L]** — but that system used *micro-quizzes*, not passive translations, and in the follow-up study chat was the **lowest-engagement** of all waiting contexts tested **[L]**. "Show a translation while someone is mid-message" is the weakest version of the idea. The tagline should be *retrieval* in the flow of typing, not *translation* in the flow of typing.

---

## 1. Spaced repetition, and reconciling it with incidental exposure

### 1.1 The algorithm landscape

| Algorithm | Memory state | Signal required | Status |
|---|---|---|---|
| SM-2 (1987) | E-factor + interval + reps | graded review 0-5 | baseline; no forgetting curve, no item features |
| Anki SM-2 variant | ease% + interval + lapses | Again/Hard/Good/Easy | "ease hell" — ease only ratchets down |
| **FSRS-6** | (Difficulty, Stability) -> Retrievability | graded review 1-4 | current default in Anki; 21 params |
| FSRS-7 / FSRS-recency | same | same | marginally better **[C]** |
| HLR (Duolingo, 2016) | half-life via log-linear regression on lexeme features | binary/partial recall | has *item features*; weaker fit **[C]** |
| Ebisu v3 | Bayesian (beta/gamma on recall prob) | supports **noisy-binary / soft** results | weakest fit in benchmark **[C]** |
| ACT-R / Pavlik-Anderson | summed decaying activation over *every* presentation | any presentation, graded or not | best theoretical fit to exposure |
| SlimStampen / MemoryLab | per-item rate-of-forgetting from **response latency** | timed retrieval | deployed, ~10 % efficiency gain **[L]** |

**FSRS current version and parameters** **[C]** — read directly from `fsrs-rs/src/model.rs`. FSRS-6 is **21 parameters**; shipped defaults:

```
[0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722,
 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425,
 0.0912, 0.0658, 0.1542]
```

Exact formulas (**[C]**, transcribed from source):

```
decay  = -w[20]                                   # -0.1542 with defaults
factor = exp(ln(0.9)/decay) - 1
R(t,S) = (t/S * factor + 1)^decay                 # POWER law, not exponential
I(S,r) = S/factor * (r^(1/decay) - 1)             # interval for desired retention r

S0(g)  = w[g-1],  g in 1..4
D0(g)  = w[4] - exp(w[5]*(g-1)) + 1
dampen(dD, D) = (10 - D) * dD / 9
D'     = w[7]*(D0(4) - d) + d      where d = D + dampen(-w[6]*(g-3), D)

S_success = S * ( exp(w[8]) * (11 - D) * S^(-w[9])
                  * (exp((1-R)*w[10]) - 1) * hard * easy + 1 )
            hard = w[15] if g==2 else 1 ;  easy = w[16] if g==4 else 1
S_fail    = min( w[11]*D^(-w[12])*((S+1)^w[13]-1)*exp((1-R)*w[14]),
                 S/exp(w[17]*w[18]) )
S_sameday = S * max(1, exp(w[17]*(g-3+w[18])) * S^(-w[19]))    # delta_t == 0
rating 0  = explicit no-op: state unchanged
```

Two properties matter enormously here:

- `(exp((1-R)*w[10]) - 1) -> 0 as R -> 1`. **The spacing effect is already built in**: a repetition when you already remember the item perfectly yields almost no stability gain. This is what makes FSRS safe to feed noisy incidental exposures into.
- `(11 - D)` couples difficulty to growth. Difficulty is *item-intrinsic* and near-stationary; stability is *trace-specific* and time-varying. The PRD's single `mastery` float collapses both.

**Open-source implementations** **[L]**: `fsrs-rs` (Rust reference optimizer, used by Anki), `py-fsrs`, `ts-fsrs`, `go-fsrs`, and for this product **`open-spaced-repetition/swift-fsrs`** (Swift Package, FSRS-6), plus third-party `4rays/swift-fsrs` (v5) and `bootuz/SwiftFSRS` (v6). **Verify the license of whichever Swift package you take before shipping in a closed-source App Store binary** **[U]**.

### 1.2 Evidence that FSRS beats SM-2

**[C]** from the `open-spaced-repetition/srs-benchmark` README, read directly: **~10,000 Anki collections, ~727M total reviews, 349.9M used for evaluation.** Metrics: log loss + RMSE(bins) for calibration, AUC for discrimination.

| Algorithm | Log loss | RMSE(bins) | AUC |
|---|---|---|---|
| RWKV-P (neural, not per-user fit) | 0.2773 | 0.02502 | 0.8329 |
| GRU | 0.3333 | 0.0556 | 0.7316 |
| FSRS-7 recency | 0.3414 | 0.0627 | 0.7097 |
| **FSRS-6** | **0.3460** | 0.0653 | 0.7034 |
| HLR (Duolingo) | 0.4694 | 0.1275 | 0.6369 |
| Ebisu v2 | 0.4989 | 0.1627 | 0.6051 |

**[L]** FSRS-6-recency estimates recall better than Anki's SM-2 with default parameters for **99.6 %** of collections; commonly cited practical figure is **20-30 % fewer reviews for equal retention**.

**Honest caveats to carry into the PRD:**
- This benchmark measures *predictive calibration on Anki review logs*, not *learning outcomes*. **Nobody has run an RCT showing FSRS produces more knowledge than SM-2** **[U]**. The 20-30 % figure is an efficiency simulation, not a measured learning gain.
- AUC ~0.70 is mediocre in absolute terms. A neural sequence model beats it by a wide margin, so FSRS is not near the ceiling.
- The population is self-selected Anki power users doing deliberate flashcard review. **Your user is not in this distribution.** Your review events will be rare, irregular, mixed with a flood of ungraded exposures, and the "interval" will usually not be under your control.

### 1.3 The real problem: your primary signal isn't a graded review

Every algorithm above assumes `(item, timestamp, grade)` where *the scheduler chose the timestamp*. Your primary signal is `(item, timestamp, the-user-happened-to-type-something-that-triggered-a-display)`. Two things break:

1. **Timing is exogenous.** FSRS's output — the optimal next interval — is largely unusable. You cannot make the user message someone about arriving late on day 12.
2. **The event is not graded.** "Shown a translation containing `llegaré`" is evidence of *exposure*, and possibly not even of attention.

Exposure -> learning conversion rate in the literature:

- **[L]** Uchihara, Webb & Yanagisawa (2019, *Language Learning*), meta-analysis, 45 effect sizes / 26 studies / N=1,918: repetition -> incidental vocabulary learning is **r = .34** (medium); encounters correlate r = .41 with learning but **account for only ~12-17 % of variance.** Repetition is necessary and radically insufficient.
- **[L]** Uchihara, Webb & Yanagisawa (2023, *Language Teaching*): **9-18 % of target words learned on immediate posttests, 6-17 % on delayed**; recognition exceeds recall.
- **[L]** van Zeeland & Webb (2018, *Language Learning*): mean **g = 1.05** from spoken input — large, but relative to a no-exposure baseline, not to deliberate study.
- **[L]** Webb, Yanagisawa & Uchihara (2020, *MLJ*): intentional/deliberate learning produces substantially higher retention than incidental conditions.

**Conclusion:** an incidental exposure is worth *something*, but roughly an order of magnitude less than a successful retrieval, and its value collapses if attention isn't engaged. The design must encode that ratio explicitly rather than pretending exposures and reviews are the same event type.

### 1.4 Recommended algorithm: FSRS-6 as an *estimator*, with attenuated exposure updates

Do not use FSRS as a scheduler. Use it as a **memory-state estimator** answering one question — `R(item, modality, now)` — and put scheduling in a separate policy layer reacting to what the user actually types.

**(a) Split the trace by modality.** Two DSR traces per item: `recognition` (ES->L1) and `production` (L1->ES). Shared `Difficulty` (item-intrinsic), separate `Stability`. **[L]** Receptive knowledge systematically exceeds productive; the gap narrows with proficiency. Since the product's *goal* is production, a model tracking only recognition will systematically overestimate readiness.

**(b) An exposure is a review with efficacy η, and it only touches the recognition trace.** Reuse `S_success` with a scalar η on the growth term:

```
S' = S * ( η * exp(w[8]) * (11 - D) * S^(-w[9]) * (exp((1-R)*w[10]) - 1) + 1 )
D' = D                       # an ungraded exposure is no evidence about difficulty
```

This inherits the spacing effect for free: as `R -> 1` the bracket -> 0, so ten exposures in one conversation are worth almost nothing. Suggested η by channel (priors to be *fitted*, see §7):

| Event | Trace | η | Rationale |
|---|---|---|---|
| Word appeared in the bar, no interaction, <800 ms dwell | recognition | 0.03 | plausibly not read at all |
| Word appeared, bar visible >=1.5 s, user continued typing | recognition | 0.10 | ~10 exposures ~= 1 review |
| User tapped the word for a breakdown / gloss / audio | recognition | 0.30 | attention confirmed; "search" occurred |
| User tapped **[Insert Spanish]** | *none* | **0** | copying is not producing — see §6.3 |
| Mode D recall **correct** | production (full) + recognition (η=0.5) | 1.0 | retrieval practice |
| Mode D recall **wrong / skipped** | production, `S_fail` | 1.0 | genuine lapse evidence |
| User typed the Spanish form themselves, unprompted, no assist | production (rating 4) + recognition (η=0.5) | 1.0 | **strongest signal in the system** |
| User typed Spanish, then requested help on that word | production, `S_fail` | 1.0 | explicit failure |
| Mode E correction accepted | production, `S_fail` then `S0` | 1.0 | error + feedback |

The ~10:1 exposure:review ratio operationalises r=.34 / ~12-17 % variance explained. Treat as a fitted parameter, not a fact **[U]**.

**(c) Cap what exposure alone can achieve.** Exposures never write to the production trace. This makes "exposure != productive knowledge" structural rather than a tuning parameter, and means the app can never claim mastery of a word the user has never once produced.

**Why not Ebisu's noisy-binary,** which looks tailor-made for fuzzy signals **[C]** (v3 supports soft-binary results)? Because it fits review data far worse (log loss 0.4989 vs 0.3460 **[C]**), and η-attenuation achieves the same partial-credit effect with a better-calibrated core.

**Why not ACT-R/Pavlik-Anderson,** the most theoretically apt (**[L]**: each presentation adds strength decaying as a power function, with each presentation's decay rate depending on activation at presentation time — this *is* the exposure model you want)? Because the practical delta over η-attenuated FSRS is small, FSRS has a maintained Swift package and a 350M-review calibration, and ACT-R has neither. Revisit only if §7's calibration test shows FSRS underfitting.

**Steal one thing from Duolingo HLR** **[C]**: its features are **lexeme tags** of the form `surface-form/lemma<pos>modifiers` (e.g. `camera.N.SG`), trained on 13M user-word pairs. FSRS has *no item features at all* — its cold start is "pick S₀ from the first rating," which for you is often no rating. Use lexeme-style features to set the priors (§2.5).

---

## 2. Critique of §13 (mastery float) and §14 (policy ladder)

### 2.1 Failure modes of the current model

| # | Failure | Why it breaks |
|---|---|---|
| **F1** | **A float does not decay.** `mastery: 0.72` is the same after 3 days and after 8 months. `last_seen_at` is stored but nothing in §14 reads it | The forgetting curve is the entire subject matter of spaced repetition. This model has no forgetting. Memory strength must be *computed from* `(S, D, elapsed)`, never stored |
| **F2** | **No recognition/production separation** | **[L]** Receptive exceeds productive. A user at `mastery: 0.85` from passive exposure will be shown nothing (§14 "normally show nothing") while unable to produce the word — which is the stated product goal. The model silently declares victory |
| **F3** | **Exposure != learning, but `exposures` is a first-class field feeding `mastery`** | **[L]** r = .34; ~12-17 % of variance. Any monotone `mastery <- f(exposures)` overstates knowledge, and overstatement is self-reinforcing: high mastery -> suppress teaching -> no further learning, but also no further evidence to correct the estimate. **The single most dangerous property of the current design** |
| **F4** | **No lemma/inflection distinction.** Is `llegaré` the same item as `llegar`? The PRD's own Mode B example annotates `LLEGARÉ` as "new construction" — so the PRD already knows the answer is no, but the data model can't express it | Spanish has ~50+ simple forms per verb plus clitic-attached forms. Keying on lemma makes `llegaré` unlearnable as a distinct thing; keying on surface form makes each verb 50 unrelated items and destroys transfer. Neither is right |
| **F5** | **No difficulty/stability separation** | FSRS's `(11 - D)` exists because a hard item gains stability slower at the same review success. One float cannot represent "I remember this well" and "this word is intrinsically hard" simultaneously — the second is nearly constant while the first swings |
| **F6** | **Cold start is undefined.** A new item has `mastery: 0.0`, so §14 fires "show translation + meaning" for every unseen word — including `hotel`, `taxi`, `problema`, `internet`, and every transparent EN/IT cognate | ~1/3 of a first Spanish message is free for an Italian speaker. Teaching them wastes the per-sentence budget and trains the user to ignore the bar |
| **F7** | **Thresholds are absolute, but §14's "additional factors" (recency, importance, UI budget) have no representation in the data** | The ladder is a total order on one number while the stated considerations are multi-objective. The policy as written cannot implement its own requirements |
| **F8** | **No confidence/uncertainty.** `mastery: 0.72` after 2 events and after 200 events are indistinguishable | With few events you should explore (test the user); with many, exploit (stay quiet). No field supports that |
| **F9** | **No sense distinction.** One `meaning_en` per lemma | `quedar` (remain / arrange to meet / fit), `tomar`, `dejar`, `pasar`. Knowing one sense is not knowing the word |
| **F10** | **`next_review_at` implies a review queue the keyboard cannot control** | Only the host app's Screen 4 can make a review happen. Storing a due date conflates "the model thinks R is low" with "a review is scheduled" |

### 2.2 Critique of §14's ladder specifically

- **It's backwards on the difficulty gradient.** **[L]** The gloss meta-analysis (Yanagisawa, Webb & Uchihara 2020, *SSLA*; 359 effect sizes / 42 studies / N=3,802) found **multiple-choice glosses most effective and in-text glosses / glossaries least effective**, and glossed reading beat unglossed (45.3 %/33.4 % vs 26.6 %/19.8 % immediate/delayed). The ladder gives the *least effective* format to the *newest* items where the opportunity is largest, and reserves the effective format for items already at 0.80+. **Invert it:** introduce with a multiple-choice or "which one?" micro-decision, and fall back to a plain gloss only when the user declines.
- **The involvement load is ~0 across the first three rungs.** **[L]** Laufer & Hulstijn's Involvement Load Hypothesis (need/search/evaluation) is predictive; the meta-analysis (Yanagisawa 2021, *Language Learning*, 398 effect sizes / 42 studies / N=4,628) found the ILH explained **15.0 % of variance immediate and 5.1 % delayed**, with **evaluation contributing most, need second, search not contributing.** "Show translation + meaning" has need=0, search=0, evaluation=0 — the lowest-involvement intervention the ILH describes. Rungs 1-3 are predicted to produce close to nothing on delayed measures.
- **"occasionally" and "normally" are unspecified** — the only two rungs with real learning value are the two whose firing rate is undefined.

### 2.3 Replacement: expected-value selection under a budget

```
value(item, intervention, context) =
      w_gain   * ΔS_expected(item, modality, intervention, R)   # learning gain
    * w_need   * P(user will need this item again soon)          # frequency x personal usage
    * w_ready  * readiness(R)                                    # desirable difficulty
    - w_cost   * intrusion_cost(intervention, context)
```

- `ΔS_expected` comes straight from the FSRS growth term — a recall attempt at `R ~ 0.85` has near-maximal expected gain, `R ~ 0.99` near-zero. **Desirable difficulty falls out of the model**, replacing "mastery < 0.95".
- `P(need)` = corpus Zipf frequency blended with the user's own personal frequency for that lemma. The honest answer to §14's "whether the word is important/common".
- `intrusion_cost` is where §14's "amount of learning UI shown recently" lives, plus context: **[L]** interruptions at *coarse* breakpoints (between chunks) cost less than at *fine* breakpoints (Adamczyk & Bailey 2004). §17's trigger engine is already correct on this and deserves credit — extend the same logic to intervention *selection*. Add: suppress when typing rate is high, when the field looks like a search box or URL, and when the user has dismissed >=2 bars in the last 5 minutes. **[L]** WaitChatter found users least likely to engage during time-sensitive, serious, or work-related conversations — you cannot detect those directly, but dismissal rate is a proxy.
- Keep §14's per-sentence budget of 1 vocabulary + 1 grammar. Well judged.

### 2.4 Concrete data model (SQLite / SwiftData, App-Group shared)

```sql
-- ---------- static, ships in the bundle, read-only, never synced ----------
CREATE TABLE item (
  id            INTEGER PRIMARY KEY,
  key           TEXT NOT NULL UNIQUE,   -- see §3.2 for key grammar
  kind          TEXT NOT NULL,          -- 'lemma_sense'|'form_cell'|'construction'|'collocation'
  lemma         TEXT,                   -- 'llegar'
  pos           TEXT,                   -- 'VERB'
  sense_idx     INTEGER DEFAULT 0,
  feats         TEXT,                   -- UD FEATS: 'Mood=Ind|Tense=Fut|Person=1|Number=Sing'
  gloss_en      TEXT,
  gloss_it      TEXT,
  zipf          REAL,                   -- log10(per-billion)+3
  cefr          TEXT,                   -- 'A1'..'C2', NULL if unknown
  cog_en        REAL,                   -- 0..1 orthographic similarity to EN gloss headword
  cog_it        REAL,                   -- 0..1 to IT gloss headword
  ff_flag       INTEGER DEFAULT 0,      -- 1 = false friend vs EN, 2 = vs IT, 3 = both
  d_prior       REAL                    -- precomputed cold-start Difficulty, §2.5
);
CREATE TABLE form (                     -- surface -> item resolution
  surface TEXT NOT NULL, item_id INTEGER NOT NULL, feats TEXT, prob REAL,
  PRIMARY KEY (surface, item_id)
);

-- ---------- per-user, mutable ----------
CREATE TABLE trace (
  item_id       INTEGER NOT NULL,
  modality      INTEGER NOT NULL,       -- 0 = recognition, 1 = production
  stability     REAL NOT NULL,          -- FSRS S, days
  difficulty    REAL NOT NULL,          -- FSRS D, 1..10
  last_event_at INTEGER NOT NULL,
  reps          INTEGER NOT NULL DEFAULT 0,   -- graded events only
  lapses        INTEGER NOT NULL DEFAULT 0,
  exposures     INTEGER NOT NULL DEFAULT 0,   -- diagnostic ONLY; never feeds a threshold
  eff_reps      REAL    NOT NULL DEFAULT 0,   -- sum of η — the honest "evidence count"
  suppressed_until INTEGER,
  PRIMARY KEY (item_id, modality)
);

-- append-only; the single most valuable table you will own
CREATE TABLE event (
  id        INTEGER PRIMARY KEY,
  item_id   INTEGER NOT NULL,
  ts        INTEGER NOT NULL,
  channel   TEXT NOT NULL,   -- 'expose'|'dwell'|'tap'|'insert'|'recall'|'produce'|'correct'
  rating    INTEGER,         -- 1..4 for graded events, NULL otherwise
  eta       REAL NOT NULL,
  dwell_ms  INTEGER,
  latency_ms INTEGER,
  r_pred    REAL,            -- model's predicted R at the time — enables offline calibration
  s_before  REAL, d_before REAL,
  ctx       TEXT             -- coarse only: app bundle CLASS, source lang, mode. NO TEXT.
);
CREATE INDEX event_item ON event(item_id, ts);
```

Notes:
- **`mastery` and `status` are deleted.** They become computed: `R(m) = pow(1 + factor*elapsed_days/S_m, decay)`, `mastery_display = 0.35*R_recognition + 0.65*R_production` — for the host app's Screen 2 only, never for a decision.
- **`next_review_at` is deleted.** The review queue is a *query*: `ORDER BY R(production) ASC LIMIT n WHERE eff_reps > threshold`.
- **`event` is append-only and never sent anywhere.** §21 compliance: `ctx` stores an app *class* (messaging/mail/browser), never app-specific content, and no raw typed text is ever written to it. **§21 should be tightened to "do not persist raw typed text at all except in the explicitly opt-in translation-history table, which is separate and independently clearable."**
- Keeping `event` makes the model *re-fittable*: you can replay the log with new η values, new priors, or a different memory model without losing history. Without it you are stuck with your first guess forever.

**Update rules:**
```
on graded event(item, modality, rating, ts):
    t = (ts - last_event_at)/86400
    R = pow(1 + factor*t/S, decay)
    S = (rating == 1) ? S_fail(S,D,R) : (t < 1/24 ? S_sameday(S,rating) : S_success(S,D,R,rating))
    D = mean_reversion(D + dampen(-w6*(rating-3), D))
    reps++, eff_reps += 1.0, (lapses++ if rating==1)

on exposure(item, η, ts):                 # recognition modality only
    t = (ts - last_event_at)/86400
    R = pow(1 + factor*t/S, decay)
    S = S * ( η*exp(w8)*(11-D)*pow(S,-w9)*(exp((1-R)*w10) - 1) + 1 )
    exposures++, eff_reps += η

on first-ever contact:
    D = d_prior(item)                                            # §2.5
    S = S0_prior(item) = clamp(0.4 * exp(1.1 * cog_max), 0.4, 4.0)
```

### 2.5 Cold start: the thing FSRS cannot do and you can

```
d_prior = clamp( 5.0
                 - 0.45*(zipf - 4.0)          # frequent words are easier
                 - 2.20*cog_max               # cognate facilitation
                 + 1.40*ff_flag_meaning       # false friend: MEANING is harder
                 + 0.30*(len_chars > 9)
                 + 0.60*(kind='construction')
                 + 0.80*irregular_verb
                 , 1.0, 10.0 )
where cog_max = max(cog_en, cog_it)
```

**[L]** Cognate facilitation is robust — bilinguals recognise and produce cognates faster; cognates are learned more easily and retained longer. And a subtle finding worth encoding: **[L]** false cognates show an *advantage* in word-**form** learning while carrying a penalty on meaning. So `ff_flag` should raise difficulty on the **recognition/meaning** trace and *lower* it on form — another reason the traces are split.

`cog_en`/`cog_it` are computable offline at build time: normalised Levenshtein between the Spanish lemma and its EN/IT gloss headword, after stripping predictable affix correspondences (`-ción`/`-tion`/`-zione`, `-dad`/`-ity`/`-tà`, `-mente`/`-ly`/`-mente`).

**Practical consequence:** on day one, `hotel`, `taxi`, `internet`, `problema`, `importante`, `posible` start with `d_prior ~ 1-2` and `S0 ~ 3-4 days`, so the policy never wastes the per-sentence budget teaching them. **That single change probably does more for perceived quality than the entire scheduler.**

### 2.6 Two cheap signals the PRD throws away

- **Latency.** **[L]** SlimStampen/MemoryLab estimates a per-item *rate of forgetting* from response times, reporting up to ~10 % efficiency gains, with individual rates stable over time and correlated across materials. You get latency free on every Mode D interaction and every Spanish word typed. Store `latency_ms`; even if v1 ignores it, v2 can fit it.
- **Unassisted production in the wild.** When the user types `llegaré` in a real message with no bar shown, that is the highest-quality datum the system will ever see and it costs nothing to detect. §12's "basic vocabulary tracking" doesn't mention it. Make it a first-class event.

---

## 3. Lemmatization and vocabulary units for Spanish

### 3.1 Why lemma alone is wrong, and surface form alone is wrong

Spanish inflection per verb: ~**50-60 simple forms** before enclitics **[U — standard-grammar arithmetic]**. With clitic clusters (`dármelo`, `dándoselo`, `cuéntamelo`) the productive form space is effectively unbounded.

- Key on **lemma** -> `llegaré` is invisible.
- Key on **surface form** -> `llegar/llego/llegué/llegaré/llegaría/llegue/llegara/llegando/llegado` are 10 unrelated items. Nothing transfers to `hablaré`, `comeré`, `saldré`. The user is taught the same future tense 400 times.

### 3.2 Recommended: factorised three-level key, credit assigned to all levels

```
llegaré  ->  { LEM:llegar|VERB|0                       # the meaning "to arrive"
             , CELL:VERB|Mood=Ind,Tense=Fut,Person=1,Number=Sing   # "future 1sg"
             , PARA:conj-ar-regular|FUT                # "-ar verbs form the future like this"
             }

dármelo  ->  { LEM:dar|VERB|0, LEM:me|PRON|0, LEM:lo|PRON|0
             , CELL:VERB|VerbForm=Inf
             , CONS:clitic-enclisis-inf-IO-DO
             }

tener ganas de -> { MWE:tener_ganas_de }               # single item, NOT tener+gana+de
la casa blanca -> { LEM:casa|NOUN|0, LEM:blanco|ADJ|0, CONS:adj-agreement-fem-sg }
```

| prefix | unit | example | why it's its own item |
|---|---|---|---|
| `LEM:` | lemma + POS + sense index | `LEM:quedar\|VERB\|2` | the meaning-learning unit; senses are separate (F9) |
| `CELL:` | paradigm cell (POS + UD FEATS), lemma-independent | `CELL:VERB\|Tense=Fut,Person=1,Number=Sing` | the morphology unit; transfers across all verbs |
| `PARA:` | conjugation class x cell | `PARA:conj-ir-e_i\|PRS` | stem-changing / irregular classes are separate learning |
| `CONS:` | construction / grammatical pattern | `CONS:ser-vs-estar-location` | §14's "grammar note" needs a first-class item to attach state to |
| `MWE:` | fixed multiword expression | `MWE:tener_ganas_de` | see below |

A factorised generalisation of Duolingo's lexeme tag **[C]** (validated on 13M user-word pairs) — except Duolingo's is a single conjunctive key, so `camera.N.SG` and `camera.N.PL` share nothing. Factorising means seeing `hablaré` gives partial credit to `CELL:VERB|Tense=Fut,Person=1,Number=Sing`, so `llegaré` is *not* fully new when first met — which is both true and what makes the model feel intelligent.

**Credit assignment:** η is split, not duplicated — e.g. `LEM` 0.6η, `CELL` 0.3η, `PARA`/`CONS` 0.1η.

**Specific cases:**
- **Gender/number agreement:** not vocabulary. Store gender as a *property* of `LEM:`; agreement as `CONS:`. Do not create `blanco/blanca/blancos/blancas` as four items.
- **Clitics:** decompose. The orthographic accent rule (`dar` -> `dármelo`) is itself a `CONS:`. Italian speakers transfer proclisis/enclisis rules that are close but not identical (IT `darmelo` vs ES `dármelo`) — mostly positive transfer, so a *low* d_prior for an IT L1 user.
- **Reflexives:** `se` changes the lemma's meaning, so `LEM:ir|VERB|0` != `LEM:irse|VERB|0`. Keep reflexive verbs as distinct lemmas (Wiktionary already does).
- **MWEs:** **[L]** formulaic sequences are processed faster than matched non-formulaic strings by both L1 and L2 speakers, and phrasal frequency predicts sensitivity — supporting the chunk as a real unit. But **[L]** Wray's own conclusion is that evidence for *teaching* formulaic sequences is mixed, and literate adults tend to unpack them anyway. **Store MWEs as items, teach them as wholes, but only ones with non-compositional meaning** (`tener ganas de`, `dar igual`, `hacer falta`, `echar de menos`, `llegar a fin de mes`).

### 3.3 Resources, and what fits in an iOS bundle (measured directly)

| Resource | Content | Size (measured) | License | Ship? |
|---|---|---|---|---|
| **`doozan/spanish_data` -> `frequency.csv`** **[C]** | 25,002 Spanish lemmas w/ POS + **all inflected surface forms with counts** | 2.67 MB raw; **derived surface->lemma table: 159,097 forms, 3.4 MB plain / 522 KB gzip** | CC-BY-SA 3.0 | **Yes — this is the core** |
| **`doozan/spanish_data` -> `es-en.data`** **[C]** | Wiktionary ES->EN: **114,353 headwords, 16,904 multiword**, per-sense glosses, POS | 17.8 MB raw / **3.88 MB gzip** | CC-BY-SA | Yes, pruned. Drop etymology+usage, keep top 30k + all MWEs -> ~1.5-2 MB **[U estimate]** |
| Apple `NLTagger` (`.lemma`, `.lexicalClass`) **[L]** | on-device lemmatization + POS, Spanish supported | **0 bytes** — OS-provided | Apple SDK | **Yes — primary tokenizer/lemmatizer** |
| spaCy `es_core_news_sm` **[L]** | LEMMA_ACC 98.32, POS_ACC 98.20 | 13.7 MB | **GPL-3.0** | **No.** Python + GPL-3.0 in a closed App Store binary is a licensing problem. Build-time only |
| Apertium `apertium-spa` / FreeLing **[L]** | full FST morph analyser | needs runtime | GPL / AGPL | Build-time only |
| UD `es_ancora` / `es_gsd` **[L]** | 17,662 sents / 547,558 tokens | ~50 MB | CC BY-SA 4.0 | No — training data |

**Recommended runtime stack (~2.5-3 MB, no third-party runtime):**
1. `NLTagger` for tokenisation, POS, first-pass lemma — free, on-device, no memory cost.
2. A bundled **FST or double-array trie of the 159k surface->(lemma, POS, FEATS) table** as the authority, overriding `NLTagger` when they disagree and supplying the FEATS it doesn't give you. Build offline; ship only the compiled table.
3. A **clitic stripper**: regex-peel `(me|te|se|nos|os|lo|la|le|los|las|les){1,2}$` from verb-final tokens, restore the accent, re-lookup. ~50 lines.
4. An **MWE matcher**: longest-match over ~2-4k non-compositional MWEs, run *before* single-word lookup.
5. Conjugation *generation* via ~90 paradigm templates + a lemma->paradigm map, not a stored form list. Tens of KB.

**Important caveat found while measuring** **[C]**: `frequency.csv`'s form->lemma mapping is **pre-disambiguated — 0 of 159,097 surface forms map to more than one lemma.** Real Spanish is ambiguous (`como`, `nada`, `vino`, `sobre`). So this is a *fast path with a known accuracy ceiling.* Use `NLTagger`'s context-sensitive tag to break ties, and treat lemma resolution as probabilistic (`form.prob`). **Do not let an ambiguous resolution write a graded event** — at most a low-η exposure.

Also: `frequency.csv` contains only **15 multiword lemmas** **[C]** — MWEs must come from `es-en.data`'s 16,904 multiword headwords.

**Licensing flag** **[L]**: essentially every viable dataset is **CC-BY-SA**, a copyleft on the *data*. A derived compiled lookup table is plausibly an adaptation, which would require sharing the derived table alike. This does not infect your app code, but may require publishing the generated data files and an attribution screen. Check before launch.

---

## 4. Frequency and CEFR data

### 4.1 Frequency

| List | Coverage | Size | License | Verdict |
|---|---|---|---|---|
| **hermitdave `FrequencyWords` `es_50k.txt`** (OpenSubtitles 2018) **[L]** | 50k word forms + counts | ~700 KB | code MIT; data CC-BY-SA 3.0 | Ship. Subtitles ~= conversational register ~= messaging. **Best register match available** |
| **`doozan` `frequency.csv`** **[C]** | 25k **lemmas**, POS-tagged | 2.67 MB / 892 KB gz | CC-BY-SA 3.0 | Ship this instead of raw es_50k — lemma-level is what you need |
| **wordfreq** **[L]** | 40+ languages, Zipf scale | — | code Apache-2.0, data CC-BY-SA 4.0 | Use offline to compute `zipf`. Maintainer froze post-2021 data over LLM contamination **[U]** |
| **EsPal / SUBTLEX-ESP** **[L]** | EsPal 300M written + 460M subtitle tokens, plus psycholinguistic properties | web DB | academic, terms unclear | Valuable for `d_prior` features. Query offline, bake in. **Check terms before redistributing** |
| RAE CREA / CORPES XXI | reference corpora | web query only | RAE terms | Not usable for bundling **[L]** |
| Davies, *A Frequency Dictionary of Spanish* | 5,000 curated lemmas | book | **© Routledge** | Excellent quality, **cannot ship.** Offline sanity check only |

**Register warning:** a subtitle list is a good but imperfect proxy for *your user's* messaging. The best "worth teaching" signal after month one is **the user's own EN/IT lemma frequency projected through translation** — words they keep writing in English are words they will keep needing in Spanish. Weight personal frequency at least as heavily as corpus frequency once you have ~5,000 of their tokens.

### 4.2 CEFR

| Resource | Lang | Content | License | Verdict |
|---|---|---|---|---|
| **ELELex** (CEFRLex, UCLouvain) **[L]** | **ES** | words + MWEs with normalised frequency distributions **across CEFR levels** | research; terms need checking | **The best Spanish CEFR option that exists.** Contact the authors. Gives a *distribution over levels*, not a single label — more honest and directly usable as a prior |
| **Plan Curricular del Instituto Cervantes** **[L]** | ES | the *de facto* CEFR reference for Spanish | **© Instituto Cervantes** | Readable, **not licensable for bundling.** Use to hand-check automatic levels |
| **KELLY** (Kilgarriff et al., *LREV* 2013) **[L]** | 9 langs incl. **IT** — **Spanish NOT included** | frequency (ipm) + CEFR level | **CC BY-NC-SA 2.0** | **Use for the Italian side.** The NC clause blocks commercial use |
| **NGSL** **[L]** | EN | ~2,800 words, >92 % coverage | **CC BY-SA 4.0** | Use for English. Cleanest license here |
| **English Vocabulary Profile** (Cambridge) **[L]** | EN | word *and sense*-level CEFR | free to educators; redistribution unclear | Check before bundling |
| **CEFR-J / olp-en-cefrj** **[L]** | EN | vocabulary profile CSV | **free for research and commercial use with citation** | Ship for English |
| **UniversalCEFR** (HuggingFace) **[L]** | 13 langs incl. ES | CEFR-labelled **texts** | per-text | Use to *train* a Spanish CEFR predictor if ELELex isn't obtainable |

**Honest answer to "what data tells you if a word is worth teaching":** no single dataset does. Combine:

```
worth(item) = 0.45 * norm(zipf)                       # will they meet it again
            + 0.25 * norm(personal_freq)              # will THEY need it
            + 0.15 * cefr_proximity(item, user_level) # is it reachable now
            + 0.15 * (1 - cog_max)                    # is it actually new to them
            - 0.30 * is_proper_noun_or_number
```

**The `(1 - cog_max)` term does more work than the CEFR term.** For an EN+IT speaker, CEFR level is a poor proxy for *personal* difficulty — a B2-labelled Latinate word may be free, and an A1 word like `pero`/`però`, `salir`, `pronto` may be a trap. **Cognate distance is a better feature than CEFR level for this specific user.** A genuine insight for this product.

---

## 5. Interference: Italian->Spanish and English->Spanish

### 5.1 What the research says

**[L]** The Italian-Spanish literature converges on one non-obvious claim: **similarity helps at the start and hurts later.** Documented: the "just add an -s" folk belief drives frequent interference and **fossilised** errors; perceived closeness has both positive and negative effects depending on stage; initial confidence tends to disappear over time; reaching a first level is easy while reaching high proficiency is *harder* than from a distant L1 because of constant interference. Studies use Error Analysis / Interlanguage frameworks and classify lexical errors as interlingual vs intralingual, and as errors of *form* vs of *meaning*.

**[L]** Psycholinguistic mechanism: cognate facilitation is robust in recognition and production; false friends produce **lower accuracy, longer RTs, and a larger N400** in L1->L2 translation; interference is **context-dependent** while facilitation is more ubiquitous. And: false cognates show an *advantage* in **word-form** learning — the form is easy, the meaning is what fails. Exactly why the memory model must separate form from meaning.

### 5.2 IT->ES: the target list

**Tier 1 — grammatical transfer traps (fire constantly; highest value).** Worth far more than lexical false friends because they recur in nearly every sentence.

| # | Trap | Italian pattern | Wrong Spanish | Right Spanish | Conf |
|---|---|---|---|---|---|
| 1 | **`ser` vs `estar`** | IT has one copula, `essere` | *`soy cansado`*, *`está italiano`* | `estoy cansado`, `es italiano` | **[L]** — universally cited as the #1 IT->ES trap |
| 2 | **`por` vs `para`** | one preposition `per` | *`gracias para todo`* | `gracias por todo` | **[U]** |
| 3 | **`muy` vs `mucho`** | one word `molto` | *`mucho bueno`*, *`muy gusta`* | `muy bueno`, `me gusta mucho` | **[U]** |
| 4 | **Indicative after `creo que`** | IT `penso che sia` takes subjunctive | *`creo que sea tarde`* | `creo que **es** tarde` | **[U]** — high-value because counterintuitive |
| 5 | **Article before possessive** | IT `il mio libro` | *`el mi libro`* | `mi libro` | **[U]** |
| 6 | **Indefinido vs perfecto with past adverbials** | IT `passato prossimo` covers both | *`he comido ayer`* | `comí ayer` | **[U]** |
| 7 | **`tener` vs `haber`** | IT `avere` covers both | *`tengo comido`*, *`he hambre`* | `he comido`, `tengo hambre` | **[U]** |
| 8 | **`pensar en` vs `pensare a`** | preposition mismatch | *`pienso a ti`* | `pienso en ti` | **[U]** |
| 9 | **Double consonants / orthography** | `professore`, `differenza`, `attenzione` | *`professor`*, *`differencia`* | `profesor`, `diferencia`, `atención` | **[U]** — very high frequency, trivially detectable |
| 10 | **`-zione` -> `-ción`, `-tà` -> `-dad`** | systematic | *`nazione`*, *`città`* | `nación`, `ciudad` | **[U]** — mostly *positive*: teach the rule once, unlock thousands |

**Tier 2 — lexical false friends.** Confirmed by search: `burro`, `salir`/`salire`, `embarazada`/`imbarazzata`, `largo`/`lungo`, `aceite`/`aceto` **[L]**. The rest **[U — verify each against DRAE + Treccani before shipping]**.

| Spanish | Means in ES | Italian look-alike | Means in IT | What the Italian wants |
|---|---|---|---|---|
| `burro` | donkey | `burro` | butter | `mantequilla` |
| `largo` | long | `largo` | wide | `ancho` (IT `lungo` = ES `largo`) |
| `salir` | to go out | `salire` | to go up | `subir` |
| `subir` | to go up | `subire` | to undergo | `sufrir`/`padecer` |
| `embarazada` | pregnant | `imbarazzata` | embarrassed | `avergonzada` |
| `aceite` | oil | `aceto` | vinegar | `vinagre` |
| `pronto` | soon | `pronto` | ready | `listo` |
| `todavía` | still, yet | `tuttavia` | however | `sin embargo` |
| `guardar` | to keep, save | `guardare` | to look at | `mirar` |
| `topo` | mole (animal) | `topo` | mouse | `ratón` |
| `gamba` | prawn | `gamba` | leg | `pierna` |
| `caldo` | broth | `caldo` | hot | `caliente` |
| `luego` | later, then | `luogo` | place | `lugar` |
| `oficina` | office | `officina` | workshop | `taller` |
| `vaso` | drinking glass | `vaso` | vase | `jarrón` |
| `carta` | letter | `carta` | paper | `papel` |
| `seta` | mushroom | `seta` | silk | `seda` |
| `nudo` | knot | `nudo` | naked | `desnudo` |
| `primo` | cousin | `primo` | first | `primero` |
| `éxito` | success | `esito` | outcome | `resultado` |
| `rato` | a while | `ratto` | rat | `rata` |
| `sembrar` | to sow | `sembrare` | to seem | `parecer` |
| `prender` | to switch on / arrest | `prendere` | to take | `tomar`/`coger` |
| `pero` | but | `però` | however/but | near-synonym — *partial* false friend, subtler and stickier |

### 5.3 EN->ES: the target list

**Tier 1 grammar:** grammatical gender (no English analogue — the highest-volume error source); `ser`/`estar`; subjunctive (absent from productive English); `por`/`para`; `gustar`-inversion; personal `a`; obligatory double negation (`no vi a nadie`); adjective position; `hace X que` for duration.

**Tier 2 lexical:** `embarazada`!=embarrassed (->`avergonzado`); `éxito`!=exit (->`salida`); `actual/actualmente`!=actual/actually (->`real`/`en realidad`); `realizar`!=realize (->`darse cuenta`); `asistir`!=assist (->`ayudar`); `sensible`!=sensible (->`sensato`); `constipado`!=constipated (->`estreñido`); `carpeta`!=carpet (->`alfombra`); `librería`!=library (->`biblioteca`); `ropa`!=rope (->`cuerda`); `sopa`!=soap (->`jabón`); `soportar`!=support (->`apoyar`); `pretender`!=pretend (->`fingir`); `molestar`!=molest (->`acosar`); `introducir`!=introduce a person (->`presentar`); `discutir`!=discuss neutrally (->`hablar de`); `colegio`!=college (->`universidad`); `argumento`!=argument (->`discusión`); `lectura`!=lecture (->`conferencia`); `once`!=once (=eleven); `red`!=red (=network); `pan`!=pan (=bread); `dime`!=dime ("tell me").

### 5.4 Should interference be the headline feature? **No — but it should be the sharpest capability**

**For:** genuinely differentiated (nothing teaches ES to an EN+IT bilingual specifically); cheap (~300 lexical pairs + ~20 grammar patterns + computable cognate distance — a weekend of data work); it solves the cold-start problem as a side effect, which is worth more than the false-friend feature itself; and **[L]** the fossilisation finding gives it real stakes — for close-language pairs, *early, explicit* contrastive attention is the recommended remedy.

**Against — and this is decisive:**
1. **Base rate.** The user has to actually type "butter" or "wide" for `burro`/`largo` to fire. In everyday messaging, most of the 300 pairs fire a handful of times per *year*. A headline feature you see monthly is not a headline feature.
2. **No error signal in the P0 product.** Interference errors only exist when the *user* produces Spanish. In Modes A/B/C the *LLM* produces the Spanish and it's correct — the user never makes the mistake. **The interference feature is entirely contingent on Mode E**, which the PRD lists as P1. Shipping "interference-aware" as a headline while Mode E is P1 would be marketing a feature the product doesn't have.
3. **Mode C actively works against it.** A code-switched hybrid like *"Probablemente I'll llegar around ocho"* is the user *producing an interlanguage string*. For a learner whose documented failure mode is over-transfer between near-identical languages, deliberately rehearsing a blended IT-ES-EN register is a plausible way to *manufacture* fossilisation. **[U]** — no study tests this, but the hypothesis is well-motivated and the burden of proof is on Mode C.

**Recommendation:** ship interference as (a) **cold-start priors** — always on, invisible, high value; (b) a **high-precision, low-recall interrupt** in Mode E and in the Mode D distractor set (use the false friend as the wrong answer — that's the "evaluation" component the ILH says matters most); (c) a **once-per-trap explicit contrastive card**, then never again unless it recurs. Do **not** put it on the box until Mode E is P0.

---

## 6. Does the core premise hold?

### 6.1 "Micro-moments inside messaging can teach vocabulary" — **holds, with a large asterisk**

**[L]** **WaitChatter** (Cai, Guo, Glass, Miller; CHI 2015) is near-exact prior art: a chat client showing contextually relevant foreign vocabulary and **micro-quizzes** just-in-time while awaiting a reply. Two-week field study, N=20, **~57 new words learned on average**, ~170 chats/day. Users were **most receptive immediately after sending a message.** Exercises appeared for 10 seconds and faded if ignored.

Asterisks:
- The intervention was a **quiz**, not a translation display — the retrieval-practice condition, not Mode A.
- The trigger was **after sending** — the dead time — not **while composing.** §17 fires on `.`/`?`/`!`/pause, i.e. mid-composition. **[L]** Adamczyk & Bailey: interruptions at *coarse* breakpoints cost less than at *fine* breakpoints, where you must additionally reconstruct your position. A sentence-final period is a coarse breakpoint — that part is right. A debounce pause mid-sentence is a fine one — that part is wrong. **Recommendation: fire the learning bar on `send`, not on pause. One-line change, best evidence-to-effort ratio in this document.**
- Could not read a delayed retention test; "57 words" may be immediate-posttest recognition **[U]**.

**[L]** **WaitSuite** (Cai et al., *TOCHI* 2017), five wait types, N=25, two weeks: **highest engagement on PullLearner and ElevatorLearner, lowest on WaitChatter.** Framework attributes this to *wait time, ease of access, and competing demands.* **Chat was the worst context they tested.** And **[L]** users were least likely to engage during time-sensitive, serious, or work-related conversations — a large share of real messaging.

**So: the premise's own best evidence says the messaging context is the hardest one, and the effective intervention there was a quiz, not a gloss.**

### 6.2 "Showing a translation mid-message will teach" — **weak. This is where the premise fails**

Four independent lines converge:

1. **[L] Gloss format.** Yanagisawa, Webb & Uchihara (2020, *SSLA*; 359 effect sizes, 42 studies, N=3,802): glossed > unglossed (45.3 %/33.4 % vs 26.6 %/19.8 %), **but multiple-choice glosses most effective and in-text glosses / glossaries least effective**; L1 glosses beat L2 glosses. Mode A/B is an in-text gloss — the worst-performing format. Mode D is closest to the best.
2. **[L] Involvement load.** ILH explained 15.0 % (immediate) / 5.1 % (delayed) of variance; **evaluation contributed most, need second, search not at all**; involvement load mattered more than time on task. An unrequested translation banner has need=0, search=0, evaluation=0.
3. **[L] Exposure is a weak lever.** r = .34; ~12-17 % of variance.
4. **[L] Banner blindness.** Benway & Lane (1998) coined the term with eye-tracking showing users look *past* banner-shaped elements even when they contain exactly the information sought; NN/g eye-tracking replicates 1997-2024, finding **stable avoidance around known ad positions and ad-like visual structures**, and that users barely saw banners *when clicking wasn't required to accomplish the task.* **A persistent horizontal strip above the keyboard, present on every message, whose content is not required to send the message, is structurally an ad banner. It will be learned-ignored within weeks.**

**Design consequences:**
- The bar must not be persistent. WaitChatter kept the panel present but the *exercise* transient; a keyboard has less screen budget and a stricter attention economy.
- Anything shown without a required interaction should be assigned η ~ 0.03 — near-zero — and **the model should know that.** This is the honesty check that keeps F3 from recurring.
- Prefer forced micro-choices over displays: *"llegaré / llegué"* as a two-way tap is cheaper than reading a gloss and has the highest-value ILH component (evaluation).

### 6.3 "One-tap insert the Spanish translation" — **actively harmful, and it's P0**

The sharpest thing found in the PRD. The user needs the Spanish (need=1), the system supplies it without search (search=0), the user accepts without comparing alternatives (evaluation=0), and then **produces the Spanish word in a real message without having generated it.** The behavioural log records "user sent a Spanish message" — the product's success metric — while no retrieval occurred. **[L]** By ILH this yields minimal retention; **[U]** by generation-effect logic it is worse than not showing it, because it substitutes for the retrieval attempt.

It also corrupts the measurement in §7: "% of characters typed in Spanish" becomes uninterpretable if a fraction were pasted.

**Recommendations:** (a) keep the insert button — it's a real usability feature — but **log it as `channel='insert', eta=0`** and exclude inserted characters from all Spanish-production metrics; (b) gate it behind a 1-second "try first" affordance for items where `R(production) > 0.5`; (c) after insertion, queue that item for a Mode D recall within 24-72 h. **Turn the crutch into a scheduling signal.**

### 6.4 Mode C (code-switch/hybrid) — **UNVERIFIED, and possibly harmful for this user**

**[L]** The macaronic-text line (Renduchintala, Knowles, Koehn, Eisner — ACL 2016 x2, EMNLP 2019) built interactive mixed-L1/L2 *reading* interfaces and **modelled comprehension** of foreign words from cognate clues, context PMI, and prior exposure. What they demonstrated is a *user model of comprehension* and a method for *choosing* which words to swap. **[U]** No controlled evidence was found that macaronic reading produces durable vocabulary acquisition superior to a control — and Mode C is *production*, not reading, which the macaronic work does not address at all.

Toucan (now Babbel-owned) is the commercial instance, ~300k Chrome installs **[L]**, with **no peer-reviewed efficacy study found** **[U]**.

Plus the fossilisation concern in §5.4. **Verdict: Mode C is the most novel-feeling and least-supported mode in the PRD.** Keep it, but demote to an experiment with an explicit success criterion, and constrain it: swap only *complete constituents* (a whole NP or VP), never mid-phrase, so the user rehearses a well-formed Spanish chunk embedded in English rather than an ungrammatical blend. `Probablemente | I'll arrive | sobre las ocho` is defensible; `Probablemente I'll llegar around ocho` is a string that exists in no language.

### 6.5 Where the premise is strong

- **Trigger discipline** (§17: no request while typing rapidly, cancel on change, never show stale) is correct and matches the interruption literature.
- **The per-sentence budget** (§14: 1 vocab + 1 grammar) is right, and stricter than most products.
- **The insight that the user's own message content selects the vocabulary** is genuinely good and under-exploited. Words the user keeps trying to say are by construction high-`P(need)` items. **This is a better item-selection signal than any frequency list, and the PRD never states it as a principle.**

---

## 7. Measurement: proving it works for one user, with no control group

You don't need a control *group*. You need **randomisation at the item level**, which a single user can supply.

### 7.1 Within-subject randomised item assignment

At the moment an item first becomes eligible, assign randomly, stratified by `zipf` band and `cog_max` band:

| Arm | Share | Treatment |
|---|---|---|
| **A — full** | 45 % | Normal policy: gloss, highlight, Mode D recall, review queue |
| **B — exposure only** | 35 % | Silently tracked and its exposures logged, but **no teaching UI ever fires** |
| **C — holdout** | 20 % | Never taught, never highlighted, never reviewed — and never queried until the test |

Test all three arms at fixed delays (7 / 30 / 90 days after the *n*th exposure) with the same instrument. **This is a randomised controlled experiment inside one person.** Arm B answers the question the whole product hinges on — *does exposure without instruction teach?* Arm C gives the natural-acquisition baseline. **A−B is the value of your teaching layer; B−C is the value of mere exposure.**

**[L]** A legitimate single-case design: SCED/N-of-1 logic requires demonstrating the effect at >=3 points in time or across replications; item-level randomisation with continuous accrual gives hundreds of replications rather than three.

Complement with a **multiple-baseline across item sets**: three matched cohorts of ~40 items, switched into treatment at staggered weeks. If the learning curve inflects at each switch-in point and not before, that's causal evidence with no control group.

### 7.2 Instruments

| What | Instrument | Cadence | Note |
|---|---|---|---|
| **Production** (the actual goal) | Typed L1->ES cued recall, no options, exact-match + lenient scoring | per-item at 7/30/90d | **Primary outcome** |
| **Recognition** | ES->L1 4-alternative MC; **use a false friend as one distractor** | same | Run *after* the production item so it doesn't prime |
| Depth of knowledge | Vocabulary Knowledge Scale | monthly, sampled | Catches the recognition-production gap qualitatively |
| Global proficiency anchor | **LexTALE-Esp** **[L]** — 60 words + 30 nonwords, r = .82 with self-rated proficiency | every 8-12 weeks | **Caveat: a vocabulary-*size* test. Insensitive to a few hundred words of gain; will look flat for months. Do not use as the primary metric** |
| Behavioural | see §7.3 | continuous | The honest product metric |
| **Model calibration** | log loss & RMSE-bins of `r_pred` vs actual Mode D outcomes, vs a frequency-only baseline | monthly | §7.4 |

### 7.3 Behavioural outcomes — what "the product works" actually means

1. **Self-generated Spanish rate**: Spanish characters typed *without* insert / total characters, weekly.
2. **Assistance rate**: assist requests per 100 self-generated Spanish words. Should *fall* while metric 1 rises. **If both rise, the product is a translator, not a teacher.**
3. **Unassisted-message rate**: % of sent messages >=80 % Spanish with zero assistance events.
4. **Suppression accuracy**: of items the model classified as "known" (suppressed UI), what fraction did the user later get wrong in Mode D? Directly tests F3. **Target: <15 %.** If it exceeds ~30 %, η must come down.
5. **Bar-blindness index**: dismissal rate and mean dwell time on the bar, by week since install. **[L]** Expect decay. If dwell time halves by week 6, the display-based modes are dead regardless of what the vocabulary tests say.
6. **Typing cost**: median inter-keystroke interval and median compose time, bar-shown vs bar-not-shown. This is §2's success condition made measurable. If compose time rises >10 %, the intrusion cost is real.

### 7.4 Falsifying your own model

Run monthly and be willing to lose:

- **Calibration:** log loss of `r_pred` against Mode D outcomes vs (i) constant `p = base rate`, (ii) logistic on `zipf + days_since_last_exposure` only. **If the full DSR model does not beat baseline (ii), delete it.** Complexity must earn its keep.
- **η identification:** fit η by maximum likelihood from the `event` log. **If the fitted η for `channel='expose'` is not distinguishable from 0, then passive exposure is not teaching this user, and every display-only mode should be cut.** This is the cleanest possible test of the core premise; it runs automatically and costs one SQL query plus a solver.
- **Arm B vs C:** if `Arm B ~= Arm C` at 30 days, incidental exposure through the keyboard produces nothing measurable, and the product must be re-founded on Modes D/E.

### 7.5 Threats to be honest about

- **Demand characteristics.** You are user, developer, and experimenter, and you know each item's arm the moment you see the UI. Mitigations: never surface arm assignment; auto-generate tests without previewing them; write the analysis script before collecting data; keep a pre-registration file in the repo with a commit timestamp.
- **Non-random exposure.** You choose what to type, so arm-B items may differ systematically despite randomisation. Stratify and check covariate balance across arms.
- **Novelty and seasonality.** Weeks 1-3 will look great. Discard or model explicitly.
- **Ceiling on the anchor.** LexTALE-Esp is coarse; a 3-point change is noise.
- **Regression to the mean** on items selected *because* they were failed.
- **One user, n=1.** Nothing generalises. It establishes only whether the product works *for you* — which is exactly the right scope for "personal use first."

---

## 8. Concrete change list for the PRD

| § | Change | Why |
|---|---|---|
| 13 | Delete `mastery`, `status`, `exposures`-as-input, `next_review_at`. Replace with `trace(item_id, modality, S, D, last_event_at, reps, lapses, eff_reps)` + append-only `event` log. Compute R on read | F1-F10 |
| 13 | Split every trace by `modality in {recognition, production}`; exposures write only to recognition | F2, and the product's own goal is production |
| 13 | Add item-feature cold-start priors (`zipf`, `cog_en`, `cog_it`, `ff_flag`, `cefr`) driving `d_prior`/`S0` | F6; the thing FSRS structurally cannot do |
| 13 | Re-key items: `LEM:` / `CELL:` / `PARA:` / `CONS:` / `MWE:` with split credit assignment | F4, F9; `llegaré` is `llegar` **and** future-1sg, not either |
| 14 | Replace the threshold ladder with expected-value scoring, subject to the existing 1+1 budget | Ladder is monotone in one number; requirements are multi-objective |
| 14 | Invert the difficulty gradient: forced micro-choice for new items, plain gloss only as fallback | In-text glosses are the *least* effective type; MC the most |
| 12 | Promote **Mode D (recall)** and **Mode E (correction)** from P1 to P0. Demote Mode C to a flagged experiment | Priority inversion — the P1 features have the evidence |
| 12 | Keep the insert button, but log it with `eta=0` and exclude inserted text from all Spanish-production metrics; optionally gate behind "try first" for `R(prod) > 0.5` | It's an anti-learning affordance masquerading as a success metric |
| 17 | Fire the learning bar **on send**, not on mid-sentence debounce pause | Coarse vs fine breakpoint; WaitChatter's own finding |
| 10 | The bar must not be visually persistent-and-ignorable. Add a decay-aware suppression rule and track dwell time as a first-class metric | Banner blindness is a design certainty, not a risk |
| 19 | Add `event` (append-only, no raw text) to the shared store. Add `item`/`form` static tables to the bundle | Makes the model re-fittable; without it your first η guess is permanent |
| 21 | Tighten: "do not persist raw typed text **at all** outside the explicitly opt-in, separately-clearable history table." `event.ctx` stores app *class*, never content | §21 currently only forbids *remote* persistence |
| 27 | Replace "Repeated exposure increments local learning state" as an acceptance test — **it enshrines failure mode F3.** Replace with "Suppression accuracy >=85 %" and "model log loss beats a frequency+recency baseline" | An acceptance test that asserts the bug |
| new | Add §34 "Evaluation protocol": arm A/B/C randomisation, delayed production tests, behavioural metrics, monthly calibration, pre-registration | Nothing in the PRD can currently distinguish "working" from "feels nice" |

---

## Sources

**Spaced repetition / memory models:** [srs-benchmark](https://github.com/open-spaced-repetition/srs-benchmark) (read directly) · [fsrs-rs](https://github.com/open-spaced-repetition/fsrs-rs) `src/model.rs` (read directly) · [ABC of FSRS](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/ABC-of-FSRS) · [Expertium benchmark](https://expertium.github.io/Benchmark.html) · [Settles & Meeder, ACL 2016 (HLR)](https://research.duolingo.com/papers/settles.acl16.pdf) · [duolingo/halflife-regression](https://github.com/duolingo/halflife-regression) · [Pavlik & Anderson (ACT-R spacing)](http://act-r.psy.cmu.edu/wordpress/wp-content/uploads/2012/12/409s15516709cog0000_14.pdf) · [fasiha/ebisu](https://github.com/fasiha/ebisu) · [SlimStampen](https://www.slimstampen.nl/en/zo-werkt-het/) · [Cold-start mitigation, UMUAI 2024](https://link.springer.com/article/10.1007/s11257-024-09401-5) · [swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs)

**Vocabulary acquisition:** Uchihara, Webb & Yanagisawa (2019) *Language Learning* · Uchihara, Webb & Yanagisawa (2023) *Language Teaching* · van Zeeland & Webb (2018) *Language Learning* · Webb, Yanagisawa & Uchihara (2020) *MLJ* · Yanagisawa, Webb & Uchihara (2020) gloss meta-analysis *SSLA* · Yanagisawa (2021) ILH meta-analysis *Language Learning* · Hulstijn & Laufer (2001)

**Micro-moments, interruption, attention:** [Cai et al., WaitChatter, CHI 2015](https://sls.csail.mit.edu/publications/2015/Cai_CHI-2015.pdf) · [Cai et al., WaitSuite, TOCHI 2017](https://dl.acm.org/doi/10.1145/3044534) · [Edge et al., MicroMandarin, CHI 2011](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/edge-CHI2011-micromandarin.pdf) · Adamczyk & Bailey (2004) · [Benway (1998) banner blindness](https://journals.sagepub.com/doi/10.1177/154193129804200504) · [Renduchintala et al., macaronic texts, ACL 2016](https://www.cs.jhu.edu/~jason/papers/renduchintala+al.acl16-macmodel.pdf) · [EMNLP 2019](https://aclanthology.org/D19-1679/)

**Spanish NLP & lexical resources:** [doozan/spanish_data](https://github.com/doozan/spanish_data) (measured locally) · [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords) · [rspeer/wordfreq](https://github.com/rspeer/wordfreq) · [spaCy Spanish models](https://spacy.io/models/es) · [apertium-spa](https://github.com/apertium/apertium-spa) · [UD_Spanish-AnCora](https://universaldependencies.org/treebanks/es_ancora/index.html) · [EsPal, *BRM* 2013](https://link.springer.com/article/10.3758/s13428-013-0326-1)

**CEFR & graded lists:** [CEFRLex](https://cental.uclouvain.be/cefrlex/) · [Plan Curricular del Instituto Cervantes](https://cvc.cervantes.es/ensenanza/biblioteca_ele/plan_curricular/niveles/09_nociones_especificas_inventario_a1-a2.htm) · [Kilgarriff et al. (2013) KELLY, *LREv*](https://link.springer.com/article/10.1007/s10579-013-9251-2) · [NGSL](https://www.newgeneralservicelist.org/home) · [olp-en-cefrj](https://github.com/openlanguageprofiles/olp-en-cefrj)

**Cross-linguistic influence:** [Italian-Spanish: Difficulties in Learning, *QULSO*](https://oaj.fupress.net/index.php/bsfm-qulso/article/view/15166) · [El error léxico en la interlengua de lenguas afines (RiuNet)](https://riunet.upv.es/entities/publication/27407348-d94f-48ca-9d79-0a3ae1f570cf) · [Cross-linguistic influence in the bilingual lexicon, *BLC*](https://www.cambridge.org/core/journals/bilingualism-language-and-cognition/article/crosslinguistic-influence-in-the-bilingual-lexicon-evidence-for-ubiquitous-facilitation-and-contextdependent-interference-effects-on-lexical-processing/8148E1897903819AD4F559943DF602DC) · [False cognates advantage in word form learning, *Cognition*](https://www.sciencedirect.com/science/article/abs/pii/S0010027720302961)

**Measurement:** [Izura, Cuetos & Brysbaert (2014) Lextale-Esp](https://www.researchgate.net/publication/259284868_Lextale-Esp_A_test_to_rapidly_and_efficiently_assess_the_Spanish_vocabulary_size) · [Single-Case Experimental Research (ERIC)](https://files.eric.ed.gov/fulltext/EJ1184160.pdf) · [Kratochwill & Levin, single-case credibility](https://societyforimplementationresearchcollaboration.org/wp-content/uploads/2011/12/Kratochwill-Levin-2010-Single-Case-Design1.pdf)
