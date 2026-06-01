# Retained-driver wrappers around the heavy draws-DB reads. Folds the proven
# logic from tmp/build_api_artifacts.R + tmp/export_parquet_chunked.R into the
# committed pipeline. CRITICAL: keep `drv` alive for the connection's lifetime —
# an anonymous dbConnect(duckdb::duckdb(), ...) can be GC'd mid-job, shutting the
# database under the connection -> "Invalid connection".

#' Pick a DuckDB memory_limit (GB) as a fraction of physical RAM (Linux).
#' Falls back to 8 GB when /proc/meminfo is unavailable.
duckdb_mem_limit_gb <- function(fraction = 0.7) {
  mt <- tryCatch(grep("MemTotal", readLines("/proc/meminfo"), value = TRUE),
                 error = function(e) character(0))
  if (!length(mt)) return(8L)
  kb <- as.numeric(gsub("\\D", "", mt))
  max(8L, as.integer(floor((kb / 1024 / 1024) * fraction)))
}

#' Open a retained read connection to a DuckDB file, with bounded resources.
#' Returns list(drv, con); caller MUST call close_draws_con() when done.
open_draws_con <- function(db_path, read_only = TRUE,
                           memory_limit = NULL, threads = NULL, temp_dir = NULL) {
  drv <- duckdb::duckdb(dbdir = db_path, read_only = read_only)
  con <- DBI::dbConnect(drv)
  stopifnot(DBI::dbIsValid(con))
  if (!is.null(temp_dir)) {
    stopifnot(!grepl("'", temp_dir))
    dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
    DBI::dbExecute(con, sprintf("PRAGMA temp_directory='%s'", temp_dir))
  }
  if (!is.null(memory_limit)) {
    stopifnot(!grepl("'", memory_limit))
    DBI::dbExecute(con, sprintf("SET memory_limit='%s'", memory_limit))
  }
  if (!is.null(threads)) {
    DBI::dbExecute(con, sprintf("SET threads=%d", as.integer(threads)))
  }
  list(drv = drv, con = con)
}

#' Disconnect and shut down a retained connection from open_draws_con().
close_draws_con <- function(h) {
  DBI::dbDisconnect(h$con, shutdown = TRUE)
  duckdb::duckdb_shutdown(h$drv)
  invisible(NULL)
}

#' Build the summary API DuckDB from the big draws DB (retained driver).
#'
#' @param draws_db_path read-only source DuckDB holding predicted_draws.
#' @param api_path output API DuckDB (overwritten if present).
#' @param enroll_lookup,district_dim see build_arrest_summary().
#' @param data_release provenance string written to meta.
#' @param memory_limit,threads,temp_dir DuckDB resource bounds (NULL = defaults).
build_api_db <- function(draws_db_path, api_path, enroll_lookup, district_dim,
                         data_release,
                         memory_limit = NULL, threads = NULL, temp_dir = NULL) {
  dir.create(dirname(api_path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(api_path)) file.remove(api_path)

  h <- open_draws_con(draws_db_path, read_only = TRUE,
                      memory_limit = memory_limit, threads = threads,
                      temp_dir = temp_dir)
  on.exit(close_draws_con(h), add = TRUE, after = FALSE)

  build_arrest_summary(h$con, enroll_lookup, district_dim, api_path)
  build_state_summary(h$con, enroll_lookup, api_path)

  # district_dim as its own lookup table (own short-lived connection on api_path)
  acon <- DBI::dbConnect(duckdb::duckdb(), dbdir = api_path, read_only = FALSE)
  on.exit(DBI::dbDisconnect(acon, shutdown = TRUE), add = TRUE, after = FALSE)
  DBI::dbWriteTable(acon, "district_dim", district_dim, overwrite = TRUE)

  write_api_meta(api_path, data_release = data_release)
  invisible(api_path)
}

#' Export Hive-partitioned parquet from the big draws DB (retained driver).
#'
#' @param draws_db_path read-only source DuckDB holding predicted_draws.
#' @param out_dir output parquet directory.
#' @param memory_limit,threads,temp_dir DuckDB resource bounds (NULL = defaults).
build_draws_parquet <- function(draws_db_path, out_dir,
                                memory_limit = NULL, threads = NULL,
                                temp_dir = NULL) {
  h <- open_draws_con(draws_db_path, read_only = TRUE,
                      memory_limit = memory_limit, threads = threads,
                      temp_dir = temp_dir)
  on.exit(close_draws_con(h), add = TRUE)
  export_draws_parquet(h$con, out_dir)  # pragmas already set on the connection
  invisible(out_dir)
}
