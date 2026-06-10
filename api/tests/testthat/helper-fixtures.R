# Build a tiny API DuckDB (arrest_summary, state_summary, district_dim, meta).
fixture_api_db <- function() {
  path <- tempfile(fileext = ".duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = path)
  arrest <- data.frame(
    LEAID="0100005", LEA_STATE="AL", YEAR="21-22", RACE="BL", SEX="M",
    model_id="unified_m2_mod", subgroup_id="unified_m2_mod", n_draws=500L,
    stu_enroll=100L, observed_arrests=3L,
    count_median=5, count_mean=5.1, count_sd=2,
    count_lower_50=4, count_upper_50=6, count_lower_80=3, count_upper_80=8,
    count_lower_95=2, count_upper_95=10,
    rate_median=0.05, rate_mean=0.051,
    rate_lower_50=0.04, rate_upper_50=0.06, rate_lower_80=0.03, rate_upper_80=0.08,
    rate_lower_95=0.02, rate_upper_95=0.10,
    lea_name="Alpha SD", state_name="Alabama", lat=32.1, lon=-86.1,
    stringsAsFactors = FALSE)
  state <- data.frame(
    LEA_STATE="AL", YEAR="21-22", RACE="BL", SEX="M", model_id="unified_m2_mod",
    n_draws=500L, stu_enroll=200L, count_median=6, count_mean=6, count_sd=1,
    count_lower_50=5, count_upper_50=7, count_lower_80=4, count_upper_80=8,
    count_lower_95=3, count_upper_95=9, rate_median=0.03, rate_mean=0.03,
    rate_lower_50=0.025, rate_upper_50=0.035, rate_lower_80=0.02, rate_upper_80=0.04,
    rate_lower_95=0.015, rate_upper_95=0.045, stringsAsFactors=FALSE)
  ddim <- data.frame(LEAID="0100005", lea_name="Alpha SD", LEA_STATE="AL",
    state_name="Alabama", lat=32.1, lon=-86.1, enrollment=1200L,
    stringsAsFactors=FALSE)
  meta <- data.frame(data_release="civilytics-crdc-arrests-2025.1",
    citation="Knowles & Miller 2025", default_model_unified="unified_m2_mod",
    default_model_stratified="stratified_m2_mod", stringsAsFactors=FALSE)
  DBI::dbWriteTable(con, "arrest_summary", arrest)
  DBI::dbWriteTable(con, "state_summary", state)
  DBI::dbWriteTable(con, "district_dim", ddim)
  DBI::dbWriteTable(con, "meta", meta)
  DBI::dbDisconnect(con, shutdown = TRUE)
  path
}
