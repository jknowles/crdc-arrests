#!/usr/bin/env bash
# Run the project's testthat suites. Optional first arg = a testthat filter
# (matched against test file names, e.g. "summarize_draws"). Exits non-zero if
# any test fails, so it is CI/agent friendly.
#
# Usage:
#   scripts/run-tests.sh                # both suites, all tests
#   scripts/run-tests.sh summarize      # only test files matching "summarize"
set -euo pipefail
cd "$(dirname "$0")/.."

FILTER="${1:-}"

run_dir() {
  local dir="$1"
  [ -d "$dir" ] || { echo "skip: $dir (not present)"; return 0; }
  echo "== testthat: $dir ${FILTER:+(filter=$FILTER)} =="
  Rscript -e "
    args <- commandArgs(trailingOnly = TRUE)
    dir <- args[[1]]; flt <- if (length(args) > 1 && nzchar(args[[2]])) args[[2]] else NULL
    res <- as.data.frame(testthat::test_dir(dir, filter = flt, reporter = 'summary', stop_on_failure = FALSE))
    fails <- sum(res\$failed) + sum(res\$error)
    if (fails > 0) quit(status = 1)
  " "$dir" "$FILTER"
}

run_dir "tests/testthat"
run_dir "api/tests/testthat"
echo "All tests passed."
