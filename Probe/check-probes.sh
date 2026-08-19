#!/usr/bin/env bash
# check-probes.sh - self-check for the Phase 01 probe harness.
#
# Asserts that every expected PROBE <id> | <key> pair is present in the log,
# naming what is missing. The smallest thing that fails if a probe silently did
# not run. No framework.
#
# Usage: bash Probe/check-probes.sh path/to/probe-log.txt
set -euo pipefail

LOG="${1:-probe-log.txt}"

if [[ ! -f "$LOG" ]]; then
  echo "FAIL: no log at $LOG"
  exit 1
fi

EXPECTED=(
  "P0|container.kind"
  "P0|appgroup.write"
  "P0|fullaccess.viewDidLoad"
  "P0|fullaccess.viewWillAppear"
  "P1|availability.en_es"
  "P1|translation.en_es.result"
  "P1|footprint.before"
  "P1|footprint.after"
  "P2|jetsam.last_footprint_mb"
  "P2|mmap.footprint_before"
  "P2|mmap.footprint_after"
  "P3|availability.it_es"
  "P4|os_proc_avail.usable"
  "P4|nltagger.schemes.es"
  "P4|nltagger.lemma.llegare"
  "P4|textchecker.languages"
  "P4|lexicon.entries"
  "P4|langrecognizer.sample"
  "P4|proxy.context"
  "P4|speech.voices.es"
  "P4|speech.speak"
  "P5|glass.frame_ms"
)

missing=()
for pair in "${EXPECTED[@]}"; do
  id="${pair%%|*}"
  key="${pair##*|}"
  if ! grep -q "PROBE ${id} | ${key}" "$LOG"; then
    missing+=("$pair")
  fi
done

recorded=$(grep -c "^.*PROBE " "$LOG" || true)

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "FAIL: ${#missing[@]} expected probe(s) never recorded:"
  printf '  - %s\n' "${missing[@]}"
  echo "($recorded observations present)"
  exit 1
fi

echo "PASS: all ${#EXPECTED[@]} expected probes recorded ($recorded observations total)"
