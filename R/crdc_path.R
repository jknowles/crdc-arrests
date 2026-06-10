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

# Mirror the partitioned draws tree to a local dir once, via DuckDB (no new dep).
.crdc_mirror_parquet <- function(remote, local) {
  drv <- duckdb::duckdb(); con <- DBI::dbConnect(drv)
  on.exit({DBI::dbDisconnect(con, shutdown = TRUE); duckdb::duckdb_shutdown(drv)})
  DBI::dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
  DBI::dbExecute(con, sprintf(
    "COPY (SELECT * FROM read_parquet('%s/**/*.parquet', hive_partitioning=true))
       TO '%s' (FORMAT parquet, PARTITION_BY (model_id, YEAR, LEA_STATE), OVERWRITE_OR_IGNORE)",
    remote, local))
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
    utils::download.file(.crdc_http(base, rel), local, mode = "wb")
  }
  local
}
