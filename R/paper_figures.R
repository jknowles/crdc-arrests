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
  # Transparent backgrounds for every figure (paper_bg = FALSE drops the theme's
  # cream paper fill); font_size = 20 enlarges the patchwork plot_annotation text
  # (overall title / subtitle / caption) which the per-builder theme_ridges() does
  # NOT control. The transparent device canvas makes the theme_ridges panels (blank
  # background) render transparent rather than white.
  ggplot2::theme_set(civilytics::theme_civilytics(font_size = 20, paper_bg = FALSE))
  knitr::opts_chunk$set(dev = "ragg_png", dev.args = list(background = "transparent"))
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
    img    <- magick::image_read(path)
    info   <- magick::image_info(img)
    logo_h <- max(1L, round(info$height * height_frac))
    lg     <- magick::image_resize(magick::image_read(logo_file),
                magick::geometry_size_pixels(height = logo_h))
    if (grepl("^bottom", position)) {
      # Place the logo in a TRANSPARENT footer band BELOW the plot so it never
      # overlaps the axis text and the figure background stays transparent.
      band <- round(logo_h * 1.7)
      canvas <- magick::image_extent(img, magick::geometry_size_pixels(
        width = info$width, height = info$height + band), gravity = "north", color = "none")
      # operator = "over" (not magick's default "atop") so the logo draws onto the
      # TRANSPARENT band -- "atop" would clip it to the band's (empty) alpha.
      out  <- magick::image_composite(canvas, lg, operator = "over", gravity = grav,
                offset = sprintf("+18+%d", max(1L, round((band - logo_h) / 2))))
    } else {
      out  <- magick::image_composite(img, lg, operator = "over", gravity = grav,
                offset = "+18+14")
    }
    magick::image_write(out, path)
    path
  })
  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# White-paper figure builders (Subsystem 3).
#
# These reproduce the published paper's figures from the artifact draws view
# (open_draws_view()) + the staged input table `rdata`
# (read_stage_df("stages/inputs/recent_data.parquet")) and, where noted,
# `tydata` (three_year_data). They are the single source for white_paper.qmd;
# supplement.qmd keeps its own inline chunks (intentional — the supplement
# inlines its analysis for transparency). Each returns a ggplot/patchwork object.
#
# Internal helpers (model classification, palettes, Agresti-Coull) mirror
# supplement.qmd's inline copies so white_paper renders standalone.
# ---------------------------------------------------------------------------

#' Agresti-Coull approximate interval for a rare-event rate. Returns
#' c(ci_upper, ci_lower, sd, phat_se, phat) (matches supplement.qmd).
agresti_coull <- function(numerator, denominator, confidence_level = 0.95) {
  adj_star <- stats::qnorm(1 - (1 - confidence_level) / 2)
  if (numerator > 0) {
    num_star   <- numerator + adj_star
    denom_star <- denominator + (2 * adj_star)
    phat       <- num_star / denom_star
    phat_se    <- sqrt((phat / denom_star) * (1 - phat))
    ci_upper   <- (phat + (adj_star * phat_se)) * denom_star
    ci_lower   <- (phat - (adj_star * phat_se)) * denom_star
    sd         <- phat_se * denom_star
  } else {
    ci_upper <- denominator * (-log(1 - confidence_level) / denominator)
    ci_lower <- 0
    sd       <- mean(c(ci_upper, ci_lower)) / confidence_level
    phat_se  <- 0
    phat     <- mean(c(ci_upper, ci_lower))
  }
  c(ci_upper, ci_lower, sd, phat_se, phat)
}

# Model classification helpers (one-/three-year; unified/stratified; covariate).
add_model_time <- function(x) {
  y <- rep("One year", length(x))
  y[x %in% c("nat_m3_mod", "nat_m4_mod", "nat_m5_mod",
             "sg_m3_mod", "sg_m4_mod", "sg_m5_mod")] <- "Three year"
  y
}
add_model_form <- function(x) {
  y <- rep("Stratified", length(x)); y[startsWith(x, "nat")] <- "Unified"; y
}
add_model_cov <- function(x) {
  y <- rep("Baseline", length(x))
  y[x %in% c("sg_m2_mod", "nat_m4_mod", "nat_m5_mod",
             "nat_m2_mod", "sg_m4_mod", "sg_m5_mod")] <- "Covariate"
  y
}
print_model_name <- function(x, lbreak = FALSE) {
  y <- rep("Stratified", length(x)); y[startsWith(x, "nat")] <- "Unified"
  x <- gsub("_mod", "", x); x <- gsub("nat_m", "", x); x <- gsub("sg_m", "", x)
  if (lbreak) paste0(y, "\nModel:", x) else paste0(y, " Model:", x)
}
wp_model_palette <- function() c("Modeled" = "#000a9bff", "Frequentist" = "#858585bb")
wp_group_palette <- function() c("WH" = "#09d2ecc2", "BL" = "#ab00a9f1", "HI" = "#00ab17f1")

