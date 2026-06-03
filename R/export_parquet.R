library(DBI)

#' Export predicted_draws to Hive-partitioned Parquet for bulk distribution.
#'
#' Memory-safe: chunks per `model_id` (each pass sorts/buffers one model's rows,
#' not all 1.14B at once) and optionally bounds DuckDB memory/threads/spill. The
#' single-shot global ORDER BY + ~1500 simultaneous partition write-buffers OOM'd
#' a 63 GB box; this does not. Partition scheme (model_id, YEAR, LEA_STATE) and
#' within-shard sort (LEAID, RACE, SEX) are unchanged, so output shape is identical.
#'
#' Idempotent + verified: `out_dir` is cleared before writing so re-running
#' cannot leave orphan shard files from a prior run (the cause of the 2026-06
#' within-YEAR duplicate-rows bug — `OVERWRITE_OR_IGNORE` overwrites same-named
#' shards but never deletes ones the new run doesn't recreate, and the
#' per-partition shard count is nondeterministic). After writing, per-model row
#' counts are checked against the source DB and the function errors on mismatch.
#'
#' @param draws_con open DBI connection holding `predicted_draws`.
#' @param out_dir output directory. WARNING: cleared (recursive unlink) at the
#'   start of each call to guarantee an idempotent, orphan-free export.
#' @param memory_limit optional DuckDB memory_limit, e.g. "24GB" (NULL = leave default).
#' @param threads optional DuckDB thread cap (NULL = leave default).
#' @param temp_dir optional spill directory for temp_directory (NULL = leave default).
export_draws_parquet <- function(draws_con, out_dir,
                                 memory_limit = NULL, threads = NULL,
                                 temp_dir = NULL) {
  stopifnot(!grepl("'", out_dir))
  # Idempotency guard: a re-run MUST start from an empty target. The per-model
  # COPY below uses OVERWRITE_OR_IGNORE, which overwrites same-named shard files
  # (data_0.parquet, ...) but never deletes shards a prior run wrote that this
  # run does not reproduce. Because the per-partition shard count is
  # nondeterministic (thread scheduling), re-running in place silently leaves
  # orphan shards -> exact duplicate rows. Clearing first makes export idempotent.
  stopifnot(nzchar(out_dir), !out_dir %in% c(".", "./", "/", ".."))
  unlink(out_dir, recursive = TRUE, force = TRUE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  if (!is.null(temp_dir)) {
    stopifnot(!grepl("'", temp_dir))
    dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
    DBI::dbExecute(draws_con, sprintf("PRAGMA temp_directory='%s'", temp_dir))
  }
  if (!is.null(memory_limit)) {
    stopifnot(!grepl("'", memory_limit))
    DBI::dbExecute(draws_con, sprintf("SET memory_limit='%s'", memory_limit))
  }
  if (!is.null(threads)) {
    DBI::dbExecute(draws_con, sprintf("SET threads=%d", as.integer(threads)))
  }
  # Let the engine skip the insertion-order scan; the explicit ORDER BY in each
  # COPY below governs row ordering within every shard.
  DBI::dbExecute(draws_con, "SET preserve_insertion_order=false")

  models <- DBI::dbGetQuery(
    draws_con,
    "SELECT DISTINCT model_id FROM predicted_draws ORDER BY model_id")$model_id

  for (m in models) {
    stopifnot(!grepl("'", m))
    sql <- sprintf("
      COPY (
        SELECT * FROM predicted_draws WHERE model_id = '%s'
        ORDER BY YEAR, LEA_STATE, LEAID, RACE, SEX
      ) TO '%s'
      (FORMAT parquet, PARTITION_BY (model_id, YEAR, LEA_STATE), OVERWRITE_OR_IGNORE)",
      m, out_dir)
    DBI::dbExecute(draws_con, sql)
  }

  # Defense in depth: assert the exported parquet has EXACTLY the source DB's
  # per-model row counts. A silent orphan/duplicate-shard regression (or a
  # partial write) would inflate or shrink these; fail loudly rather than
  # publish corrupt data. Counts come from parquet metadata, so this is cheap.
  db_counts <- DBI::dbGetQuery(
    draws_con,
    "SELECT model_id, COUNT(*) AS n FROM predicted_draws GROUP BY model_id")
  pq_counts <- DBI::dbGetQuery(
    draws_con,
    sprintf("SELECT model_id, COUNT(*) AS n
               FROM read_parquet('%s/**/*.parquet', hive_partitioning = true)
              GROUP BY model_id", out_dir))
  cmp <- merge(db_counts, pq_counts, by = "model_id",
               all = TRUE, suffixes = c("_db", "_parquet"))
  mismatch <- cmp[is.na(cmp$n_db) | is.na(cmp$n_parquet) | cmp$n_db != cmp$n_parquet, ]
  if (nrow(mismatch) > 0L) {
    stop("export_draws_parquet: exported parquet row counts != source DB ",
         "(possible orphan/duplicate shards or partial write):\n",
         paste(utils::capture.output(print(mismatch)), collapse = "\n"))
  }

  invisible(out_dir)
}
