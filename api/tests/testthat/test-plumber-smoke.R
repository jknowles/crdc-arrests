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
