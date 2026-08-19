#!/usr/bin/env bash
# setup.sh - everything needed before opening LinguaKey.xcodeproj.
#
# Idempotent. Run it again any time; it rebuilds only what is missing.
set -euo pipefail
cd "$(dirname "$0")"

step() { printf '\n=== %s ===\n' "$1"; }

step "linguistic tables"
if [[ -f build/morphology/manifest.json && -f build/lexicon/manifest.json ]]; then
  echo "  already built. delete build/morphology and build/lexicon to force a rebuild."
else
  echo "  this downloads ~200 MB of source corpora and takes a few minutes"
  tools/build-data/fetch.sh
  python3 tools/build-data/build_morphology.py
  python3 tools/build-data/build_lexicon.py
fi

step "staging the runtime data root"
./tools/stage-data.sh

step "local build settings"
if [[ -f LinguaKeyApp/Local.xcconfig ]]; then
  echo "  LinguaKeyApp/Local.xcconfig already exists, leaving it alone"
else
  cp LinguaKeyApp/Local.xcconfig.example LinguaKeyApp/Local.xcconfig
  echo "  created LinguaKeyApp/Local.xcconfig from the example"
  echo "  EDIT IT: set DEVELOPMENT_TEAM to your ten-character Team ID and"
  echo "  BUNDLE_PREFIX to a reverse-DNS prefix. Signing fails until you do."
fi

step "checks"
./check.sh

cat <<'NEXT'

Next:
  1. Edit LinguaKeyApp/Local.xcconfig if you have not already.
  2. open LinguaKey.xcodeproj
  3. Select the LinguaKey scheme and your iPhone, then Run.
  4. On the phone: Settings > General > VPN & Device Management, trust the
     developer certificate. A free personal team's build expires after 7 days.
  5. In the app, Setup > Download the Spanish pack.

NEXT
