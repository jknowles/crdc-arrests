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
  expect_true("nat_m2_mod" %in% vapply(defaults, function(m) m$model_id, character(1)))
})

test_that("handle_draws returns HF shard url + duckdb snippet, not draws", {
  res <- handle_draws(state="AL", race="BL", sex="M", year="21-22", model="nat_m2")
  expect_match(res$data$parquet_url, "huggingface.co/datasets/civilytics/crdc-school-arrest-rates")
  expect_match(res$data$duckdb_sql, "read_parquet")
  expect_match(res$data$parquet_url, "model_id=nat_m2_mod")
})

test_that("handle_draws rejects invalid state with api_bad_request", {
  expect_error(
    handle_draws(state="ZZ", race="BL", sex="M", year="21-22", model="nat_m2"),
    class = "api_bad_request"
  )
})

test_that("handle_draws with state=NULL and year=NULL omits partition segments", {
  res <- handle_draws(state=NULL, race="BL", sex="M", year=NULL, model="nat_m2")
  expect_match(res$data$parquet_url, "model_id=nat_m2_mod")
  expect_false(grepl("LEA_STATE=", res$data$parquet_url))
  expect_false(grepl("YEAR=", res$data$parquet_url))
})

test_that("handle_districts rejects invalid state with api_bad_request", {
  con <- api_connect(TEST_API_DB); on.exit(api_disconnect(con))
  expect_error(
    handle_districts(con, q=NULL, state="ZZ", limit="10", offset="0"),
    class = "api_bad_request"
  )
})