# Title helper: "District Name in State".
.wp_dist_name <- function(obsv_focal) {
  paste0(tools::toTitleCase(tolower(unique(obsv_focal$LEA_NAME))), " in ",
         state.name[state.abb == unique(obsv_focal$LEA_STATE)])
}

#' Figs 2 & 4: predicted-arrest 95% intervals vs the frequentist interval, for a
#' single district, faceted by covariate x time. `subtitle`, `title_wrap`, `grid`
#' differ between the zero-arrest (Fig 2) and many-arrest (Fig 4) cases.
wp_fig_district_intervals <- function(con, rdata, focal_dist, subtitle,
                                      title_wrap = 120, grid = FALSE) {
  obsv_focal <- dplyr::filter(rdata, LEAID == focal_dist)
  dist_name  <- .wp_dist_name(obsv_focal)
  dist_draws <- get_prediction_draws(con, YEAR = "21-22", LEAID = focal_dist)
  obsv_plot <- obsv_focal |> dplyr::ungroup() |>
    dplyr::summarize(arrests = sum(ARRESTS), enroll = sum(stu_enroll)) |>
    dplyr::mutate(ci_upper = agresti_coull(arrests, enroll, 0.95)[1],
                  ci_lower = agresti_coull(arrests, enroll, 0.95)[2],
                  type = "Frequentist")
  model_plot <- dist_draws |>
    dplyr::group_by(model_id, draw_id) |>
    dplyr::summarize(arrestst = sum(pred), .groups = "drop") |>
    dplyr::group_by(model_id) |>
    dplyr::summarize(arrests = stats::median(arrestst),
                     ci_upper = stats::quantile(arrestst, 1 - (1 - 0.95) / 2),
                     ci_lower = stats::quantile(arrestst, (1 - 0.95) / 2),
                     enroll = obsv_plot$enroll[1], .groups = "drop") |>
    dplyr::rename(type = model_id)
  plotdf <- dplyr::bind_rows(
    tidyr::crossing(obsv_plot, model_id = unique(model_plot$type)),
    dplyr::mutate(model_plot, model_id = type)) |>
    dplyr::mutate(type = ifelse(type == "Frequentist", type, "Modeled"))
  ggplot2::ggplot(plotdf, ggplot2::aes(x = model_id, y = arrests,
      ymin = ci_upper, ymax = ci_lower, color = type, group = type)) +
    ggplot2::geom_pointrange(position = ggplot2::position_dodge(width = 0.5)) +
    ggplot2::facet_wrap(add_model_cov(model_id) ~ add_model_time(model_id),
                        strip.position = "top", scales = "free_y") +
    ggplot2::scale_x_discrete("Model", limits = rev,
      labels = function(x) print_model_name(x, lbreak = TRUE)) +
    ggplot2::scale_color_manual(values = wp_model_palette(),
      guide = ggplot2::guide_legend(override.aes = list(linetype = c(0, 0)))) +
    ggplot2::coord_flip() +
    ggplot2::labs(title = stringr::str_wrap(
      paste0("Predicted arrests 95% interval for ", dist_name), title_wrap),
      y = "Predicted arrests", x = "Model type", color = "", subtitle = subtitle) +
    ggridges::theme_ridges(grid = grid, font_size = 24) +
    ggplot2::theme(legend.position = "bottom",
      axis.text.y = ggplot2::element_text(angle = 90, hjust = 0.25))
}

