test_that("open_draws_view exposes predicted_draws as a view over partitioned parquet", {
  # synthetic draws shard mirroring the published schema: partition cols
  # (model_id, YEAR, LEA_STATE) come from the path; the rest are file columns.
  d  <- tempfile()
  pq <- file.path(d, "parquet/model_id=nat_m2_mod/YEAR=21-22/LEA_STATE=RI")
  dir.create(pq, recursive = TRUE)
  drv <- duckdb::duckdb(); con0 <- DBI::dbConnect(drv)
  DBI::dbExecute(con0, sprintf(
    "COPY (SELECT 's' subgroup_id, '1' LEAID, 'WH' RACE, 'M' SEX, 1 draw_id, 3 pred)
       TO '%s' (FORMAT parquet)", file.path(pq, "data_0.parquet")))
  DBI::dbDisconnect(con0, shutdown = TRUE); duckdb::duckdb_shutdown(drv)

  withr::with_envvar(c(CRDC_ARTIFACTS = d), {
    h <- open_draws_view()
    on.exit(close_draws_view(h))
    res <- get_prediction_summary(h$con, model = "nat_m2_mod")
    expect_equal(res$model_id, "nat_m2_mod")
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

test_that("with_model_labels adds a model_label column from the registry", {
  df  <- data.frame(model_id = c("nat_m2_mod", "sg_m1_mod"), stringsAsFactors = FALSE)
  out <- with_model_labels(df)
  expect_equal(out$model_label, c("Pooled (m2)", "Student-group (m1)"))
})
