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
