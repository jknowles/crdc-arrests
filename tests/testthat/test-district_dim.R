test_that("build_district_dim unions years, deduplicates by LEAID, and maps FIPS to state", {
  ccd <- list(
    fixture_ccd_dir("2015"),
    fixture_ccd_dir("2017"),
    fixture_ccd_dir("2021")
  )
  dim <- build_district_dim(ccd)

  expect_setequal(names(dim),
    c("LEAID", "lea_name", "LEA_STATE", "state_name", "lat", "lon", "enrollment"))
  # one row per LEAID
  expect_equal(nrow(dim), 2L)
  expect_false(any(duplicated(dim$LEAID)))
  # latest (2021) name wins
  expect_true(all(grepl("2021", dim$lea_name)))
  # state mapped from FIPS "01" -> AL
  expect_equal(unique(dim$LEA_STATE), "AL")
  expect_equal(unique(dim$state_name), "Alabama")
})

test_that("build_district_dim zero-pads short LEAID and FIPS codes", {
  short <- fixture_ccd_dir("2021", leaids = c("100005", "100006"))
  short$fips <- "1"
  d <- build_district_dim(list(short))
  expect_equal(sort(d$LEAID), c("0100005", "0100006"))
  expect_equal(unique(d$LEA_STATE), "AL")
})
