test_that("handle_estimates returns rate+count with requested interval", {
  con <- api_connect(TEST_API_DB); on.exit(api_disconnect(con))
  res <- handle_estimates(con, leaid="0100005", state=NULL, race="BL", sex="M",
                          year="21-22", model="unified_m2", interval="95",
                          limit="100", page="0")
  expect_equal(res$status, "success")
  row <- res$data[[1]]
  expect_equal(row$leaid, "0100005")
  expect_equal(row$rate_median, 0.05)
  expect_equal(row$rate_lower, 0.02)   # from rate_lower_95
  expect_equal(row$rate_upper, 0.10)
  expect_equal(res$meta$model, "unified_m2_mod")
  expect_equal(res$meta$interval, 95L)
})

test_that("handle_estimates rejects bad race", {
  con <- api_connect(TEST_API_DB); on.exit(api_disconnect(con))
  expect_error(handle_estimates(con, leaid=NULL, state=NULL, race="ZZ", sex=NULL,
    year=NULL, model=NULL, interval=NULL, limit=NULL, page=NULL),
    class = "api_bad_request")
})

test_that("handle_estimates rejects invalid state code", {
  con <- api_connect(TEST_API_DB); on.exit(api_disconnect(con))
  expect_error(handle_estimates(con, leaid=NULL, state="ZZ", race=NULL, sex=NULL,
    year=NULL, model=NULL, interval=NULL, limit=NULL, page=NULL),
    class = "api_bad_request")
})
