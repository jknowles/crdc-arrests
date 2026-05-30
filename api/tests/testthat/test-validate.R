test_that("validate_model accepts allowed ids and rejects others", {
  expect_equal(validate_model("nat_m2"), "nat_m2_mod")
  expect_equal(validate_model(NULL, default = "nat_m2_mod"), "nat_m2_mod")
  expect_error(validate_model("nat_m9"), class = "api_bad_request")
})

test_that("validate_interval coerces to allowed masses", {
  expect_equal(validate_interval("80"), 80L)
  expect_equal(validate_interval(NULL), 95L)
  expect_error(validate_interval("70"), class = "api_bad_request")
})

test_that("validate_enum checks race/sex/year", {
  expect_equal(validate_enum("BL", c("AM","BL","HI","WH"), "race"), "BL")
  expect_error(validate_enum("ZZ", c("AM","BL","HI","WH"), "race"),
               class = "api_bad_request")
})

test_that("validate_limit caps and floors", {
  expect_equal(validate_limit("100"), 100L)
  expect_equal(validate_limit(NULL), 100L)
  expect_equal(validate_limit("99999"), 1000L)  # capped
  expect_error(validate_limit("-1"), class = "api_bad_request")
})
