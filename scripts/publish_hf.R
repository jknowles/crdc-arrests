#!/usr/bin/env Rscript
# Publish partitioned Parquet shards to the Hugging Face dataset repo.
# Requires the `huggingface-cli` on PATH and `HF_TOKEN` in the environment.
# Usage: Rscript scripts/publish_hf.R export/parquet
args <- commandArgs(trailingOnly = TRUE)
parquet_dir <- if (length(args)) args[[1]] else "export/parquet"
repo <- "civilytics/crdc-school-arrest-rates"
stopifnot(nzchar(Sys.getenv("HF_TOKEN")), dir.exists(parquet_dir))

cmd <- sprintf(
  "huggingface-cli upload %s %s parquet --repo-type=dataset --commit-message='%s'",
  repo, shQuote(parquet_dir), "publish parquet civilytics-crdc-arrests-2025.1")
message("Running: ", cmd)
status <- system(cmd)
if (status != 0) stop("HF upload failed (status ", status, ")")
message("Done.")
