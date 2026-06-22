# Tests for cv_stamp_logo_png() (R/branding.R), sourced via setup.R.

test_that("cv_stamp_logo_png stamps a PNG in place and returns the path invisibly", {
  skip_if_not_installed("magick")
  skip_if_not_installed("civilytics")
  p <- withr::local_tempfile(fileext = ".png")
  magick::image_write(magick::image_blank(400, 150, "white"), p)
  before <- file.info(p)$size
  expect_invisible(out <- cv_stamp_logo_png(p))
  expect_identical(out, p)
  expect_true(file.info(p)$size != before)  # modified in place
})

test_that("cv_stamp_logo_png runs for every type/variant/position combo", {
  skip_if_not_installed("magick")
  skip_if_not_installed("civilytics")
  p <- withr::local_tempfile(fileext = ".png")
  magick::image_write(magick::image_blank(400, 150, "white"), p)
  for (ty in c("wordmark", "mark")) {
    for (va in c("light", "dark")) {
      for (pos in c("bottom-right", "bottom-left", "top-right", "top-left")) {
        expect_silent(cv_stamp_logo_png(p, type = ty, variant = va, position = pos))
      }
    }
  }
})

test_that("cv_stamp_logo_png rejects an unknown type", {
  p <- withr::local_tempfile(fileext = ".png")
  expect_error(cv_stamp_logo_png(p, type = "banner"))
})
