library(DBI)

#' Export predicted_draws to Hive-partitioned Parquet for bulk distribution.
#'
#' Memory-safe: chunks per `model_id` (each pass sorts/buffers one model's rows,
#' not all 1.14B at once) and optionally bounds DuckDB memory/threads/spill. The
#' single-shot global ORDER BY + ~1500 simultaneous partition write-buffers OOM'd
#' a 63 GB box; this does not. Partition scheme (model_id, YEAR, LEA_STATE) and
#' within-shard sort (LEAID, RACE, SEX) are unchanged, so output shape is identical.
#'
#' @param draws_con open DBI connection holding `predicted_draws`.
#' @param out_dir output directory (created if missing).
#' @param memory_limit optional DuckDB memory_limit, e.g. "24GB" (NULL = leave default).
#' @param threads optional DuckDB thread cap (NULL = leave default).
#' @param temp_dir optional spill directory for temp_directory (NULL = leave default).
export_draws_parquet <- function(draws_con, out_dir,
                                 memory_limit = NULL, threads = NULL,
                                 temp_dir = NULL) {
  stopifnot(!grepl("'", out_dir))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  if (!is.null(temp_dir)) {
    dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
    DBI::dbExecute(draws_con, sprintf("PRAGMA temp_directory='%s'", temp_dir))
  }
  if (!is.null(memory_limit)) {
    DBI::dbExecute(draws_con, sprintf("SET memory_limit='%s'", memory_limit))
  }
  if (!is.null(threads)) {
    DBI::dbExecute(draws_con, sprintf("SET threads=%d", as.integer(threads)))
  }
  # No global buffering to preserve insertion order; we ORDER BY inside each COPY.
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
  invisible(out_dir)
}
