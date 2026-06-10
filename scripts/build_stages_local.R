#!/usr/bin/env Rscript
# Build export/stages/ artifacts from the local targets store WITHOUT re-running
# the pipeline.
#
# Why not `tar_make()`? The staging targets transitively depend on raw-CSV
# `format="file"` targets whose source files live in the scratch `tmp/` dir
# (cleared on this box). tar_make() insists on re-validating/rebuilding that
# raw-ingestion chain — the very 7-day work Subsystem 3 exists to avoid. The
# built objects survive in `_targets/objects/`, and `tar_read_raw()` deserializes
# a stored object by name without re-validating upstream freshness. This is the
# correct owner-side rebuild path: the store survives, the raw scratch CSVs do
# not.
#
# Memory-safe: `model_stats` reads each nat fit + each sg dynamic-branch one at a
# time (the monolithic model_stats_artifact target would deserialize all 45 fits
# ~40-60 GB at once). The produced parquet is byte-identical to what the target
# would write (calculate_model_stats is a pure per-fit lapply; stage_model_stats
# overwrites model_id/model_label per id).
#
# Usage: Rscript scripts/build_stages_local.R <phase>
#   phase = inputs | crdc | diagnostics | model_stats | all   (default: all)

suppressMessages({
  library(targets)
  library(brms)      # ndraws/nchains generics + rstan (HMC diagnostics)
})
source("R/model_registry.R")
source("R/crdc_path.R")
source("R/stage_artifacts.R")
source("R/funs.R")   # calculate_model_stats()

DIR <- "export/stages"

build_inputs <- function() {
  message(">> inputs")
  out <- stage_inputs_artifacts(
    tar_read_raw("three_year_data"),
    tar_read_raw("recent_data"),
    tar_read_raw("combined_model_data"),
    tar_read_raw("combined_sch_data"),
    dir = DIR)
  message("wrote ", length(out), " input parquets")
}

build_crdc <- function() {
  message(">> crdc")
  nm <- c("full_crdc_data_y2122", "full_crdc_data_y1718", "full_crdc_data_y1516",
          "model_data_y2122", "model_data_y1718", "model_data_y1516",
          "popcounts_y2122", "popcounts_y1718", "popcounts_y1516",
          "schenrollraw_y2122", "schenrollraw_y1718", "schenrollraw_y1516",
          "lerefs_y2122", "lerefs_y1718", "lerefs_y1516",
          "ccd_sch_geo_y2122", "ccd_sch_geo_y1718", "ccd_sch_geo_y1516",
          "ccd_dist_geo_y2122", "ccd_dist_geo_y1718", "ccd_dist_geo_y1516")
  for (n in nm) {                       # read+write one at a time (low memory)
    x <- tar_read_raw(n)
    stage_crdc_artifacts(stats::setNames(list(x), n), dir = DIR)
    rm(x); gc(FALSE)
  }
  message("wrote ", length(nm), " crdc parquets")
}

build_diagnostics <- function() {
  message(">> diagnostics (hmc + unified qs2; 5 unified fits)")
  unified_ids <- crdc_unified_ids()
  fits <- lapply(unified_ids, tar_read_raw); names(fits) <- unified_ids
  stage_hmc_diagnostics(fits, dir = DIR)
  stage_unified_fits(fits, dir = DIR)
  rm(fits); gc(FALSE)
  message("wrote hmc_diagnostics.parquet + unified_m{1..5}.qs2")
}

build_model_stats <- function() {
  message(">> model_stats (per-branch, memory-safe)")
  m <- tar_meta()
  one <- function(fit, id) {
    s <- calculate_model_stats(fit, model_prefix = id)
    s$model_id    <- id
    s$model_label <- crdc_model_label(id)
    s
  }
  rows <- list()
  for (id in crdc_unified_ids()) {            # unified: single fits
    fit <- tar_read_raw(id)
    rows[[length(rows) + 1L]] <- one(fit, id)
    rm(fit); gc(FALSE)
    message("  ", id)
  }
  for (id in paste0("stratified_m", 1:5, "_mod")) {  # stratified: dynamic branches, one at a time
    ch <- m$children[[match(id, m$name)]]
    ch <- ch[!is.na(ch)]
    for (b in ch) {
      fit <- tar_read_raw(b)
      rows[[length(rows) + 1L]] <- one(fit, id)
      rm(fit); gc(FALSE)
    }
    message("  ", id, " (", length(ch), " branches)")
  }
  df <- do.call(rbind, rows)
  stage_write_parquet(df, file.path(DIR, "diagnostics/model_stats.parquet"))
  message("model_stats rows: ", nrow(df))
}

phase <- commandArgs(trailingOnly = TRUE)
phase <- if (length(phase)) phase[1] else "all"
switch(phase,
  inputs       = build_inputs(),
  crdc         = build_crdc(),
  diagnostics  = build_diagnostics(),
  model_stats  = build_model_stats(),
  all          = { build_inputs(); build_crdc(); build_diagnostics(); build_model_stats() },
  stop("unknown phase: ", phase))
