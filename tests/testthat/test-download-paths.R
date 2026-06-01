test_that("crdc_expected_paths matches the canonical _targets.R contract", {
  # Canonical paths copied verbatim from _targets.R `crdc_data`. Keep in sync:
  # this test fails loudly if the download helper ever drifts from the pipeline.
  expected <- list(
    "2021-22" = list(
      enrollment_path = "tmp/data/2021-22-crdc-data/SCH/Enrollment.csv",
      le_path         = "tmp/data/2021-22-crdc-data/SCH/Referrals and Arrests.csv"),
    "2017-18" = list(
      enrollment_path = "tmp/data/2017-18-crdc-data-corrected-05242021/2017-18 Public-Use Files/Data/SCH/CRDC/CSV/Enrollment.csv",
      le_path         = "tmp/data/2017-18-crdc-data-corrected-05242021/2017-18 Public-Use Files/Data/SCH/CRDC/CSV/Referrals and Arrests.csv"),
    "2015-16" = list(
      enrollment_path = "tmp/data/2015-16-crdc-data/Data Files and Layouts/CRDC 2015-16 School Data.csv",
      le_path         = "tmp/data/2015-16-crdc-data/Data Files and Layouts/CRDC 2015-16 School Data.csv")
  )
  for (y in names(expected)) {
    got <- crdc_expected_paths(y, dest_dir = "tmp/data")
    expect_equal(got$enrollment_path, expected[[y]]$enrollment_path, info = y)
    expect_equal(got$le_path,         expected[[y]]$le_path,         info = y)
  }
})

test_that("crdc_expected_paths rejects unknown years", {
  expect_error(crdc_expected_paths("2099-00"), "Year must be one of")
})
