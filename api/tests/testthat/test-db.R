test_that("api_connect opens read-only and meta loads", {
  con <- api_connect(TEST_API_DB); on.exit(api_disconnect(con))
  m <- read_meta(con)
  expect_equal(m$data_release, "civilytics-crdc-arrests-2025.1")
})

test_that("interval_cols maps mass to the right column names", {
  ic <- interval_cols(95L, "rate")
  expect_equal(ic$lower, "rate_lower_95")
  expect_equal(ic$upper, "rate_upper_95")
})
