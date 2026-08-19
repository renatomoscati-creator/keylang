#!/usr/bin/env bash
# check.sh - run every check in the repo. Exits non-zero if anything fails.
#
# Everything here runs without Xcode and without a device. The on-device probes
# are Phase 01 and live in Probe/.
set -uo pipefail
cd "$(dirname "$0")"

fail=0
run() {
  local name="$1"; shift
  printf '\n=== %s ===\n' "$name"
  if "$@"; then
    return 0
  fi
  echo "!! $name FAILED"
  fail=1
}

if [[ ! -d build/morphology ]]; then
  echo "no build yet. run:"
  echo "  tools/build-data/fetch.sh && python3 tools/build-data/build_morphology.py"
  echo "  python3 tools/build-data/build_lexicon.py"
  exit 1
fi

run "morphology table"  python3 tools/build-data/check_morphology.py
run "lexicon tables"    python3 tools/build-data/check_lexicon.py
run "memory model"      bash -c 'cd tools/engine && python3 test_fsrs.py'
run "focus selection"   bash -c 'cd tools/engine && python3 test_focus.py'

printf '\n=== golden vectors are current ===\n'
before=$(sha256sum build/golden/fsrs-golden.json 2>/dev/null | cut -d' ' -f1)
(cd tools/engine && python3 golden.py >/dev/null)
after=$(sha256sum build/golden/fsrs-golden.json | cut -d' ' -f1)
if [[ "$before" != "$after" ]]; then
  echo "!! golden vectors were stale and have been regenerated."
  echo "   The memory model changed. Commit the new file and note it in STATE.md."
  fail=1
else
  echo "  ok  unchanged"
fi

printf '\n'
if [[ $fail -ne 0 ]]; then
  echo "FAILED"
  exit 1
fi
echo "ALL CHECKS PASSED"
