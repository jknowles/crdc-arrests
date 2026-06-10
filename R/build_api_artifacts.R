# Retained-driver wrappers around the heavy draws-DB reads. Folds the proven
# logic from tmp/build_api_artifacts.R + tmp/export_parquet_chunked.R into the
# committed pipeline. CRITICAL: keep `drv` alive for the connection's lifetime —
# an anonymous dbConnect(duckdb::duckdb(), ...) can be GC'd mid-job, shutting the
# database under the connection -> "Invalid connection".

#' Detect total physical RAM in GB, cross-platform. Returns NA_real_ if the
#' platform can't be probed (caller falls back to a conservative default).
#'   * Linux:        /proc/meminfo MemTotal (kB)
#'   * macOS / BSD:  sysctl -n hw.memsize (bytes)
#'   * Windows:      PowerShell CIM Win32_ComputerSystem.TotalPhysicalMemory
#'                   (bytes); `wmic` is deprecated/removed on recent Windows.
detect_total_ram_gb <- function() {
  tryCatch({
    if (file.exists("/proc/meminfo")) {
      mt <- grep("MemTotal", readLines("/proc/meminfo"), value = TRUE)
      if (length(mt)) return(as.numeric(gsub("[^0-9]", "", mt)) / 1024 / 1024)
    }
    if (Sys.info()[["sysname"]] == "Windows") {
      out <- suppressWarnings(system2(
        "powershell",
        c("-NoProfile", "-Command",
          "(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory"),
        stdout = TRUE, stderr = FALSE))
      bytes <- suppressWarnings(as.numeric(out[nzchar(out)][1]))
      if (length(bytes) && is.finite(bytes)) return(bytes / 1024^3)
    } else if (nzchar(Sys.which("sysctl"))) {
      bytes <- suppressWarnings(
        as.numeric(system2("sysctl", c("-n", "hw.memsize"), stdout = TRUE)))
      if (length(bytes) && is.finite(bytes)) return(bytes / 1024^3)
    }
    NA_real_
  }, error = function(e) NA_real_)
}

#' Pick a DuckDB memory_limit (GB): detect RAM, take `fraction` of it, divide by
#' the number of heavy DuckDB jobs that may run concurrently, then clamp to
#' `cap_gb`. Falls back to 8 GB when RAM can't be detected.
#'
#' Why each knob matters:
#'   * fraction   — leave RAM for the OS and other crew workers.
#'   * concurrency — `memory_limit` is enforced PER DuckDB INSTANCE with no
#'     cross-instance coordination. api_db and draws_parquet run as sibling crew
#'     workers, so the SUM of their limits must fit in RAM or both climbing at
#'     once OOMs the box. Dividing by the co-run count keeps that sum bounded.
#'   * cap_gb     — this job's working set is small: the per-model chunked export
#'     ran fine under a ~44 GB limit on a 63 GB box (spilling the rest), so there
#'     is never a reason to hand a 256 GB machine 179 GB. The cap prevents a
#'     single instance from greedily ballooning even when RAM is plentiful.
#'   `memory_limit` is a SPILL THRESHOLD, not a reservation — DuckDB only uses
#'   what it needs and spills (to its isolated temp dir) beyond the limit.
duckdb_mem_limit_gb <- function(fraction = 0.7, concurrency = 1L, cap_gb = 64L) {
  total_gb <- detect_total_ram_gb()
  if (!length(total_gb) || !is.finite(total_gb)) return(8L)
  budget <- floor(total_gb * fraction / max(1L, as.integer(concurrency)))
  max(4L, min(as.integer(cap_gb), as.integer(budget)))
}

#' Create a process-unique spill subdirectory under `base` so concurrent DuckDB
#' instances never collide on temp_directory filenames. DuckDB names its spill
#' files deterministically per-instance (e.g. duckdb_temp_storage_S64K-0.tmp),
#' NOT globally uniquely; two instances sharing one temp dir overwrite and
#' truncate each other's spill files -> "Could not read enough bytes". Returns
#' the unique path (NULL if `base` is NULL); the caller must unlink() it.
make_spill_dir <- function(base) {
  if (is.null(base)) return(NULL)
  stopifnot(!grepl("'", base))
  uniq <- file.path(base, paste0("ddb-", Sys.getpid(), "-",
                                 basename(tempfile(""))))
  dir.create(uniq, recursive = TRUE, showWarnings = FALSE)
  uniq
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

  # Isolate this instance's spill files from any concurrent DuckDB build
  # (e.g. draws_parquet running in a sibling crew worker). Registered first so
  # it runs LAST on exit, after every connection is closed and temp files freed.
  spill <- make_spill_dir(temp_dir)
  if (!is.null(spill)) {
    on.exit(unlink(spill, recursive = TRUE, force = TRUE), add = TRUE, after = FALSE)
  }

  h <- open_draws_con(draws_db_path, read_only = TRUE,
                      memory_limit = memory_limit, threads = threads,
                      temp_dir = spill)
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
  # Per-invocation spill dir so a concurrent api_db build can't truncate our
  # temp files (DuckDB temp filenames are per-instance deterministic, not unique).
  spill <- make_spill_dir(temp_dir)
  h <- open_draws_con(draws_db_path, read_only = TRUE,
                      memory_limit = memory_limit, threads = threads,
                      temp_dir = spill)
  on.exit({
    close_draws_con(h)                 # close first so temp files are released,
    if (!is.null(spill)) {             # then remove the isolated spill dir
      unlink(spill, recursive = TRUE, force = TRUE)
    }
  }, add = TRUE)
  export_draws_parquet(h$con, out_dir)  # pragmas already set on the connection
  invisible(out_dir)
}
