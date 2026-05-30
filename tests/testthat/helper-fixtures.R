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
