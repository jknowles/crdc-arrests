test_that("registry has all 10 models with unique ids", {
  reg <- crdc_model_registry()
  expect_equal(nrow(reg), 10L)
  expect_equal(anyDuplicated(reg$id), 0L)
  expect_setequal(reg$group, c("pooled", "student_group"))
})

test_that("crdc_model_label maps ids to Pooled / Student-group labels", {
  expect_equal(crdc_model_label("nat_m2_mod"), "Pooled (m2)")
  expect_equal(crdc_model_label("sg_m4_mod"), "Student-group (m4)")
  expect_equal(crdc_model_label(c("nat_m1_mod", "sg_m1_mod")),
               c("Pooled (m1)", "Student-group (m1)"))
  expect_true(is.na(crdc_model_label("does_not_exist")))
})

test_that("crdc_pooled_ids returns the 5 nat_* fits that ship as qs2", {
  expect_equal(crdc_pooled_ids(),
               c("nat_m1_mod", "nat_m2_mod", "nat_m3_mod", "nat_m4_mod", "nat_m5_mod"))
})
