test_that("API boots and serves /health, /estimates, /openapi.json", {
  skip_on_cran()
  testthat::skip_if_not_installed("callr")
  testthat::skip_if_not_installed("httr2")
  port <- 8137L
  db <- normalizePath(TEST_API_DB)
  api_dir <- normalizePath(file.path("..", ".."))  # api/
  rp <- callr::r_bg(function(db, port, api_dir) {
    setwd(api_dir)                 # plumber.R sources "R/" relative to cwd
    Sys.setenv(API_DB_PATH = db)
    plumber::pr_run(plumber::pr("plumber.R"), host = "127.0.0.1", port = port)
  }, args = list(db = db, port = port, api_dir = api_dir))
  on.exit({ rp$kill() })
  # wait for boot
  ok <- FALSE
  for (i in 1:50) { Sys.sleep(0.2)
    res <- tryCatch(httr2::req_perform(httr2::request(sprintf("http://127.0.0.1:%d/api/v1/health", port))),
                    error = function(e) NULL)
    if (!is.null(res) && httr2::resp_status(res) == 200) { ok <- TRUE; break } }
  expect_true(ok)

  base <- sprintf("http://127.0.0.1:%d", port)
  est <- httr2::resp_body_json(httr2::req_perform(httr2::request(
    paste0(base, "/api/v1/estimates?leaid=0100005&model=unified_m2"))))
  expect_equal(est$status, "success")
  expect_equal(est$data[[1]]$leaid, "0100005")

  # plumber serves the OpenAPI spec at the root /openapi.json
  spec <- httr2::req_perform(httr2::request(paste0(base, "/openapi.json")))
  expect_equal(httr2::resp_status(spec), 200)
})

test_that("invalid input returns a 400 error envelope, not a bare 500", {
  skip_on_cran()
  testthat::skip_if_not_installed("callr")
  testthat::skip_if_not_installed("httr2")
  port <- 8138L
  db <- normalizePath(TEST_API_DB)
  api_dir <- normalizePath(file.path("..", ".."))  # api/
  rp <- callr::r_bg(function(db, port, api_dir) {
    setwd(api_dir)
    Sys.setenv(API_DB_PATH = db)
    plumber::pr_run(plumber::pr("plumber.R"), host = "127.0.0.1", port = port)
  }, args = list(db = db, port = port, api_dir = api_dir))
  on.exit({ rp$kill() })
  ok <- FALSE
  for (i in 1:50) { Sys.sleep(0.2)
    res <- tryCatch(httr2::req_perform(httr2::request(sprintf("http://127.0.0.1:%d/api/v1/health", port))),
                    error = function(e) NULL)
    if (!is.null(res) && httr2::resp_status(res) == 200) { ok <- TRUE; break } }
  expect_true(ok)

  base <- sprintf("http://127.0.0.1:%d", port)
  get_raw <- function(path) {
    req <- httr2::request(paste0(base, path))
    req <- httr2::req_error(req, is_error = function(resp) FALSE)  # don't throw on 4xx/5xx
    httr2::req_perform(req)
  }

  # unknown model -> 400 with the {status,data,error,meta} envelope (NOT a bare 500)
  resp <- get_raw("/api/v1/estimates?leaid=0100005&model=bogus_xyz")
  expect_equal(httr2::resp_status(resp), 400L)
  body <- httr2::resp_body_json(resp)
  expect_equal(body$status, "error")
  expect_null(body$data)
  expect_match(body$error, "model", ignore.case = TRUE)

  # invalid interval is also a validation error -> 400
  resp2 <- get_raw("/api/v1/estimates?leaid=0100005&model=unified_m2&interval=42")
  expect_equal(httr2::resp_status(resp2), 400L)
  expect_equal(httr2::resp_body_json(resp2)$status, "error")
})
