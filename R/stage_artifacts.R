#' Staged-intermediate artifact materializers (Subsystem 3).
#'
#' These run owner-side (in the targets pipeline) and read the store. They write
#' portable parquet/qs2 under export/stages/ for publishing to the HF dataset so
#' a stranger can render the docs without the 7-day run. Reads stay native;
#' these are write-side helpers.

#' Write a data.frame to a parquet file via DuckDB (no arrow dependency).
stage_write_parquet <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  drv <- duckdb::duckdb(); con <- DBI::dbConnect(drv)
  on.exit({DBI::dbDisconnect(con, shutdown = TRUE); duckdb::duckdb_shutdown(drv)})
  duckdb::duckdb_register(con, "df_tmp", df)
  DBI::dbExecute(con, sprintf("COPY df_tmp TO '%s' (FORMAT parquet)", path))
  duckdb::duckdb_unregister(con, "df_tmp")
  path
}

#' Materialize the four model-input artifacts (the lists' $data frames).
stage_inputs_artifacts <- function(three_year_data, recent_data,
                                    combined_model_data, combined_sch_data,
                                    dir = "export/stages") {
  c(
    stage_write_parquet(three_year_data$data, file.path(dir, "inputs/three_year_data.parquet")),
    stage_write_parquet(recent_data$data,     file.path(dir, "inputs/recent_data.parquet")),
    stage_write_parquet(combined_model_data,  file.path(dir, "inputs/combined_model_data.parquet")),
    stage_write_parquet(combined_sch_data,    file.path(dir, "inputs/combined_sch_data.parquet"))
  )
}

#' Materialize the raw/intermediate CRDC artifacts. `named` is a named list of
#' data.frames; each is written to stages/crdc/<name>.parquet.
stage_crdc_artifacts <- function(named, dir = "export/stages") {
  stopifnot(!is.null(names(named)), all(nzchar(names(named))))
  vapply(names(named), function(nm)
    stage_write_parquet(named[[nm]], file.path(dir, "crdc", paste0(nm, ".parquet"))),
    character(1), USE.NAMES = FALSE)
}
