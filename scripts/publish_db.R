#!/usr/bin/env Rscript
# Publish the compact summary DuckDB to Hugging Face as summary.duckdb.
# Requires `huggingface-cli` + HF_TOKEN. Usage: Rscript scripts/publish_db.R
db <- "export/api/crdc_api.duckdb"
repo <- "civilytics/crdc-school-arrest-rates"
release <- "civilytics-crdc-arrests-2025.1"
stopifnot(nzchar(Sys.getenv("HF_TOKEN")), file.exists(db))

cmd <- sprintf(
  "huggingface-cli upload %s %s summary.duckdb --repo-type=dataset --commit-message='%s'",
  repo, shQuote(db), paste("publish summary", release))
message("Running: ", cmd)
status <- system(cmd)
if (status != 0) stop("HF upload failed (status ", status, ")")
message("Published. Set DATA_URL to:")
message(sprintf("https://huggingface.co/datasets/%s/resolve/main/summary.duckdb", repo))
