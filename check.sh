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
run "arm assignment"    bash -c 'cd tools/engine && python3 test_arms.py'
run "swift invariants"  python3 tools/check_invariants.py
run "xcode project"     python3 tools/check_project.py

printf '\n=== golden vectors are current ===\n'
golden_check() {
  local file="$1" script="$2" what="$3"
  local before after
  before=$(sha256sum "build/golden/$file" 2>/dev/null | cut -d' ' -f1)
  (cd tools/engine && python3 "$script" >/dev/null)
  after=$(sha256sum "build/golden/$file" | cut -d' ' -f1)
  if [[ "$before" != "$after" ]]; then
    echo "!! $file was stale and has been regenerated."
    echo "   $what changed. Commit the new file and note it in STATE.md."
    fail=1
  else
    echo "  ok  $file unchanged"
  fi
}
golden_check fsrs-golden.json golden.py      "The memory model"
golden_check arms-golden.json golden_arms.py "Arm assignment"

printf '\n'
if [[ $fail -ne 0 ]]; then
  echo "FAILED"
  exit 1
fi
echo "ALL CHECKS PASSED"