# One binline-ridge panel for the zero-arrest distribution figure.
.wp_zero_panel <- function(plot_draws, ndraws, cov, time, title, subtitle,
                           xbreaks, xlimits, xlab = "", ylab = "", ytitle = NULL) {
  d <- plot_draws |> dplyr::filter(!grepl("_m5", model_id)) |>
    dplyr::filter(add_model_cov(model_id) == cov) |>
    dplyr::filter(add_model_time(model_id) == time)
  yexp <- if (!is.null(ytitle)) ggplot2::expansion(add = c(0.25, 1.2)) else
          ggplot2::expansion(add = c(0.25, 1.1))
  ysc <- if (!is.null(ytitle))
    ggplot2::scale_y_discrete(labels = function(x) print_model_name(x, lbreak = TRUE),
                              expand = yexp, name = ytitle) else
    ggplot2::scale_y_discrete(labels = function(x) print_model_name(x, lbreak = TRUE),
                              expand = yexp)
  ggplot2::ggplot(d, ggplot2::aes(x = pred, y = model_id, group = model_id)) +
    ggridges::geom_density_ridges2(stat = "binline", scale = 0.9, binwidth = 1,
                                   color = "#000a9bff") +
    ggplot2::geom_text(stat = "bin", ggplot2::aes(
        y = group + (0.9 * ggplot2::after_stat(count / max(count))),
        label = ifelse(ggplot2::after_stat(count) > 25,
                       pretty_per(ggplot2::after_stat(count / ndraws)), "")),
      nudge_y = 0, vjust = -0.25, size = 6, color = "black", binwidth = 1) +
    ysc +
    ggplot2::scale_x_continuous(breaks = xbreaks, limits = xlimits,
      expand = ggplot2::expansion(add = c(0.25, 1), mult = c(0, 0.2))) +
    ggridges::theme_ridges(grid = FALSE, font_size = 24) +
    ggplot2::labs(title = title, subtitle = subtitle, x = xlab, y = ylab) +
    ggplot2::theme(axis.text.y = ggplot2::element_text(angle = 90, hjust = -0.5))
}

#' Fig 3: distribution of predicted arrests across models for a zero-arrest
#' district (Paterson), four binline-ridge panels (cov x time), top-coded at 16.
wp_fig_zero_distribution <- function(con, rdata, focal_dist) {
  obsv_focal <- dplyr::filter(rdata, LEAID == focal_dist)
  dist_name  <- .wp_dist_name(obsv_focal)
  dist_draws <- get_prediction_draws(con, YEAR = "21-22", LEAID = focal_dist)
  ndraws <- 500
  plot_draws <- dist_draws |> dplyr::group_by(model_id, draw_id) |>
    dplyr::summarize(pred = sum(pred), .groups = "drop") |>
    dplyr::mutate(pred = ifelse(pred > 16, 16, pred))
  p1 <- .wp_zero_panel(plot_draws, ndraws, "Baseline", "Three year",
    "Three year models", "Baseline", 5:16, c(4, 17))
  p2 <- .wp_zero_panel(plot_draws, ndraws, "Baseline", "One year",
    "One year models", "Baseline", 0:8, c(-0.5, 8), ylab = "Model type",
    ytitle = "Model type")
  p3 <- .wp_zero_panel(plot_draws, ndraws, "Covariate", "Three year",
    "Three year models", "Covariates", 0:12, c(-0.5, 13), xlab = "Predicted Arrests")
  p4 <- .wp_zero_panel(plot_draws, ndraws, "Covariate", "One year",
    "One year models", "Covariates", 0:8, c(-0.5, 8), xlab = "Predicted Arrests")
  p2 + p1 + p4 + p3 + patchwork::plot_annotation(
    title = paste0("All model draws for ", dist_name),
    caption = paste0("Observed arrests in 2021-22 are 0.\n",
      "Arrests are top-coded at 16 or more for visual clarity.\n",
      "Values with fewer than 5% predicted likelihood are not labeled."),
    subtitle = "Frequency of predicted arrests from 500 draws of posterior for each model",
    theme = ggplot2::theme(plot.caption = ggplot2::element_text(size = 18, hjust = 0,
                                                                lineheight = 0.9)))
}

