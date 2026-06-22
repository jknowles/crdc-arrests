# Tests for the HuggingFace auth + retry hardening in R/crdc_path.R.
# Pure logic only — no network. (.crdc_hf_token / .crdc_hf_auth / .crdc_with_retry
# are sourced via setup.R.)

test_that(".crdc_hf_token reads HF_TOKEN, then HUGGING_FACE_HUB_TOKEN, else ''", {
  withr::local_envvar(c(HF_TOKEN = "", HUGGING_FACE_HUB_TOKEN = ""))
  expect_identical(.crdc_hf_token(), "")

  withr::local_envvar(c(HF_TOKEN = "hf_primary"))
  expect_identical(.crdc_hf_token(), "hf_primary")

  withr::local_envvar(c(HF_TOKEN = "", HUGGING_FACE_HUB_TOKEN = "hf_fallback"))
  expect_identical(.crdc_hf_token(), "hf_fallback")
})

test_that(".crdc_with_retry returns immediately on success without sleeping", {
  calls <- 0L
  out <- .crdc_with_retry(function() { calls <<- calls + 1L; 42 }, base_wait = 0)
  expect_equal(out, 42)
  expect_equal(calls, 1L)
})

test_that(".crdc_with_retry retries a 429 then succeeds", {
  calls <- 0L
  fn <- function() {
    calls <<- calls + 1L
    if (calls < 3L) stop("HTTP 429 rate limit exceeded")
    "ok"
  }
  expect_message(
    out <- .crdc_with_retry(fn, tries = 5L, base_wait = 0),
    "attempt 1/5"
  )
  expect_equal(out, "ok")
  expect_equal(calls, 3L)
})

test_that(".crdc_with_retry re-raises a non-retryable error immediately", {
  calls <- 0L
  fn <- function() { calls <<- calls + 1L; stop("syntax error near 'FROM'") }
  expect_error(.crdc_with_retry(fn, tries = 5L, base_wait = 0), "syntax error")
  expect_equal(calls, 1L)  # not retried
})

test_that(".crdc_with_retry gives up after exhausting attempts on persistent 429", {
  calls <- 0L
  fn <- function() { calls <<- calls + 1L; stop("HTTP Error 429") }
  expect_error(.crdc_with_retry(fn, tries = 3L, base_wait = 0), "429")
  expect_equal(calls, 3L)
})

test_that(".crdc_hf_auth is a no-op (no error) when no token is set", {
  withr::local_envvar(c(HF_TOKEN = "", HUGGING_FACE_HUB_TOKEN = ""))
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit({ DBI::dbDisconnect(con, shutdown = TRUE) }, add = TRUE)
  expect_identical(.crdc_hf_auth(con), con)
})
