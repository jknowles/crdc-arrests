#!/usr/bin/env bash
# Render social_media_posts.qmd to gfm (reusing frozen compute) and split it
# into Hugo page bundles under export/hugo/posts/<slug>/.
set -euo pipefail
cd "$(dirname "$0")/.."
export CRDC_ARTIFACTS="${CRDC_ARTIFACTS:-export}"

echo ">>> rendering social_media_posts.qmd -> gfm (frozen)"
quarto render social_media_posts.qmd --to gfm

echo ">>> exporting Hugo page bundles"
Rscript -e 'source("R/export_hugo_posts.R"); dirs <- export_hugo_posts("social_media_posts.md"); cat(length(dirs), "bundles:\n"); cat(dirs, sep="\n")'

echo "Done. Bundles in export/hugo/posts/."