#' Fig 5: predicted-arrest probability-density intervals with the 95% highest
#' posterior density region shaded, vs the frequentist interval (Mobile County).
wp_fig_hpd_ridges <- function(con, rdata, focal_dist) {
  obsv_focal <- dplyr::filter(rdata, LEAID == focal_dist)
  dist_name  <- .wp_dist_name(obsv_focal)
  dist_draws <- get_prediction_draws(con, YEAR = "21-22", LEAID = focal_dist)
  obsv_plot <- obsv_focal |> dplyr::ungroup() |>
    dplyr::summarize(arrests = sum(ARRESTS), enroll = sum(stu_enroll)) |>
    dplyr::mutate(ci_upper = agresti_coull(arrests, enroll, 0.95)[1],
                  ci_lower = agresti_coull(arrests, enroll, 0.95)[2], type = "Frequentist")
  result <- dist_draws |> dplyr::filter(!grepl("_m5", model_id)) |>
    dplyr::group_by(model_id, draw_id) |>
    dplyr::summarize(pred = sum(pred), .groups = "drop") |>
    dplyr::group_by(model_id) |>
    dplyr::mutate(rank = rank(-pred, ties.method = "min")) |>
    dplyr::ungroup()
  model_ids <- unique(result$model_id)
  lower_hpd_vec <- numeric(nrow(result)); upper_hpd_vec <- numeric(nrow(result))
  within_hpd_vec <- logical(nrow(result))
  for (cm in model_ids) {                          # narrowest 95% window per model
    rows <- which(result$model_id == cm)
    sp <- sort(result$pred[rows]); n <- length(sp)
    w <- ceiling(0.95 * n)
    widths <- vapply(seq_len(n - w + 1), function(j) sp[j + w - 1] - sp[j], numeric(1))
    k <- which.min(widths)
    lo <- sp[k]; hi <- sp[k + w - 1]
    lower_hpd_vec[rows] <- lo; upper_hpd_vec[rows] <- hi
    within_hpd_vec[rows] <- result$pred[rows] >= lo & result$pred[rows] <= hi
  }
  result$lower_hpd <- lower_hpd_vec; result$upper_hpd <- upper_hpd_vec
  result$within_hpd <- within_hpd_vec
  ggplot2::ggplot(result, ggplot2::aes(x = pred, y = model_id, group = model_id)) +
    ggridges::geom_density_ridges(scale = 0.95, rel_min_height = 0.01) +
    ggridges::geom_density_ridges_gradient(data = dplyr::filter(result, within_hpd),
      ggplot2::aes(fill = ggplot2::after_stat(x)), scale = 0.95,
      gradient_lwd = 1.0, rel_min_height = 0.01) +
    ggplot2::geom_pointrange(data = tidyr::crossing(obsv_plot,
        model_id = unique(result$model_id)),
      ggplot2::aes(y = model_id, x = arrests, xmin = ci_lower, fill = NULL,
                   xmax = ci_upper), color = I("#5a0052ff"),
      position = ggplot2::position_nudge(y = 0.15)) +
    ggplot2::scale_fill_viridis_c(name = "Arrests", option = "C",
                                  guide = ggplot2::guide_none()) +
    ggplot2::scale_y_discrete("Model", limits = rev,
      labels = function(x) print_model_name(x, lbreak = TRUE),
      expand = ggplot2::expansion(mult = c(0.1, 0.15))) +
    ggplot2::facet_wrap(add_model_cov(model_id) ~ add_model_time(model_id),
                        strip.position = "top", scales = "free_y") +
    ggplot2::labs(title = stringr::str_wrap(
      paste0("Predicted arrests probability density interval for ", dist_name), 120),
      x = "Predicted arrests", y = "Model type",
      subtitle = stringr::str_wrap(paste0("Frequentist rate and interval shown in ",
        "purple. Colored fill represents the 95% highest posterior density for ",
        "each model, shaded to emphasize number of arrests."), 70)) +
    ggridges::theme_ridges(grid = FALSE, font_size = 24) +
    ggplot2::theme(legend.position = "bottom",
      panel.grid.major.y = ggplot2::element_line(color = "gray50"),
      axis.text.y = ggplot2::element_text(angle = 90, hjust = -0.5))
}

# Shared Clark-County group data (Figs 6 & 7): male BL/WH/HI draws + observed.
.wp_group_data <- function(con, rdata, focal_dist) {
  obsv_focal <- dplyr::filter(rdata, LEAID == focal_dist)
  dist_name  <- .wp_dist_name(obsv_focal)
  dist_draws <- get_prediction_draws(con, YEAR = "21-22", LEAID = focal_dist)
  obsv_plot <- obsv_focal |> dplyr::ungroup() |>
    dplyr::filter(SEX == "M", RACE %in% c("BL", "WH", "HI")) |>
    dplyr::group_by(RACE) |>
    dplyr::summarize(arrests = sum(ARRESTS), enroll = sum(stu_enroll), .groups = "drop") |>
    dplyr::rowwise() |>
    dplyr::mutate(ci_upper = agresti_coull(arrests, enroll, 0.95)[1],
                  ci_lower = agresti_coull(arrests, enroll, 0.95)[2], type = "observed") |>
    dplyr::ungroup()
  plot_draws <- dist_draws |> dplyr::filter(!grepl("_m5", model_id)) |>
    dplyr::filter(SEX == "M", RACE %in% c("BL", "WH", "HI")) |>
    dplyr::mutate(enroll = dplyr::case_when(
      RACE == "BL" ~ obsv_plot$enroll[obsv_plot$RACE == "BL"],
      RACE == "HI" ~ obsv_plot$enroll[obsv_plot$RACE == "HI"],
      TRUE         ~ obsv_plot$enroll[obsv_plot$RACE == "WH"]))
  list(plot_draws = plot_draws, obsv_plot = obsv_plot, dist_name = dist_name)
}

