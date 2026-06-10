test_that("open_draws_view exposes predicted_draws as a view over partitioned parquet", {
  # synthetic draws shard mirroring the published schema: partition cols
  # (model_id, YEAR, LEA_STATE) come from the path; the rest are file columns.
  d  <- tempfile()
  pq <- file.path(d, "parquet/model_id=unified_m2_mod/YEAR=21-22/LEA_STATE=RI")
  dir.create(pq, recursive = TRUE)
  drv <- duckdb::duckdb(); con0 <- DBI::dbConnect(drv)
  DBI::dbExecute(con0, sprintf(
    "COPY (SELECT 's' subgroup_id, '1' LEAID, 'WH' RACE, 'M' SEX, 1 draw_id, 3 pred)
       TO '%s' (FORMAT parquet)", file.path(pq, "data_0.parquet")))
  DBI::dbDisconnect(con0, shutdown = TRUE); duckdb::duckdb_shutdown(drv)

  withr::with_envvar(c(CRDC_ARTIFACTS = d), {
    h <- open_draws_view()
    on.exit(close_draws_view(h))
    res <- get_prediction_summary(h$con, model = "unified_m2_mod")
    expect_equal(res$model_id, "unified_m2_mod")
    expect_true("fitted_value" %in% names(res))
  })
})

test_that("read_stage_df reads a tabular stage artifact via crdc_path", {
  d <- tempfile()
  withr::with_envvar(c(CRDC_ARTIFACTS = d), {
    p <- file.path(crdc_path("stages/inputs/recent_data.parquet"))
    dir.create(dirname(p), recursive = TRUE)
    stage_write_parquet(data.frame(LEAID = c("1", "2"), n = c(10L, 20L)), p)
    out <- read_stage_df("stages/inputs/recent_data.parquet")
    expect_equal(nrow(out), 2L)
    expect_setequal(out$LEAID, c("1", "2"))
  })
})

test_that("crdc_cached_path returns local path if present, NA otherwise, never downloads", {
  d <- tempfile(); dir.create(d)
  withr::with_envvar(c(CRDC_ARTIFACTS = d), {
    expect_true(is.na(crdc_cached_path("stages/models/unified_m2.qs2")))   # absent
    p <- file.path(d, "stages/models/unified_m2.qs2"); dir.create(dirname(p), recursive = TRUE)
    writeLines("x", p)
    expect_equal(crdc_cached_path("stages/models/unified_m2.qs2"), p)      # present
  })
  # remote base, nothing cached -> NA (and no network touched)
  withr::with_envvar(c(CRDC_ARTIFACTS = "hf://datasets/x/y@z",
                       CRDC_CACHE = tempfile()), {
    expect_true(is.na(crdc_cached_path("stages/models/unified_m2.qs2")))
  })
})

test_that("with_model_labels adds a model_label column from the registry", {
  df  <- data.frame(model_id = c("unified_m2_mod", "stratified_m1_mod"), stringsAsFactors = FALSE)
  out <- with_model_labels(df)
  expect_equal(out$model_label, c("Unified (m2)", "Stratified (m1)"))
})

test_that("cv_apply_branding sets the civilytics theme; logo hook gated on magick", {
  old <- ggplot2::theme_get(); on.exit(ggplot2::theme_set(old), add = TRUE)
  # logo = FALSE: applies theme, installs no hook, returns FALSE
  expect_false(cv_apply_branding(logo = FALSE))
  fam <- ggplot2::theme_get()$text$family
  expect_true(!is.null(fam) && nzchar(fam))   # a custom (civilytics) theme is active

  if (requireNamespace("magick", quietly = TRUE)) {
    expect_true(cv_apply_branding(logo = TRUE))                 # hook installed
    knitr::opts_chunk$set(fig.process = NULL)                  # clean up global hook
  } else {
    expect_message(res <- cv_apply_branding(logo = TRUE), "magick not installed")
    expect_false(res)
  }
})
