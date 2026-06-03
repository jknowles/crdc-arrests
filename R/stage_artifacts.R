#' Staged-intermediate artifact materializers (Subsystem 3).
#'
#' These run owner-side (in the targets pipeline) and read the store. They write
#' portable parquet/qs2 under export/stages/ for publishing to the HF dataset so
#' a stranger can render the docs without the 7-day run. Reads stay native;
#' these are write-side helpers.

#' Coerce a vector's strings to valid UTF-8. Parquet requires UTF-8; some CRDC
#' source strings (e.g. school names) carry Windows-1252 bytes such as 0x96
#' (en-dash) that DuckDB rejects on read. Only invalid-UTF-8 entries are
#' re-encoded (from Windows-1252, the common source); valid UTF-8 passes through.
.stage_to_utf8 <- function(x) {
  if (is.factor(x)) { levels(x) <- .stage_to_utf8(levels(x)); return(x) }
  if (!is.character(x)) return(x)
  bad <- !validUTF8(x)
  if (any(bad)) x[bad] <- iconv(x[bad], from = "windows-1252", to = "UTF-8", sub = "?")
  enc2utf8(x)
}

#' Write a data.frame to a parquet file via DuckDB (no arrow dependency).
stage_write_parquet <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  df[] <- lapply(df, .stage_to_utf8)                # parquet requires valid UTF-8
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

#' Materialize calculate_model_stats() across a named list of model objects,
#' tagged with model_id + registry label. `stats_fn` is injectable for testing.
stage_model_stats <- function(models, dir = "export/stages",
                              stats_fn = calculate_model_stats) {
  stopifnot(!is.null(names(models)))
  rows <- lapply(names(models), function(id) {
    s <- stats_fn(models[[id]], model_prefix = id)
    s$model_id    <- id
    s$model_label <- crdc_model_label(id)
    s
  })
  df <- do.call(rbind, rows)
  stage_write_parquet(df, file.path(dir, "diagnostics/model_stats.parquet"))
}

#' Extract structured HMC sampler diagnostics for the pooled fits.
#' `pooled_fits` is a named list of brmsfit objects (names = model_id).
stage_hmc_diagnostics <- function(pooled_fits, dir = "export/stages") {
  rows <- lapply(names(pooled_fits), function(id) {
    sf <- pooled_fits[[id]]$fit
    data.frame(
      model_id      = id,
      model_label   = crdc_model_label(id),
      num_divergent = rstan::get_num_divergent(sf),
      num_max_tree  = rstan::get_num_max_treedepth(sf),
      min_bfmi      = suppressWarnings(min(rstan::get_bfmi(sf))),
      stringsAsFactors = FALSE
    )
  })
  stage_write_parquet(do.call(rbind, rows),
                      file.path(dir, "diagnostics/hmc_diagnostics.parquet"))
}

#' Save the pooled (nat_*) brms fits as qs2, named by spec (pooled_m#.qs2).
stage_pooled_fits <- function(pooled_fits, dir = "export/stages") {
  reg <- crdc_model_registry()
  vapply(names(pooled_fits), function(id) {
    spec <- reg$spec[match(id, reg$id)]
    path <- file.path(dir, "models", sprintf("pooled_%s.qs2", spec))
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    qs2::qs_save(pooled_fits[[id]], path)
    path
  }, character(1), USE.NAMES = FALSE)
}