# One race-density-ridge panel (used by Figs 6 & 7).
.wp_group_density_plot <- function(plot_draws, obsv_plot, dist_name, subtitle,
                                   races = c("BL", "WH", "HI"), title_wrap = 120,
                                   font_size = 24) {
  g <- ggplot2::ggplot(dplyr::filter(plot_draws, RACE %in% races),
      ggplot2::aes(x = (pred / (enroll / 1000)), color = RACE, fill = RACE, y = model_id)) +
    ggridges::geom_density_ridges(scale = 0.9, rel_min_height = 0.01, alpha = 1/5,
                                  bandwidth = 0.1)
  for (r in races) {
    ny <- switch(r, HI = 0.25, BL = 0.35, WH = 0.15)
    g <- g + ggplot2::geom_pointrange(
      data = tidyr::crossing(dplyr::filter(obsv_plot, RACE == r),
                             model_id = unique(plot_draws$model_id)),
      ggplot2::aes(y = model_id, x = (arrests / (enroll / 1000)),
        xmin = ci_lower / (enroll / 1000), xmax = ci_upper / (enroll / 1000), color = RACE),
      show.legend = FALSE, position = ggplot2::position_nudge(y = ny))
  }
  g +
    ggplot2::scale_y_discrete(labels = function(x) print_model_name(x, lbreak = TRUE),
                              expand = ggplot2::expansion(c(0, 0))) +
    ggplot2::facet_wrap(add_model_cov(model_id) ~ add_model_time(model_id),
                        strip.position = "top", scales = "free_y") +
    ggplot2::guides(color = ggplot2::guide_none()) +
    ggplot2::scale_color_manual(values = wp_group_palette(),
                                labels = function(x) crdc_race_recode(x)) +
    ggplot2::scale_fill_manual(values = wp_group_palette(),
                               labels = function(x) crdc_race_recode(x)) +
    ggplot2::labs(title = stringr::str_wrap(
      paste0("Arrest rate probability density for ", dist_name), title_wrap),
      x = "Arrest rate per 1,000", y = "", fill = "Student race:", subtitle = subtitle) +
    ggplot2::coord_cartesian(clip = "off") +
    ggridges::theme_ridges(grid = FALSE, font_size = font_size) +
    ggplot2::theme(legend.position = "bottom",
      axis.text.y = ggplot2::element_text(angle = 90, hjust = -0.5))
}

#' Fig 6: arrest-rate posterior density by race (male BL/WH/HI) for one district
#' (Clark County NV) vs the frequentist point interval.
wp_fig_group_density <- function(con, rdata, focal_dist) {
  d <- .wp_group_data(con, rdata, focal_dist)
  .wp_group_density_plot(d$plot_draws, d$obsv_plot, d$dist_name,
    subtitle = "Male students. Frequentist interval shown as point range.")
}

