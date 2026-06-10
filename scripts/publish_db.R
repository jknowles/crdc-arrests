#!/usr/bin/env Rscript
# Publish the compact summary DuckDB to Hugging Face as summary.duckdb.
# Requires the `hf` CLI + either a WRITE-scoped HF_TOKEN in the environment or a
# stored `hf auth login` session. Usage: Rscript scripts/publish_db.R
db <- "export/api/crdc_api.duckdb"
repo <- "civilytics/crdc-school-arrest-rates"
release <- "civilytics-crdc-arrests-2025.1"
stopifnot(file.exists(db))
# Accept either an HF_TOKEN env var or a stored `hf auth login` session (mirrors
# scripts/publish_hf.R) so the publish works without exporting a token.
authed <- nzchar(Sys.getenv("HF_TOKEN")) ||
  identical(suppressWarnings(system("hf auth whoami",
            ignore.stdout = TRUE, ignore.stderr = TRUE)), 0L)
if (!authed) {
  stop("Not authenticated to Hugging Face. Either run `hf auth login` ",
       "(paste a WRITE token) or set HF_TOKEN=hf_... with write scope, then re-run.")
}

cmd <- sprintf(
  "hf upload %s %s summary.duckdb --repo-type=dataset --commit-message='%s'",
  repo, shQuote(db), paste("publish summary", release))
message("Running: ", cmd)
status <- system(cmd)
if (status != 0) stop("HF upload failed (status ", status, ")")
message("Published. Set DATA_URL to:")
message(sprintf("https://huggingface.co/datasets/%s/resolve/main/summary.duckdb", repo))
