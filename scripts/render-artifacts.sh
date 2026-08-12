#!/usr/bin/env bash
# Render the Subsystem-3 artifacts (white paper, supplement, social posts)
# from PUBLISHED/cached data — no model fitting, no targets
# store needed. Each .qmd reads via crdc_path(); CRDC_ARTIFACTS selects the
# source: local "export" (owner) or hf:// (stranger, the default).
#
# Usage:
#   scripts/render-artifacts.sh                 # render all in-scope docs
#   CRDC_ARTIFACTS=export scripts/render-artifacts.sh   # render from local export/
#   scripts/render-artifacts.sh white_paper.qmd supplement.qmd   # a subset
#
# Tip: run scripts/cache-artifacts.sh first to mirror the big artifacts locally.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v quarto &> /dev/null; then
  echo "ERROR: Quarto CLI not found. Install from https://quarto.org and ensure it is on PATH."
  exit 1
fi

if [ "$#" -gt 0 ]; then
  DOCS=("$@")
else
  DOCS=("white_paper.qmd" "supplement.qmd" "social_media_posts.qmd")
fi

for d in "${DOCS[@]}"; do
  echo ">>> rendering $d"
  quarto render "$d"
done
echo "Done. HTML alongside each .qmd; figures in export/figures/."

if [ "${EXPORT_HUGO:-0}" = "1" ]; then
  # Site-deployment tooling, not published with this repo. Degrade with a clear
  # message rather than a "no such file" from the shell.
  if [ -x scripts/export-hugo-posts.sh ]; then
    scripts/export-hugo-posts.sh
  else
    echo "EXPORT_HUGO=1, but scripts/export-hugo-posts.sh is not present." >&2
    echo "It is Civilytics site-deployment tooling and is not part of the public repo." >&2
  fi
fi