#' Fig 7: Hispanic-White male arrest-rate disparity (Clark County NV): the
#' WH/HI densities (top) over the model-estimated difference distribution (bottom).
wp_fig_group_difference <- function(con, rdata, focal_dist) {
  d <- .wp_group_data(con, rdata, focal_dist)
  plot_draws <- dplyr::filter(d$plot_draws, !grepl("_m5", model_id))
  diff_b <- plot_draws |> dplyr::group_by(model_id, draw_id) |>
    dplyr::summarize(group_h = pred[RACE == "HI"] / enroll[RACE == "HI"],
                     group_w = pred[RACE == "WH"] / enroll[RACE == "WH"],
                     .groups = "drop") |>
    dplyr::mutate(diffv = group_h - group_w)
  annotate_df <- diff_b |> dplyr::group_by(model_id) |>
    dplyr::summarize(total = dplyr::n(), diffcount = sum(diffv > 0), diffv = 1,
                     .groups = "drop") |>
    dplyr::mutate(diff_per = diffcount / total)
  p1 <- ggplot2::ggplot(diff_b, ggplot2::aes(x = (diffv * 1000), y = model_id,
      fill = ggplot2::after_stat(x))) +
    ggridges::geom_density_ridges_gradient(from = -0.5, to = 1.5, scale = 1.5,
      alpha = 4/5, bandwidth = 0.05) +
    ggplot2::scale_fill_distiller(name = "Diff.", direction = 1, palette = "YlOrRd",
      guide = ggplot2::guide_none()) +
    ggplot2::geom_vline(xintercept = 0, linetype = 3, color = I("red"), linewidth = 2) +
    ggplot2::geom_text(data = annotate_df, size = 4.5,
      position = ggplot2::position_nudge(y = 0.4, x = 0),
      ggplot2::aes(y = model_id, x = diffv,
        label = paste0("Pr(", "Δ", "> 0): ", pretty_per(diff_per)))) +
    ggplot2::coord_cartesian(clip = "off") +
    ggridges::theme_ridges(grid = FALSE, font_size = 20) +
    ggplot2::labs(x = "Arrest rate per 1,000", title = stringr::str_wrap(
      paste0("Model estimated difference (", "Δ",
        ") between Hispanic and White student arrest rates in ", d$dist_name), 90),
      subtitle = "No difference shown as red vertical line.", y = "") +
    ggplot2::scale_y_discrete(labels = function(x) print_model_name(x, lbreak = TRUE),
                              expand = ggplot2::expansion(c(0, 0))) +
    ggplot2::facet_wrap(add_model_cov(model_id) ~ add_model_time(model_id),
                        strip.position = "top", scales = "free_y") +
    ggplot2::theme(legend.position = "bottom",
      axis.text.y = ggplot2::element_text(angle = 90, hjust = 0.25))
  p2 <- .wp_group_density_plot(plot_draws, d$obsv_plot, d$dist_name,
    subtitle = "Male students only. Frequentist interval shown by point interval.",
    races = c("WH", "HI"), title_wrap = 90, font_size = 20)
  p2 / p1
}

# Shared 4-group state data for Fig 8 + Table 1 (AK/CO, Black/Amer.Ind, M/F).
# keep_ids = the four groups the paper highlights from Table 1.
.wp_state_group_data <- function(con, rdata) {
  draws <- get_state_prediction_draws(con, LEA_STATE = c("AK", "CO"), YEAR = "21-22",
    model = c("nat_m1_mod", "nat_m2_mod", "nat_m3_mod", "nat_m4_mod",
              "sg_m1_mod", "sg_m2_mod", "sg_m3_mod", "sg_m4_mod"),
    RACE = c("BL", "AM"), SEX = c("M", "F"))
  obsv <- rdata |> dplyr::filter(LEA_STATE %in% c("AK", "CO")) |>
    dplyr::group_by(LEA_STATE, YEAR, RACE, SEX) |>
    dplyr::summarize(arrests = sum(ARRESTS), enroll = sum(stu_enroll), .groups = "drop") |>
    dplyr::rowwise() |>
    dplyr::mutate(ci_upper = agresti_coull(arrests, enroll, 0.95)[1],
                  ci_lower = agresti_coull(arrests, enroll, 0.95)[2], type = "observed") |>
    dplyr::ungroup()
  plot_draws <- dplyr::inner_join(draws,
      dplyr::select(obsv, LEA_STATE, RACE, SEX, YEAR, arrests, enroll),
      by = c("LEA_STATE", "RACE", "SEX", "YEAR")) |>
    dplyr::mutate(arr_rate = 1000 * fitted_value / enroll)
  obsv <- obsv |> dplyr::filter(RACE %in% c("BL", "AM")) |>
    dplyr::mutate(arr_rate = 1000 * arrests / enroll,
                  rowid = paste(LEA_STATE, RACE, SEX, sep = "-"))
  plot_draws$rowid <- paste(plot_draws$LEA_STATE, plot_draws$RACE, plot_draws$SEX, sep = "-")
  list(plot_draws = plot_draws, obsv = obsv,
       keep_ids = c("AK-BL-M", "AK-BL-F", "AK-AM-M", "CO-AM-M"))
}

.wp_parse_state_row <- function(x) {
  y <- x
  y[x == "AK-BL-M"] <- "AK Black \nMale"
  y[x == "AK-BL-F"] <- "AK Black \nFemale"
  y[x == "AK-AM-M"] <- "AK Amer. Indian \nAlaska Native Male"
  y[x == "CO-AM-M"] <- "CO Amer. Indian \nAlaska Native Male"
  y
}

