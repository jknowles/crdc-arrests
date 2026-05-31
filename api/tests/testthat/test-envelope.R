test_that("ok_envelope wraps data with meta and success status", {
  e <- ok_envelope(list(list(leaid="x")), meta = list(total = 1))
  expect_equal(e$status, "success")
  expect_null(e$error)
  expect_equal(e$meta$total, 1)
  expect_equal(e$data[[1]]$leaid, "x")
  expect_equal(e$meta$version, "v1")
})

test_that("ok_envelope version cannot be overridden by caller meta", {
  e <- ok_envelope(list(), meta = list(version = "v99"))
  expect_equal(e$meta$version, "v1")
})

test_that("err_envelope sets error and null data", {
  e <- err_envelope("bad model")
  expect_equal(e$status, "error")
  expect_null(e$data)
  expect_equal(e$error, "bad model")
})

# JSON serialization: the plumber routes use @serializer unboxedJSON list(null="null")
# which passes null="null" to jsonlite::toJSON. Verify that ok_envelope serializes
# "error":null (not "error":{}) and err_envelope serializes "data":null.
test_that("ok_envelope serializes error field as JSON null literal", {
  e <- ok_envelope(list(list(leaid="x")), meta = list(total = 1L))
  json <- jsonlite::toJSON(e, auto_unbox = TRUE, null = "null")
  expect_true(grepl('"error":null', json, fixed = TRUE),
    info = paste("Expected '\"error\":null' in JSON, got:", json))
  expect_false(grepl('"error":{}', json, fixed = TRUE),
    info = "error field must not serialize as empty object")
})

test_that("err_envelope serializes data field as JSON null literal", {
  e <- err_envelope("bad model")
  json <- jsonlite::toJSON(e, auto_unbox = TRUE, null = "null")
  expect_true(grepl('"data":null', json, fixed = TRUE),
    info = paste("Expected '\"data\":null' in JSON, got:", json))
  expect_false(grepl('"data":{}', json, fixed = TRUE),
    info = "data field must not serialize as empty object")
  expect_true(grepl('"error":"bad model"', json, fixed = TRUE),
    info = "error message must appear as a string")
})
