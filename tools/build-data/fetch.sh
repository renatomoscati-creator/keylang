#!/usr/bin/env bash
# fetch.sh - download the third-party linguistic sources the data pipeline builds from.
#
# Nothing downloaded here is committed. The build outputs are, and each carries
# its source and licence in the manifest.
#
# Sources and licences:
#   unimorph/spa          Spanish morphology, lemma + surface + UniMorph features   CC BY-SA 3.0
#   doozan/spanish_data   lemma frequency with POS, derived from OpenSubtitles      CC BY-SA 3.0
#   hermitdave            word-form frequency, OpenSubtitles 2018                   CC BY-SA 3.0
#
# CC BY-SA is copyleft on the DATA. A derived compiled table is plausibly an
# adaptation, so the generated artifacts are published alongside the app with
# attribution. This does not affect the app's own source licence.
set -euo pipefail

OUT="${1:-build/sources}"
mkdir -p "$OUT"

fetch() {
  local url="$1" dest="$2"
  if [[ -s "$OUT/$dest" ]]; then
    echo "have  $dest"
    return
  fi
  echo "get   $dest"
  curl -sSfL --max-time 300 -o "$OUT/$dest" "$url"
}

fetch https://raw.githubusercontent.com/unimorph/spa/master/spa                                   spa-unimorph.tsv
fetch https://raw.githubusercontent.com/doozan/spanish_data/master/frequency.csv                  es-frequency.csv
fetch https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/es/es_50k.txt es-forms-50k.txt
fetch https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt en-forms-50k.txt
fetch https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/it/it_50k.txt it-forms-50k.txt

echo
ls -la "$OUT"