#' Fig 8: reevaluating Table 1's four state demographic groups with the models.
#' Top: modeled density + frequentist interval for each group (unified m3,
#' stratified m2). Bottom: model-estimated differences (CO vs AK Amer.Ind;
#' Black vs Amer.Ind within AK).
wp_fig_state_differences <- function(con, rdata) {
  d <- .wp_state_group_data(con, rdata)
  pd <- d$plot_draws; obsv <- d$obsv; keep_ids <- d$keep_ids
  two <- c("nat_m3_mod", "sg_m2_mod")
  p1 <- ggplot2::ggplot(pd |> dplyr::filter(rowid %in% keep_ids, model_id %in% two),
      ggplot2::aes(x = fitted_value / (enroll / 1000), y = rowid, fill = model_id)) +
    ggridges::geom_density_ridges(scale = 1, from = 0, to = 9, rel_min_height = 0.01,
                                  alpha = 3/5, bandwidth = 0.4) +
    ggplot2::geom_pointrange(data = dplyr::filter(obsv, rowid %in% keep_ids),
      ggplot2::aes(y = rowid, x = arr_rate, fill = NULL,
        xmin = 1000 * ci_lower / enroll, xmax = 1000 * ci_upper / enroll),
      show.legend = FALSE, position = ggplot2::position_nudge(y = 0.35)) +
    ggplot2::scale_y_discrete(expand = ggplot2::expansion(0, 0),
      labels = function(x) .wp_parse_state_row(x)) +
    ggplot2::scale_fill_manual(values = c("#d55c00a9", "#0071b2c5"),
      labels = function(x) print_model_name(x, lbreak = FALSE)) +
    ggplot2::coord_cartesian(clip = "off") +
    ggridges::theme_ridges(grid = FALSE, font_size = 20) +
    ggplot2::labs(x = "Arrests per 1,000", y = "", fill = "Model",
      title = "Bayesian modeled arrest rate predictions for selected state demographic groups") +
    ggplot2::theme(legend.position = "bottom",
      axis.text.y = ggplot2::element_text(angle = 90, hjust = 0.5))
  diff_panel <- function(ids, label_a, label_b, ann_x, ann_label, ttl, sub = NULL,
                         from = -1.25, to = NULL) {
    da <- pd |> dplyr::filter(rowid %in% ids, model_id %in% two) |>
      dplyr::ungroup() |>
      dplyr::select(model_id, draw_id, rowid, fitted_value, enroll) |>
      dplyr::group_by(model_id, draw_id) |>
      dplyr::summarize(ga = fitted_value[rowid == label_a] / enroll[rowid == label_a],
                       gb = fitted_value[rowid == label_b] / enroll[rowid == label_b],
                       .groups = "drop") |>
      dplyr::mutate(diffv = ga - gb)
    ann <- da |> dplyr::group_by(model_id) |>
      dplyr::summarize(total = dplyr::n(), diffcount = sum(diffv > 0), diffv = ann_x,
                       .groups = "drop") |>
      dplyr::mutate(diff_per = diffcount / total)
    g <- ggplot2::ggplot(da, ggplot2::aes(x = (diffv * 1000), y = model_id,
        fill = ggplot2::after_stat(x))) +
      (if (is.null(to))
         ggridges::geom_density_ridges_gradient(from = from, alpha = 4/5,
           rel_min_height = 0.02, bandwidth = 0.2) else
         ggridges::geom_density_ridges_gradient(from = from, to = to, alpha = 4/5,
           rel_min_height = 0.02, bandwidth = 0.2)) +
      ggplot2::scale_fill_distiller(name = "Diff.", direction = 1, palette = "YlOrRd",
        guide = ggplot2::guide_none()) +
      ggplot2::geom_vline(xintercept = 0, linetype = 3, color = I("red"), linewidth = 2) +
      ggplot2::geom_text(data = ann, size = 7.5,
        position = ggplot2::position_nudge(y = 0.5, x = 0),
        ggplot2::aes(y = model_id, x = diffv,
          label = paste0(ann_label, "\n", pretty_per(diff_per)))) +
      ggplot2::coord_cartesian(clip = "off") +
      ggridges::theme_ridges(grid = FALSE, font_size = 20) +
      ggplot2::labs(x = "Arrest rate per 1,000", y = "",
        title = stringr::str_wrap(ttl, 55), subtitle = sub) +
      ggplot2::scale_y_discrete(labels = function(x) print_model_name(x, lbreak = TRUE),
        expand = ggplot2::expansion(c(0, 0))) +
      ggplot2::theme(legend.position = "bottom",
        axis.text.y = ggplot2::element_text(angle = 90, hjust = -0.5))
    g
  }
  p2 <- diff_panel(c("AK-AM-M", "CO-AM-M"), "CO-AM-M", "AK-AM-M", 2, "Pr(CO > AK):",
    "Difference between Colorado and Alaska American Indian / Alaska Native Male Arrest Rates",
    sub = "No difference shown as red vertical line.", to = 4)
  p3 <- diff_panel(c("AK-AM-M", "AK-BL-M"), "AK-AM-M", "AK-BL-M", 1.25,
    "Pr( Amer. Ind > Black):",
    "Difference between Black and American Indian / Alaska Native male students within Alaska")
  p1 / (p2 + p3)
}

