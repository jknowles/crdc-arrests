test_that("ok_envelope wraps data with meta and success status", {
  e <- ok_envelope(list(list(leaid="x")), meta = list(total = 1))
  expect_equal(e$status, "success")
  expect_null(e$error)
  expect_equal(e$meta$total, 1)
  expect_equal(e$data[[1]]$leaid, "x")
})

test_that("err_envelope sets error and null data", {
  e <- err_envelope("bad model")
  expect_equal(e$status, "error")
  expect_null(e$data)
  expect_equal(e$error, "bad model")
})
