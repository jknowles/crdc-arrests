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

#' Resolve `rel` to a local path ONLY if it is already available — a local base,
#' or already cached for a remote base. NEVER downloads (unlike crdc_path() for
#' big objects). Returns NA_character_ if not present. Use for optional inputs
#' (e.g. the ~2.9 GB pooled fits) so a render degrades gracefully to a table.
crdc_cached_path <- function(rel) {
  base <- crdc_artifacts_base()
  p <- if (!grepl("^(hf://|https://|s3://)", base)) file.path(base, rel)
       else file.path(crdc_cache_dir(), rel)
  if (file.exists(p) || dir.exists(p)) p else NA_character_
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

#' Apply Civilytics branding to ALL figures in a document. Call ONCE in a doc's
#' setup chunk. Sets the ggplot theme globally (no extra deps) and, when `magick`
#' is available, stamps the Civilytics logo onto every rendered PNG via a knitr
#' `fig.process` hook. Degrades gracefully (theme only) when magick is absent.
#' Returns TRUE if the logo hook was installed, FALSE otherwise (invisibly).
cv_apply_branding <- function(logo = TRUE,
                              position = c("bottom-right", "bottom-left",
                                           "top-right", "top-left"),
                              type = c("wordmark", "mark"),
                              height_frac = 0.06) {
  position <- match.arg(position); type <- match.arg(type)
  ggplot2::theme_set(civilytics::theme_civilytics())          # theme on every figure
  if (!isTRUE(logo)) return(invisible(FALSE))
  if (!requireNamespace("magick", quietly = TRUE)) {
    message("cv_apply_branding(): theme set; magick not installed, logo overlay skipped.")
    return(invisible(FALSE))
  }
  logo_file <- system.file("img",
    if (type == "mark") "civilytics-mark.png" else "civilytics-wordmark.png",
    package = "civilytics")
  grav <- switch(position, `bottom-right` = "southeast", `bottom-left` = "southwest",
                 `top-right` = "northeast", `top-left` = "northwest")
  knitr::opts_chunk$set(fig.process = function(path, options = NULL) {
    if (!grepl("\\.png$", path, ignore.case = TRUE) || !nzchar(logo_file)) return(path)
    img <- magick::image_read(path)
    h   <- magick::image_info(img)$height
    lg  <- magick::image_resize(
      magick::image_read(logo_file),
      magick::geometry_size_pixels(height = max(1L, round(h * height_frac))))
    magick::image_write(
      magick::image_composite(img, lg, gravity = grav, offset = "+18+14"), path)
    path
  })
  invisible(TRUE)
}
