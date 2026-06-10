test_that("stage_write_parquet writes a readable parquet round-trip", {
  d <- tempfile(); dir.create(d)
  df <- data.frame(a = 1:3, b = letters[1:3], stringsAsFactors = FALSE)
  p  <- stage_write_parquet(df, file.path(d, "sub/x.parquet"))
  expect_true(file.exists(p))
  drv <- duckdb::duckdb(); con <- DBI::dbConnect(drv)
  on.exit({DBI::dbDisconnect(con, shutdown = TRUE); duckdb::duckdb_shutdown(drv)})
  back <- DBI::dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s') ORDER BY a", p))
  expect_equal(back$a, 1:3); expect_equal(back$b, letters[1:3])
})

test_that("stage_inputs_artifacts writes the 4 input parquets and returns paths", {
  d <- tempfile()
  ty  <- list(data = data.frame(LEAID = "1", ARRESTS = 2))
  rd  <- list(data = data.frame(LEAID = "1", ARRESTS = 1))
  cmd <- data.frame(LEAID = "1", YEAR = "21-22")
  csd <- data.frame(LEAID = "1", name = "x")
  out <- stage_inputs_artifacts(ty, rd, cmd, csd, dir = d)
  expect_setequal(basename(out),
    c("three_year_data.parquet", "recent_data.parquet",
      "combined_model_data.parquet", "combined_sch_data.parquet"))
  expect_true(all(file.exists(out)))
})

test_that("stage_crdc_artifacts writes one parquet per named element", {
  d <- tempfile()
  named <- list(full_crdc_data_y2122 = data.frame(x = 1),
                model_data_y2122     = data.frame(y = 2))
  out <- stage_crdc_artifacts(named, dir = d)
  expect_setequal(basename(out),
                  c("full_crdc_data_y2122.parquet", "model_data_y2122.parquet"))
  expect_true(all(file.exists(out)))
})

test_that("stage_model_stats binds per-model stats with registry labels", {
  d <- tempfile()
  fake <- function(models, model_prefix = NULL) data.frame(term = "b", est = 1.0)
  ids <- c("unified_m2_mod", "stratified_m4_mod")
  models <- stats::setNames(list("FIT_A", "FIT_B"), ids)
  p <- stage_model_stats(models, dir = d, stats_fn = fake)
  drv <- duckdb::duckdb(); con <- DBI::dbConnect(drv)
  on.exit({DBI::dbDisconnect(con, shutdown = TRUE); duckdb::duckdb_shutdown(drv)})
  res <- DBI::dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", p))
  expect_setequal(res$model_id, ids)
  expect_setequal(res$model_label, c("Unified (m2)", "Stratified (m4)"))
})

test_that("stage_unified_fits writes one qs2 per unified model, round-trips", {
  d <- tempfile()
  fits <- list(unified_m1_mod = list(tag = "A"), unified_m2_mod = list(tag = "B"))
  out  <- stage_unified_fits(fits, dir = d)
  expect_setequal(basename(out), c("unified_m1.qs2", "unified_m2.qs2"))
  expect_equal(qs2::qs_read(out[grepl("unified_m1", out)])$tag, "A")
})

test_that("stage_write_parquet sanitizes non-UTF8 (Windows-1252) strings", {
  d <- tempfile(); dir.create(d)
  df <- data.frame(
    name = c("Opportunities for Learning \x96 Duarte", "plain ascii"),
    stringsAsFactors = FALSE)
  expect_false(all(validUTF8(df$name)))             # input has invalid UTF8
  p <- stage_write_parquet(df, file.path(d, "u.parquet"))
  drv <- duckdb::duckdb(); con <- DBI::dbConnect(drv)
  on.exit({DBI::dbDisconnect(con, shutdown = TRUE); duckdb::duckdb_shutdown(drv)})
  back <- DBI::dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s') ORDER BY name", p))
  expect_true(all(validUTF8(back$name)))            # round-trips as valid UTF8
  expect_true(any(grepl("Duarte", back$name)))      # content preserved
})
