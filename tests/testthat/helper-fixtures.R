# A minimal CCD school-district directory frame, as returned per-year by
# educationdata::get_education_data(level="school-districts", topic="directory").
fixture_ccd_dir <- function(year, leaids = c("0100005", "0100006")) {
  data.frame(
    year = year,
    leaid = leaids,
    lea_name = paste0("District ", leaids, " (", year, ")"),
    fips = "01",
    latitude = c(32.1, 32.2)[seq_along(leaids)],
    longitude = c(-86.1, -86.2)[seq_along(leaids)],
    enrollment = c(1200L, 3400L)[seq_along(leaids)],
    stringsAsFactors = FALSE
  )
}

# Build a tiny in-memory predicted_draws table for SQL tests.
# Two groups, known draw vectors so HPD/median are hand-verifiable.
fixture_draws_con <- function() {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  draws <- rbind(
    # group A: counts 0..9 (n=10), unified_m2_mod
    data.frame(LEAID="0100005", LEA_STATE="AL", YEAR="21-22", RACE="BL", SEX="M",
               pred=0:9, draw_id=1:10, model_id="unified_m2_mod",
               subgroup_id="unified_m2_mod", stringsAsFactors=FALSE),
    # group B: counts all 5 (n=10), unified_m2_mod
    data.frame(LEAID="0100006", LEA_STATE="AL", YEAR="21-22", RACE="WH", SEX="F",
               pred=rep(5L,10), draw_id=1:10, model_id="unified_m2_mod",
               subgroup_id="unified_m2_mod", stringsAsFactors=FALSE)
  )
  DBI::dbWriteTable(con, "predicted_draws", draws)
  con
}

fixture_enroll_lookup <- function() {
  data.frame(
    LEAID = c("0100005", "0100006"),
    YEAR  = c("21-22", "21-22"),
    RACE  = c("BL", "WH"),
    SEX   = c("M", "F"),
    stu_enroll = c(100L, 200L),
    observed_arrests = c(3L, 5L),
    stringsAsFactors = FALSE
  )
}

fixture_district_dim <- function() {
  data.frame(
    LEAID = c("0100005", "0100006"),
    lea_name = c("Alpha SD", "Beta SD"),
    LEA_STATE = c("AL", "AL"),
    state_name = c("Alabama", "Alabama"),
    lat = c(32.1, 32.2), lon = c(-86.1, -86.2),
    enrollment = c(1200L, 3400L), stringsAsFactors = FALSE
  )
}

# A tiny on-disk predicted_draws DuckDB file (for the retained-driver wrappers,
# which open their own connection from a db path).
fixture_draws_db_file <- function(models = c("unified_m2_mod", "stratified_m2_mod")) {
  path <- tempfile(fileext = ".duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = path)
  draws <- do.call(rbind, lapply(models, function(m)
    data.frame(LEAID = "0100005", LEA_STATE = "AL", YEAR = "21-22",
               RACE = "BL", SEX = "M", pred = 0:9, draw_id = 1:10,
               model_id = m, subgroup_id = m, stringsAsFactors = FALSE)))
  DBI::dbWriteTable(con, "predicted_draws", draws)
  DBI::dbDisconnect(con, shutdown = TRUE)
  path
}
