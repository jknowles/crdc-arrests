test_that("registry has all 10 models with unique ids", {
  reg <- crdc_model_registry()
  expect_equal(nrow(reg), 10L)
  expect_equal(anyDuplicated(reg$id), 0L)
  expect_setequal(reg$group, c("unified", "stratified"))
})

test_that("crdc_model_label maps ids to Unified / Stratified labels", {
  expect_equal(crdc_model_label("unified_m2_mod"), "Unified (m2)")
  expect_equal(crdc_model_label("stratified_m4_mod"), "Stratified (m4)")
  expect_equal(crdc_model_label(c("unified_m1_mod", "stratified_m1_mod")),
               c("Unified (m1)", "Stratified (m1)"))
  expect_true(is.na(crdc_model_label("does_not_exist")))
})

test_that("crdc_unified_ids returns the 5 unified fits that ship as qs2", {
  expect_equal(crdc_unified_ids(),
               c("unified_m1_mod", "unified_m2_mod", "unified_m3_mod", "unified_m4_mod", "unified_m5_mod"))
})
