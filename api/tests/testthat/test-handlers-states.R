test_that("handle_states returns state aggregates", {
  con <- api_connect(TEST_API_DB); on.exit(api_disconnect(con))
  res <- handle_states(con, state="AL", race="BL", sex="M", year="21-22",
                       model="nat_m2", interval="80", limit="100", page="0")
  expect_equal(res$status, "success")
  row <- res$data[[1]]
  expect_equal(row$state, "AL")
  expect_equal(row$rate_lower, 0.02)  # rate_lower_80
  expect_null(row$leaid)              # state grain has no LEAID
})
