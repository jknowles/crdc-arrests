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
    # group A: counts 0..9 (n=10), nat_m2_mod
    data.frame(LEAID="0100005", LEA_STATE="AL", YEAR="21-22", RACE="BL", SEX="M",
               pred=0:9, draw_id=1:10, model_id="nat_m2_mod",
               subgroup_id="nat_m2_mod", stringsAsFactors=FALSE),
    # group B: counts all 5 (n=10), nat_m2_mod
    data.frame(LEAID="0100006", LEA_STATE="AL", YEAR="21-22", RACE="WH", SEX="F",
               pred=rep(5L,10), draw_id=1:10, model_id="nat_m2_mod",
               subgroup_id="nat_m2_mod", stringsAsFactors=FALSE)
  )
  DBI::dbWriteTable(con, "predicted_draws", draws)
  con
}
