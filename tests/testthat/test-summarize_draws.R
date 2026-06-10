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

test_that("build_arrest_summary: LEAID absent from enroll_lookup yields NA rate", {
  # Build a bespoke draws connection that includes a third LEAID not in enrollment
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  draws <- rbind(
    data.frame(LEAID = "0100005", LEA_STATE = "AL", YEAR = "21-22", RACE = "BL",
               SEX = "M", pred = 0:9, draw_id = 1:10,
               model_id = "unified_m2_mod", subgroup_id = "unified_m2_mod",
               stringsAsFactors = FALSE),
    # "9999999" has no entry in enroll_lookup -> stu_enroll will be NA
    data.frame(LEAID = "9999999", LEA_STATE = "AL", YEAR = "21-22", RACE = "BL",
               SEX = "M", pred = 1:10, draw_id = 1:10,
               model_id = "unified_m2_mod", subgroup_id = "unified_m2_mod",
               stringsAsFactors = FALSE)
  )
  DBI::dbWriteTable(con, "predicted_draws", draws)

  enroll <- fixture_enroll_lookup()[fixture_enroll_lookup()$LEAID == "0100005", ]
  dim_df <- rbind(
    fixture_district_dim(),
    data.frame(LEAID = "9999999", lea_name = "Unknown SD", LEA_STATE = "AL",
               state_name = "Alabama", lat = 32.3, lon = -86.3,
               enrollment = 0L, stringsAsFactors = FALSE)
  )
  api_path <- tempfile(fileext = ".duckdb")

  build_arrest_summary(draws_con = con, enroll_lookup = enroll,
                       district_dim = dim_df, api_db_path = api_path,
                       probs = c(0.5, 0.95))

  acon <- DBI::dbConnect(duckdb::duckdb(), dbdir = api_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(acon, shutdown = TRUE), add = TRUE)
  s <- DBI::dbGetQuery(acon, "SELECT * FROM arrest_summary ORDER BY LEAID")

  missing_row <- s[s$LEAID == "9999999", ]
  expect_true(is.na(missing_row$rate_median))
})

test_that("build_arrest_summary: un-padded LEAID in draws still joins district geo", {
  # Draws use 6-char LEAID "100005"; district_dim uses 7-char "0100005".
  # The normalization should zero-pad both sides before the merge.
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  draws <- data.frame(
    LEAID = "100005",          # un-padded — simulates raw CRDC data
    LEA_STATE = "AL", YEAR = "21-22", RACE = "BL", SEX = "M",
    pred = 0:9, draw_id = 1:10,
    model_id = "unified_m2_mod", subgroup_id = "unified_m2_mod",
    stringsAsFactors = FALSE
  )
  DBI::dbWriteTable(con, "predicted_draws", draws)

  enroll <- data.frame(
    LEAID = "100005", YEAR = "21-22", RACE = "BL", SEX = "M",
    stu_enroll = 100L, observed_arrests = 3L,
    stringsAsFactors = FALSE
  )
  dim_df <- data.frame(
    LEAID = "0100005",         # 7-char padded — canonical form in district_dim
    lea_name = "Alpha SD", LEA_STATE = "AL", state_name = "Alabama",
    lat = 32.1, lon = -86.1, enrollment = 1200L,
    stringsAsFactors = FALSE
  )
  api_path <- tempfile(fileext = ".duckdb")

  build_arrest_summary(draws_con = con, enroll_lookup = enroll,
                       district_dim = dim_df, api_db_path = api_path,
                       probs = c(0.5, 0.95))

  acon <- DBI::dbConnect(duckdb::duckdb(), dbdir = api_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(acon, shutdown = TRUE), add = TRUE)
  s <- DBI::dbGetQuery(acon, "SELECT * FROM arrest_summary")

  expect_equal(nrow(s), 1L)
  expect_false(is.na(s$lea_name[1]),
    label = "un-padded LEAID should match padded district_dim entry after normalization")
  expect_equal(s$lea_name[1], "Alpha SD")
})

test_that("build_state_summary aggregates per-draw then summarizes", {
  # Two LEAs in AL, same group, 2 draws each; per-draw state count = sum across LEAs
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir=":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  draws <- rbind(
    data.frame(LEAID="0100005", LEA_STATE="AL", YEAR="21-22", RACE="BL", SEX="M",
               pred=c(2L,4L), draw_id=1:2, model_id="unified_m2_mod",
               subgroup_id="unified_m2_mod"),
    data.frame(LEAID="0100006", LEA_STATE="AL", YEAR="21-22", RACE="BL", SEX="M",
               pred=c(3L,3L), draw_id=1:2, model_id="unified_m2_mod",
               subgroup_id="unified_m2_mod")
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
  # HPD interval assertions for 2-draw fixture (draw totals 5 and 7)
  expect_equal(s$count_lower_95, 5)
  expect_equal(s$count_upper_95, 7)
  expect_true(s$count_lower_95 <= s$count_median && s$count_upper_95 >= s$count_median)
})

test_that("write_api_meta stamps the data_release", {
  api_path <- tempfile(fileext=".duckdb")
  acon <- DBI::dbConnect(duckdb::duckdb(), dbdir=api_path)
  DBI::dbWriteTable(acon, "arrest_summary",
                    data.frame(LEAID="x"), overwrite=TRUE)
  DBI::dbDisconnect(acon, shutdown=TRUE)

  write_api_meta(api_path, data_release="civilytics-crdc-arrests-2025.1")

  acon <- DBI::dbConnect(duckdb::duckdb(), dbdir=api_path, read_only=TRUE)
  on.exit(DBI::dbDisconnect(acon, shutdown=TRUE))
  m <- DBI::dbGetQuery(acon, "SELECT * FROM meta")
  expect_equal(m$data_release[1], "civilytics-crdc-arrests-2025.1")
  expect_equal(m$citation[1], "Knowles & Miller 2025")
  expect_equal(m$default_model_unified[1], "unified_m2_mod")
  expect_equal(m$default_model_stratified[1], "stratified_m2_mod")
})
