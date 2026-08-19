#!/usr/bin/env bash
# Assemble the runtime data root that LinguaKeyCore's `Tables(root:)` and
# `Interference(root:)` expect.
#
# The pieces live apart in the repository for good reasons: `build/` is
# generated and `data/` is hand-curated. At runtime they are one directory,
# because the keyboard extension gets a single App Group container URL and
# should not have to know how the repository is organised.
#
#   ./tools/stage-data.sh [destination]
#
# Default destination is build/LinguaKeyData. Add that folder to the Xcode
# project as a FOLDER REFERENCE (blue), not a group (yellow): a group flattens
# the tree and the two subdirectories would collide on manifest.json.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="${1:-$root/build/LinguaKeyData}"

for required in "$root/build/morphology/manifest.json" \
                "$root/build/lexicon/manifest.json" \
                "$root/data/interference.json"; do
    if [[ ! -f "$required" ]]; then
        echo "missing: ${required#$root/}" >&2
        echo "run tools/build-data/fetch.sh and the two build scripts first" >&2
        exit 1
    fi
done

rm -rf "$dest"
mkdir -p "$dest"
cp -R "$root/build/morphology" "$dest/morphology"
cp -R "$root/build/lexicon" "$dest/lexicon"
cp "$root/data/interference.json" "$dest/interference.json"

echo "staged -> ${dest#$root/}"
du -sh "$dest" | awk '{print "  total  " $1}'
echo "  morphology  $(du -sh "$dest/morphology" | awk '{print $1}')"
echo "  lexicon     $(du -sh "$dest/lexicon" | awk '{print $1}')"
