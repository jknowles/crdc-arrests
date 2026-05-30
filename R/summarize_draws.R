library(DBI)

# Group key columns shared by every summary computation.
.GROUP_KEYS <- c("LEAID", "LEA_STATE", "YEAR", "RACE", "SEX",
                 "model_id", "subgroup_id")

#' SQL that returns the smallest-width HPD interval per group for `value_col`.
#'
#' Generalizes R/db_views_experimental.R to a parameterized, materializable
#' query. k = ceil(prob * n_draws) per group; the HPD is the min-width window
#' of k consecutive ordered draws.
#'
#' @param prob posterior mass in (0,1).
#' @param value_col column to summarize (e.g. "pred").
#' @param source_table table/relation name (default predicted_draws).
#' @return character SQL returning GROUP_KEYS + hpd_lower, hpd_upper.
hpd_bounds_sql <- function(prob, value_col = "pred",
                           source_table = "predicted_draws") {
  stopifnot(prob > 0, prob < 1)
  keys <- paste(.GROUP_KEYS, collapse = ", ")
  part <- paste(.GROUP_KEYS, collapse = ", ")
  sprintf("
    WITH counts AS (
      SELECT %s, COUNT(*) AS n_draws,
             CAST(CEIL(%f * COUNT(*)) AS BIGINT) AS k
      FROM %s GROUP BY %s
    ),
    ordered AS (
      SELECT d.*, c.k,
             ROW_NUMBER() OVER (PARTITION BY %s ORDER BY d.%s) AS rn
      FROM %s d JOIN counts c USING (%s)
    ),
    windows AS (
      SELECT %s, %s AS lower_val,
             LEAD(%s, k-1) OVER (PARTITION BY %s ORDER BY %s) AS upper_val
      FROM ordered
    ),
    widths AS (
      SELECT %s, lower_val, upper_val, (upper_val - lower_val) AS width,
             ROW_NUMBER() OVER (PARTITION BY %s ORDER BY (upper_val-lower_val), lower_val) AS rnb
      FROM windows WHERE upper_val IS NOT NULL
    )
    SELECT %s, lower_val AS hpd_lower, upper_val AS hpd_upper
    FROM widths WHERE rnb = 1",
    keys, prob, source_table, keys,
    part, value_col, source_table, keys,
    keys, value_col, value_col, part, value_col,
    keys, part,
    keys
  )
}

#' Materialize the LEA-level arrest summary into the API DuckDB.
#'
#' Computes count median/mean/sd + HPD intervals per group from a draws
#' connection, derives rate columns by dividing by stu_enroll, joins enrollment
#' and district name/geo, and writes table `arrest_summary` to api_db_path.
#'
#' @param draws_con open DBI connection holding `predicted_draws`.
#' @param enroll_lookup df: LEAID, YEAR, RACE, SEX, stu_enroll, observed_arrests.
#' @param district_dim df from build_district_dim().
#' @param api_db_path path to the (created/overwritten) API DuckDB file.
#' @param probs interval masses to compute (default 0.5, 0.8, 0.95).
build_arrest_summary <- function(draws_con, enroll_lookup, district_dim,
                                 api_db_path, probs = c(0.5, 0.8, 0.95)) {
  # register lookups in the draws connection for joining
  duckdb::duckdb_register(draws_con, "enroll_lookup", enroll_lookup)

  keys <- paste(.GROUP_KEYS, collapse = ", ")

  # base per-group stats
  base_sql <- sprintf("
    CREATE OR REPLACE TEMP TABLE _base AS
    SELECT %s,
           COUNT(*) AS n_draws,
           quantile_cont(pred, 0.5) AS count_median,
           AVG(pred) AS count_mean,
           stddev_samp(pred) AS count_sd
    FROM predicted_draws GROUP BY %s", keys, keys)
  DBI::dbExecute(draws_con, base_sql)

  # one HPD temp table per mass
  pct <- function(p) as.integer(round(p * 100))
  for (p in probs) {
    DBI::dbExecute(draws_con, sprintf(
      "CREATE OR REPLACE TEMP TABLE _hpd_%d AS %s",
      pct(p), hpd_bounds_sql(p, "pred")))
  }

  # assemble: base + hpd masses + enroll + rate derivation
  hpd_joins <- paste(vapply(probs, function(p) sprintf(
    "LEFT JOIN _hpd_%d USING (%s)", pct(p), keys), character(1)), collapse = "\n")
  hpd_cols <- paste(vapply(probs, function(p) sprintf(
    "_hpd_%d.hpd_lower AS count_lower_%d, _hpd_%d.hpd_upper AS count_upper_%d",
    pct(p), pct(p), pct(p), pct(p)), character(1)), collapse = ",\n")
  rate_cols <- paste(c(
    "count_median / NULLIF(stu_enroll,0) AS rate_median",
    "count_mean   / NULLIF(stu_enroll,0) AS rate_mean",
    vapply(probs, function(p) sprintf(
      "count_lower_%d / NULLIF(stu_enroll,0) AS rate_lower_%d,
       count_upper_%d / NULLIF(stu_enroll,0) AS rate_upper_%d",
      pct(p), pct(p), pct(p), pct(p)), character(1))), collapse = ",\n")

  assemble_sql <- sprintf("
    CREATE OR REPLACE TEMP TABLE _summary AS
    WITH joined AS (
      SELECT b.*, %s,
             e.stu_enroll, e.observed_arrests
      FROM _base b
      %s
      LEFT JOIN enroll_lookup e USING (LEAID, YEAR, RACE, SEX)
    )
    SELECT *, %s FROM joined", hpd_cols, hpd_joins, rate_cols)
  DBI::dbExecute(draws_con, assemble_sql)

  # pull to R, join district dim (small), write to API DB
  summary_df <- DBI::dbGetQuery(draws_con, "SELECT * FROM _summary")
  summary_df <- merge(summary_df,
                      district_dim[, c("LEAID","lea_name","state_name","lat","lon")],
                      by = "LEAID", all.x = TRUE)

  acon <- DBI::dbConnect(duckdb::duckdb(), dbdir = api_db_path, read_only = FALSE)
  on.exit(DBI::dbDisconnect(acon, shutdown = TRUE))
  DBI::dbWriteTable(acon, "arrest_summary", summary_df, overwrite = TRUE)
  DBI::dbExecute(acon,
    "CREATE INDEX IF NOT EXISTS idx_as_keys ON arrest_summary (LEAID, YEAR, RACE, SEX, model_id)")
  DBI::dbExecute(acon,
    "CREATE INDEX IF NOT EXISTS idx_as_state ON arrest_summary (LEA_STATE, model_id, YEAR)")
  invisible(api_db_path)
}
