#' Shared render helpers for the Subsystem-3 docs (paper + standalone reports).
#'
#' These return native handles/frames; the docs still issue native
#' get_prediction_summary()/SQL. They are path/connection helpers, not
#' data-access wrappers.

#' Open a DuckDB connection exposing `predicted_draws` as a VIEW over the
#' published draws parquet (local mirror or hf://). The existing
#' get_prediction_summary()/get_state_prediction_summary() work unchanged
#' against this connection. Close with close_draws_view().
#'
#' NB: distinct from build_api_artifacts.R::open_draws_con(), which opens the
#' raw 69 GB DuckDB DB (Subsystem 1/2). This one is published-parquet-backed.
open_draws_view <- function() {
  drv <- duckdb::duckdb(); con <- DBI::dbConnect(drv)
  DBI::dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
  DBI::dbExecute(con, sprintf(
    "CREATE VIEW predicted_draws AS
       SELECT * FROM read_parquet('%s/**/*.parquet', hive_partitioning=true)",
    crdc_path("parquet")))
  list(con = con, drv = drv)
}

#' Close a handle returned by open_draws_view().
close_draws_view <- function(h) {
  DBI::dbDisconnect(h$con, shutdown = TRUE)
  duckdb::duckdb_shutdown(h$drv)
}

#' Read a tabular stage artifact into a data.frame via DuckDB.
read_stage_df <- function(rel) {
  drv <- duckdb::duckdb(); con <- DBI::dbConnect(drv)
  on.exit({DBI::dbDisconnect(con, shutdown = TRUE); duckdb::duckdb_shutdown(drv)})
  DBI::dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
  DBI::dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", crdc_path(rel)))
}

#' Attach registry display labels by model_id.
with_model_labels <- function(df, id_col = "model_id") {
  df$model_label <- crdc_model_label(df[[id_col]])
  df
}
