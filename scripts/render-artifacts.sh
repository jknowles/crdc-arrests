#!/usr/bin/env bash
# Render the Subsystem-3 artifacts (white paper, results, applied examples,
# social posts, EDA) from PUBLISHED/cached data — no model fitting, no targets
# store needed. Each .qmd reads via crdc_path(); CRDC_ARTIFACTS selects the
# source: local "export" (owner) or hf:// (stranger, the default).
#
# Usage:
#   scripts/render-artifacts.sh                 # render all in-scope docs
#   CRDC_ARTIFACTS=export scripts/render-artifacts.sh   # render from local export/
#   scripts/render-artifacts.sh white_paper.qmd results.qmd   # a subset
#
# Tip: run scripts/cache-artifacts.sh first to mirror the big artifacts locally.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -gt 0 ]; then
  DOCS=("$@")
else
  DOCS=("white_paper.qmd" "results.qmd" "applied_examples.qmd"
        "social_media_posts.qmd" "combined_eda.qmd")
fi

for d in "${DOCS[@]}"; do
  echo ">>> rendering $d"
  quarto render "$d"
done
echo "Done. HTML alongside each .qmd; figures in export/figures/."
