#!/usr/bin/env Rscript
# Publish partitioned Parquet shards to the Hugging Face dataset repo.
#
# MIRRORS export/parquet -> <repo>/parquet in a SINGLE atomic commit via
# `hf upload --delete '*'`. A plain upload only overwrites same-named files; on a
# re-publish where the new export produced fewer shard files in a partition, the
# stale remote files would survive as orphans -> duplicate rows on HF (the same
# failure mode as the 2026-06 local export bug). `--delete` patterns are relative
# to PATH_IN_REPO (parquet/), so the mirror removes stale shards while leaving
# summary.duckdb and stages/ at the repo ROOT untouched. One commit => there is
# never a window where parquet/ is missing/stale, and an interrupted upload
# leaves the previous content in place.
#
# Requires the `hf` (huggingface_hub) CLI on PATH and a WRITE-scoped HF_TOKEN in
# the environment (or `hf auth login`).
# Usage: Rscript scripts/publish_hf.R [export/parquet]
args <- commandArgs(trailingOnly = TRUE)
parquet_dir <- if (length(args)) args[[1]] else "export/parquet"
repo <- "civilytics/crdc-school-arrest-rates"
stopifnot(dir.exists(parquet_dir))
# Accept either an HF_TOKEN env var or a stored `hf auth login` session.
authed <- nzchar(Sys.getenv("HF_TOKEN")) ||
  identical(suppressWarnings(system("hf auth whoami",
            ignore.stdout = TRUE, ignore.stderr = TRUE)), 0L)
if (!authed) {
  stop("Not authenticated to Hugging Face. Either run `hf auth login` ",
       "(paste a WRITE token) or set HF_TOKEN=hf_... with write scope, then re-run.")
}

run <- function(cmd) {
  message("Running: ", cmd)
  status <- system(cmd)
  if (status != 0) stop("command failed (status ", status, "): ", cmd)
}

# Atomic mirror: upload the clean local shards and, in the SAME commit, delete
# any remote files under parquet/ not present locally (--delete '*', relative to
# path_in_repo). fnmatch '*' matches recursively. summary.duckdb and stages/ at
# the repo root are untouched.
run(sprintf(
  "hf upload %s %s parquet --repo-type=dataset --delete '*' --commit-message='%s'",
  repo, shQuote(parquet_dir),
  "publish de-duplicated parquet; mirror parquet/ (orphan-shard fix)"))

message("Done. Remote <repo>/parquet now mirrors ", parquet_dir, ".")
