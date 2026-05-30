library(DBI)

#' Export predicted_draws to Hive-partitioned Parquet for bulk distribution.
#'
#' Partitions by (model_id, YEAR, LEA_STATE) and sorts within shard by
#' (LEAID, RACE, SEX) for row-group pruning. Target ~10-50 MB/shard on real data.
#'
#' @param draws_con open DBI connection holding `predicted_draws`.
#' @param out_dir output directory (created if missing).
export_draws_parquet <- function(draws_con, out_dir) {
  stopifnot(!grepl("'", out_dir))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  sql <- sprintf("
    COPY (
      SELECT * FROM predicted_draws ORDER BY model_id, YEAR, LEA_STATE, LEAID, RACE, SEX
    ) TO '%s'
    (FORMAT parquet, PARTITION_BY (model_id, YEAR, LEA_STATE), OVERWRITE_OR_IGNORE)",
    out_dir)
  DBI::dbExecute(draws_con, sql)
  invisible(out_dir)
}
