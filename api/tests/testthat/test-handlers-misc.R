test_that("handle_districts searches by name and state", {
  con <- api_connect(TEST_API_DB); on.exit(api_disconnect(con))
  res <- handle_districts(con, q="Alpha", state=NULL, limit="10", offset="0")
  expect_equal(res$data[[1]]$leaid, "0100005")
  expect_equal(res$data[[1]]$lea_name, "Alpha SD")
})

test_that("handle_models lists all 10 with a default flag", {
  res <- handle_models()
  ids <- vapply(res$data, function(m) m$model_id, character(1))
  expect_length(ids, 10)
  defaults <- Filter(function(m) isTRUE(m$is_default), res$data)
  expect_true("unified_m2_mod" %in% vapply(defaults, function(m) m$model_id, character(1)))
})

test_that("handle_draws returns HF shard url + duckdb snippet, not draws", {
  res <- handle_draws(state="AL", race="BL", sex="M", year="21-22", model="unified_m2")
  # hf:// protocol (DuckDB can glob it; https resolve URLs reject globs) +
  # full model_id/YEAR/LEA_STATE partition depth, in order
  expect_match(res$data$parquet_url, "^hf://datasets/civilytics/crdc-school-arrest-rates/parquet")
  expect_match(res$data$parquet_url, "model_id=unified_m2_mod/YEAR=21-22/LEA_STATE=AL/[*][.]parquet$")
  expect_match(res$data$duckdb_sql, "read_parquet")
})

test_that("handle_draws rejects invalid state with api_bad_request", {
  expect_error(
    handle_draws(state="ZZ", race="BL", sex="M", year="21-22", model="unified_m2"),
    class = "api_bad_request"
  )
})

test_that("handle_draws keeps partition depth with wildcards when year/state omitted", {
  res <- handle_draws(state=NULL, race="BL", sex="M", year=NULL, model="unified_m2")
  # all three partition levels must be present (wildcards for the unfiltered
  # ones) so the glob depth matches model_id/YEAR/LEA_STATE on disk
  expect_match(res$data$parquet_url, "^hf://")
  expect_match(res$data$parquet_url, "model_id=unified_m2_mod/[*]/[*]/[*][.]parquet$")
})

test_that("handle_districts rejects invalid state with api_bad_request", {
  con <- api_connect(TEST_API_DB); on.exit(api_disconnect(con))
  expect_error(
    handle_districts(con, q=NULL, state="ZZ", limit="10", offset="0"),
    class = "api_bad_request"
  )
})
