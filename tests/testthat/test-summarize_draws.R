test_that("hpd_bounds_sql returns smallest-width interval per group", {
  con <- fixture_draws_con(); on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  sql <- hpd_bounds_sql(prob = 0.8, value_col = "pred")
  res <- DBI::dbGetQuery(con, sql)
  res <- res[order(res$LEAID), ]

  # group A: n=10, k=ceil(.8*10)=8; smallest window of 8 consecutive of 0..9
  # is [0..7] or [1..8] or [2..9], all width 7 -> lower 0, upper 7 (first ties)
  expect_equal(res$hpd_lower[res$LEAID == "0100005"], 0)
  expect_equal(res$hpd_upper[res$LEAID == "0100005"], 7)
  # group B: all 5 -> interval [5,5]
  expect_equal(res$hpd_lower[res$LEAID == "0100006"], 5)
  expect_equal(res$hpd_upper[res$LEAID == "0100006"], 5)
})
