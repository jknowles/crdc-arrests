#!/usr/bin/env bash
# Prime the local crdc_path() cache with the BIG public artifacts (the draws
# parquet tree and the pooled-model qs2 fits) so subsequent renders avoid
# multi-gigabyte re-downloads. Small stage artifacts are read directly from HF.
#
# Honors CRDC_ARTIFACTS (default: the public HF dataset) and CRDC_CACHE
# (default: tools::R_user_dir("crdc-arrests","cache")). With CRDC_ARTIFACTS=export
# (owner, local) nothing is downloaded — crdc_path() returns local paths.
set -euo pipefail
cd "$(dirname "$0")/.."

Rscript -e '
source("R/crdc_path.R")
cat("base :", crdc_artifacts_base(), "\n")
cat("cache:", crdc_cache_dir(), "\n")
invisible(crdc_path("parquet"))                                   # mirror draws tree
for (m in c("m1","m2","m3","m4","m5"))
  invisible(crdc_path(sprintf("stages/models/pooled_%s.qs2", m))) # fetch pooled fits
cat("cache primed.\n")
'
