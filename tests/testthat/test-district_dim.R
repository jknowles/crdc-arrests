test_that("combine_dist_geo unions years and keeps one row per LEAID with latest name", {
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
})
