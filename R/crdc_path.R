#' Resolve a logical artifact path to a URI for native readers.
#'
#' Returns a STRING usable by DuckDB `read_parquet()`, `qs2::qs_read()`, or
#' `download.file()`. Big objects (draws parquet tree, unified-fit qs2) are cached
#' locally on first use; small objects resolve to the remote URI for direct
#' (range) reads. This resolves a path + caches — it does NOT read data.
crdc_artifacts_base <- function() {
  Sys.getenv("CRDC_ARTIFACTS",
             "hf://datasets/civilytics/crdc-school-arrest-rates@civilytics-crdc-arrests-2025.1")
}

crdc_cache_dir <- function() {
  Sys.getenv("CRDC_CACHE", tools::R_user_dir("crdc-arrests", which = "cache"))
}

# Big objects to cache locally: the draws tree and the unified-fit qs2 files.
.crdc_is_big <- function(rel) {
  grepl("^parquet(/|$)", rel) || grepl("^stages/models/", rel)
}

# Convert an hf:// dataset base (optionally "@revision") + rel to an https
# "resolve" URL for download.file().
.crdc_http <- function(base, rel) {
  m    <- regmatches(base, regexec("^hf://datasets/(.+?)(?:@([^/]+))?$", base))[[1]]
  repo <- m[2]
  rev  <- if (length(m) >= 3 && nzchar(m[3])) m[3] else "main"
  sprintf("https://huggingface.co/datasets/%s/resolve/%s/%s", repo, rev, rel)
}

# HuggingFace access token from the usual env vars ("" if none set). Treats an
# empty HF_TOKEN as absent so it falls through to HUGGING_FACE_HUB_TOKEN.
.crdc_hf_token <- function() {
  tok <- Sys.getenv("HF_TOKEN", "")
  if (!nzchar(tok)) tok <- Sys.getenv("HUGGING_FACE_HUB_TOKEN", "")
  tok
}

# Authenticate a DuckDB httpfs connection to HuggingFace when a token is present,
# so hf:// reads/writes use the (much higher) authenticated rate limit instead of
# the low anonymous limit that triggers HTTP 429 on the bulk parquet mirror.
# No-op when no token is set; tolerant of older DuckDB without the hf secret type.
.crdc_hf_auth <- function(con) {
  token <- .crdc_hf_token()
  if (nzchar(token)) {
    try(DBI::dbExecute(con, sprintf(
      "CREATE OR REPLACE SECRET crdc_hf (TYPE huggingface, TOKEN '%s')",
      gsub("'", "''", token))), silent = TRUE)
  }
  invisible(con)
}

# Run fn(), retrying on transient HuggingFace rate-limit / HTTP errors with
# exponential backoff. Re-raises non-retryable errors immediately and the last
# error after exhausting attempts.
.crdc_with_retry <- function(fn, tries = 5L, base_wait = 2) {
  for (i in seq_len(tries)) {
    out <- tryCatch(fn(), error = function(e) e)
    if (!inherits(out, "error")) return(out)
    msg <- conditionMessage(out)
    retryable <- grepl("429|rate.?limit|HTTP (4|5)[0-9][0-9]|timeout|temporar",
                       msg, ignore.case = TRUE)
    if (!retryable || i == tries) stop(out)
    wait <- base_wait * 2^(i - 1L)
    message(sprintf("HF request failed (attempt %d/%d): %s\n  retrying in %ds...",
                    i, tries, msg, wait))
    Sys.sleep(wait)
  }
}

# Mirror the partitioned draws tree to a local dir once, via DuckDB (no new dep).
# Authenticates with HF_TOKEN when available and retries the heavy COPY on 429.
.crdc_mirror_parquet <- function(remote, local) {
  drv <- duckdb::duckdb(); con <- DBI::dbConnect(drv)
  on.exit({DBI::dbDisconnect(con, shutdown = TRUE); duckdb::duckdb_shutdown(drv)})
  DBI::dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
  .crdc_hf_auth(con)
  copy_sql <- sprintf(
    "COPY (SELECT * FROM read_parquet('%s/**/*.parquet', hive_partitioning=true))
       TO '%s' (FORMAT parquet, PARTITION_BY (model_id, YEAR, LEA_STATE), OVERWRITE_OR_IGNORE)",
    remote, local)
  .crdc_with_retry(function() DBI::dbExecute(con, copy_sql))
  invisible(local)
}

crdc_path <- function(rel) {
  base <- crdc_artifacts_base()
  # Local base: return the file path directly (no network, no cache).
  if (!grepl("^(hf://|https://|s3://)", base)) {
    return(file.path(base, rel))
  }
  # Remote small object: direct read against the remote URI (DuckDB reads hf://).
  if (!.crdc_is_big(rel)) {
    return(paste0(base, "/", rel))
  }
  # Remote big object: ensure cached, return local path.
  local <- file.path(crdc_cache_dir(), rel)
  if (file.exists(local) || dir.exists(local)) return(local)
  dir.create(dirname(local), recursive = TRUE, showWarnings = FALSE)
  if (grepl("^parquet(/|$)", rel)) {
    .crdc_mirror_parquet(paste0(base, "/", rel), local)
  } else {
    url   <- .crdc_http(base, rel)
    token <- .crdc_hf_token()
    hdrs  <- if (nzchar(token)) c(Authorization = paste("Bearer", token)) else NULL
    .crdc_with_retry(function()
      utils::download.file(url, local, mode = "wb", quiet = TRUE, headers = hdrs))
  }
  local
}
