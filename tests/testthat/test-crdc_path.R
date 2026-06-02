test_that("local base returns a direct file path (no network, no cache)", {
  withr::with_envvar(c(CRDC_ARTIFACTS = "export"), {
    expect_equal(crdc_path("stages/inputs/three_year_data.parquet"),
                 file.path("export", "stages/inputs/three_year_data.parquet"))
    expect_equal(crdc_path("parquet"), file.path("export", "parquet"))
  })
})

test_that("remote small objects resolve to the hf:// URI for a direct read", {
  withr::with_envvar(c(CRDC_ARTIFACTS = "hf://datasets/civilytics/crdc-school-arrest-rates@civilytics-crdc-arrests-2025.1"), {
    expect_equal(
      crdc_path("stages/inputs/recent_data.parquet"),
      "hf://datasets/civilytics/crdc-school-arrest-rates@civilytics-crdc-arrests-2025.1/stages/inputs/recent_data.parquet")
  })
})

test_that(".crdc_is_big flags draws tree and pooled fits only", {
  expect_true(.crdc_is_big("parquet"))
  expect_true(.crdc_is_big("parquet/model_id=nat_m2_mod/YEAR=21-22/LEA_STATE=TX/data_0.parquet"))
  expect_true(.crdc_is_big("stages/models/pooled_m2.qs2"))
  expect_false(.crdc_is_big("stages/inputs/recent_data.parquet"))
  expect_false(.crdc_is_big("stages/diagnostics/model_stats.parquet"))
})

test_that(".crdc_http converts an hf:// base + rev to an https resolve URL", {
  expect_equal(
    .crdc_http("hf://datasets/civilytics/crdc-school-arrest-rates@civilytics-crdc-arrests-2025.1",
               "stages/models/pooled_m2.qs2"),
    "https://huggingface.co/datasets/civilytics/crdc-school-arrest-rates/resolve/civilytics-crdc-arrests-2025.1/stages/models/pooled_m2.qs2")
  expect_equal(
    .crdc_http("hf://datasets/civilytics/crdc-school-arrest-rates", "x.qs2"),
    "https://huggingface.co/datasets/civilytics/crdc-school-arrest-rates/resolve/main/x.qs2")
})