#' Table 1: frequentist Agresti-Coull arrest rates per 1,000 for the four
#' highlighted state demographic groups (the rare-event illustration).
wp_table_state_rates <- function(con, rdata) {
  d <- .wp_state_group_data(con, rdata)
  d$obsv |> dplyr::filter(rowid %in% d$keep_ids) |>
    dplyr::transmute(
      Observation = gsub("\n", "", .wp_parse_state_row(rowid)),
      Arrests = round(arrests),
      Enrollment = round(enroll),
      `Rate per 1,000` = round(1000 * arrests / enroll, 2),
      `95% interval (per 1,000)` = paste0(
        round(1000 * ci_lower / enroll, 2), " -- ", round(1000 * ci_upper / enroll, 2))) |>
    dplyr::arrange(`Rate per 1,000`)
}

#' Table A1: model computation times. Runtime / Data rows / Parameters are
#' aggregated from the model_stats artifact (summed across the 8 stratified
#' subsets); "Iterations per chain" is a fitting-time input not recorded in the
#' artifact, so the original reported values are kept.
wp_table_computation <- function(model_stats) {
  iters <- c("Unified 1" = "3,500", "Unified 2" = "3,500", "Unified 3" = "3,500",
             "Unified 4" = "4,000", "Unified 5" = "4,000",
             "Stratified 1" = "2,000 (x 8 models)", "Stratified 2" = "3,500 (x 8 models)",
             "Stratified 3" = "3,500 (x 8 models)", "Stratified 4" = "4,300 (x 8 models)",
             "Stratified 5" = "4,000 (x 8 models)")
  ms <- model_stats |>
    dplyr::mutate(
      form = add_model_form(model_id),
      spec = as.integer(sub("^(nat|sg)_m([0-9]+)_mod$", "\\2", model_id)),
      Models = paste(form, spec)) |>
    dplyr::group_by(Models, form, spec) |>
    dplyr::summarize(`Runtime in minutes` = round(sum(runtime_minutes), 1),
                     `Data rows` = sum(data_rows),
                     `Parameters` = sum(parameters), .groups = "drop") |>
    dplyr::arrange(dplyr::desc(form == "Unified"), spec) |>
    dplyr::mutate(`Iterations per chain` = unname(iters[Models])) |>
    dplyr::select(Models, `Runtime in minutes`, `Data rows`, `Parameters`,
                  `Iterations per chain`)
  ms
}

#' Fig 1: 2021-22 national arrest rates per 1,000 by race x sex student group,
#' built from the staged full CRDC data (stages/crdc/full_crdc_data_y2122).
wp_fig_national_rates <- function(crdc_y2122) {
  rates <- crdc_y2122 |>
    dplyr::filter(RACE %in% c("AM", "WH", "HI", "BL"), SEX %in% c("M", "F")) |>
    dplyr::group_by(RACE, SEX) |>
    dplyr::summarize(arrests = sum(ARRESTS, na.rm = TRUE),
                     enroll = sum(stu_enroll, na.rm = TRUE), .groups = "drop") |>
    dplyr::filter(enroll > 0) |>
    dplyr::mutate(arrest_rate = arrests / (enroll / 1000),
                  group = paste0(crdc_race_recode(RACE), " ",
                                 ifelse(SEX == "M", "male", "female")))
  ggplot2::ggplot(rates, ggplot2::aes(x = stats::reorder(group, arrest_rate),
      y = arrest_rate, fill = SEX)) +
    ggplot2::geom_col() +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(values = c("M" = "#000a9bff", "F" = "#00ab17f1"),
      labels = c("M" = "Male", "F" = "Female")) +
    ggplot2::labs(title = "National arrest rates by select student groups, 2021-22",
      x = "", y = "Arrests per 1,000 students", fill = "Sex") +
    ggridges::theme_ridges(grid = TRUE, font_size = 22) +
    ggplot2::theme(legend.position = "bottom")
}
