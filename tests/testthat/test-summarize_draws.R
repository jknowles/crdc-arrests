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

test_that("build_arrest_summary writes one row per group with count+rate+intervals", {
  draws_con <- fixture_draws_con(); on.exit(DBI::dbDisconnect(draws_con, shutdown = TRUE))
  api_path <- tempfile(fileext = ".duckdb")

  build_arrest_summary(
    draws_con   = draws_con,
    enroll_lookup = fixture_enroll_lookup(),
    district_dim  = fixture_district_dim(),
    api_db_path   = api_path,
    probs = c(0.5, 0.8, 0.95)
  )

  acon <- DBI::dbConnect(duckdb::duckdb(), dbdir = api_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(acon, shutdown = TRUE), add = TRUE)
  s <- DBI::dbGetQuery(acon, "SELECT * FROM arrest_summary ORDER BY LEAID")

  expect_equal(nrow(s), 2L)
  # group A counts 0..9: median 4.5; rate = count / stu_enroll(100)
  a <- s[s$LEAID == "0100005", ]
  expect_equal(a$count_median, 4.5)
  expect_equal(a$rate_median, 4.5 / 100)
  expect_equal(a$stu_enroll, 100)
  expect_equal(a$observed_arrests, 3)
  expect_equal(a$lea_name, "Alpha SD")
  # interval columns present and ordered
  expect_true(a$count_lower_95 <= a$count_median)
  expect_true(a$count_upper_95 >= a$count_median)
  expect_equal(a$rate_lower_80, a$count_lower_80 / 100)
})

test_that("build_state_summary aggregates per-draw then summarizes", {
  # Two LEAs in AL, same group, 2 draws each; per-draw state count = sum across LEAs
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir=":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  draws <- rbind(
    data.frame(LEAID="0100005", LEA_STATE="AL", YEAR="21-22", RACE="BL", SEX="M",
               pred=c(2L,4L), draw_id=1:2, model_id="nat_m2_mod",
               subgroup_id="nat_m2_mod"),
    data.frame(LEAID="0100006", LEA_STATE="AL", YEAR="21-22", RACE="BL", SEX="M",
               pred=c(3L,3L), draw_id=1:2, model_id="nat_m2_mod",
               subgroup_id="nat_m2_mod")
  )
  DBI::dbWriteTable(con, "predicted_draws", draws)
  enroll <- data.frame(LEAID=c("0100005","0100006"), YEAR="21-22", RACE="BL",
                       SEX="M", stu_enroll=c(100L,100L), observed_arrests=c(1L,2L))
  api_path <- tempfile(fileext=".duckdb")

  build_state_summary(draws_con=con, enroll_lookup=enroll,
                      api_db_path=api_path, probs=c(0.5,0.8,0.95))

  acon <- DBI::dbConnect(duckdb::duckdb(), dbdir=api_path, read_only=TRUE)
  on.exit(DBI::dbDisconnect(acon, shutdown=TRUE), add=TRUE)
  s <- DBI::dbGetQuery(acon, "SELECT * FROM state_summary")

  # per-draw state counts: draw1 = 2+3 = 5, draw2 = 4+3 = 7; median = 6
  expect_equal(s$count_median, 6)
  # state enrollment = 200; rate_median = 6/200
  expect_equal(s$stu_enroll, 200)
  expect_equal(s$rate_median, 6/200)
})
