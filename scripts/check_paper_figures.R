#!/usr/bin/env Rscript
# Render the white paper's eight figures standalone and check them for the
# defects that a full `quarto render` would take minutes to surface:
#
#   * text running off the canvas (clipped titles, subtitles, captions)
#   * caption line spacing (the device/layout size mismatch between a figure's
#     requested size and the canvas it is drawn on). Needs the line_spacing()
#     helper from the file named by CV_FIGCHECK_HELPERS; without it that column
#     reads "skipped" and only the edge check runs.
#
# Exists because these figures are expensive to produce through the paper
# (~3 min per render) and the constants that control text fit -- str_wrap()
# budgets, theme font sizes -- need an iterate-and-measure loop.
#
# Usage:
#   CRDC_ARTIFACTS=export Rscript scripts/check_paper_figures.R [outdir]
#
# Writes PNGs at the same dimensions the .qmd chunks request, then reports a
# table. Nothing here writes into export/figures -- the paper owns that path.

suppressMessages({
  library(ggplot2); library(ggridges); library(patchwork)
  library(dplyr); library(tidyr); library(stringr); library(knitr)
  library(duckdb)
})
source("R/funs.R"); source("R/crdc_path.R")
source("R/model_registry.R"); source("R/paper_figures.R")

outdir <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(outdir)) outdir <- file.path(tempdir(), "figcheck")
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

cv_apply_branding()   # same entry point the paper uses: theme + showtext off + logo

h <- open_draws_view(); con <- h$con
on.exit(close_draws_view(h), add = TRUE)
rdata     <- read_stage_df("stages/inputs/recent_data.parquet")
crdc_2122 <- read_stage_df("stages/crdc/full_crdc_data_y2122.parquet")

# label -> (builder, width, height); mirrors the chunk options in white_paper.qmd.
FIGS <- list(
  list(label = "fig-national-rates", w = 10, h = 7,
       f = function() wp_fig_national_rates(crdc_2122)),
  list(label = "fig-paterson-intervals", w = 10, h = 10,
       f = function() wp_fig_district_intervals(con, rdata, "3412690",
             "Observed arrests are 0, frequentist interval given by the rule of 3.",
             title_wrap = 90, grid = TRUE)),
  list(label = "fig-paterson-distribution", w = 10, h = 10,
       f = function() wp_fig_zero_distribution(con, rdata, "3412690")),
  list(label = "fig-mobile-intervals", w = 10, h = 10,
       f = function() wp_fig_district_intervals(con, rdata, "0102370",
             "Frequentist interval shown in gray.", title_wrap = 120, grid = FALSE)),
  list(label = "fig-mobile-distribution", w = 10, h = 10,
       f = function() wp_fig_hpd_ridges(con, rdata, "0102370")),
  list(label = "fig-clark-density", w = 10, h = 10,
       f = function() wp_fig_group_density(con, rdata, "3200060")),
  list(label = "fig-clark-disparity", w = 12, h = 10,
       f = function() wp_fig_group_difference(con, rdata, "3200060")),
  list(label = "fig-state-differences", w = 12, h = 10,
       f = function() wp_fig_state_differences(con, rdata))
)

only <- commandArgs(trailingOnly = TRUE)[2]
if (!is.na(only)) FIGS <- Filter(function(x) grepl(only, x$label), FIGS)

paths <- character(0)
for (fig in FIGS) {
  message("rendering ", fig$label, " (", fig$w, "x", fig$h, ")")
  p <- fig$f()
  out <- file.path(outdir, paste0("whitepaper-", fig$label, "-1.png"))
  # dpi 192 matches the paper: knitr renders a 10in figure to 1920px.
  ragg::agg_png(out, width = fig$w, height = fig$h, units = "in", res = 192,
                background = "white")
  print(p); invisible(grDevices::dev.off())
  paths <- c(paths, out)
}

# --- checks ---------------------------------------------------------------
helpers <- Sys.getenv("CV_FIGCHECK_HELPERS")
has_spacing <- nzchar(helpers) && file.exists(helpers)
if (has_spacing) {
  source(helpers)
} else {
  message("CV_FIGCHECK_HELPERS not set; skipping the caption spacing check")
}

#' Extent (in px) that ink reaches past each edge of the canvas. The figures are
#' drawn on a white background here, so any ink within `band` px of an edge is
#' text or a mark that has run out of room.
edge_ink <- function(path, band = 4L) {
  im <- png::readPNG(path)
  d  <- pmax(abs(im[, , 1] - 1), abs(im[, , 2] - 1), abs(im[, , 3] - 1))
  ink <- d > 0.02
  H <- nrow(ink); W <- ncol(ink)
  c(top    = sum(ink[seq_len(band), ]),
    bottom = sum(ink[seq.int(H - band + 1, H), ]),
    left   = sum(ink[, seq_len(band)]),
    right  = sum(ink[, seq.int(W - band + 1, W)]))
}

cat("\n", strrep("-", 92), "\n", sep = "")
cat(sprintf("%-34s %-22s %s\n", "figure", "caption spacing", "ink touching edge (t/b/l/r)"))
cat(strrep("-", 92), "\n", sep = "")
bad <- FALSE
for (p in paths) {
  ls_ <- if (has_spacing) line_spacing(p, bg = "white") else NULL
  sp  <- if (!has_spacing) "  skipped" else if (is.null(ls_)) "  n/a" else
           sprintf("%.2f (%d lines)%s", ls_$ratio, ls_$n_lines,
                   if (ls_$ratio > 1.6) " !" else "")
  e <- edge_ink(p)
  flag <- any(e > 0)
  if (flag) bad <- TRUE
  cat(sprintf("%-34s %-22s %d/%d/%d/%d%s\n",
      sub("^whitepaper-", "", tools::file_path_sans_ext(basename(p))),
      sp, e[["top"]], e[["bottom"]], e[["left"]], e[["right"]],
      if (flag) "   <- CLIPPED" else ""))
}
cat(strrep("-", 92), "\n", sep = "")
cat("PNGs in: ", outdir, "\n", sep = "")
if (bad) cat("\nAt least one figure has ink at the canvas edge -- text is being cut off.\n")
