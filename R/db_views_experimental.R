library(DBI)
# -------------------------------------------------
#  Function: create_pred_hpd_view()
# -------------------------------------------------
# Arguments
#   con          : DBI connection to DuckDB
#   prob         : Desired posterior mass (e.g. 0.95, 0.90, 0.99)
#   view_name    : Name of the view you want to create/replace
#                  (default = "v_pred_hpd")
#   batch_size   : Number of rows DuckDB should pull from the
#                  underlying table at a time when evaluating the
#                  window functions (see DuckDB PRAGMA).  A larger
#                  value reduces I/O but uses more RAM.
# -------------------------------------------------
create_pred_hpd_view <- function(con,
                                 prob = 0.95,
                                 view_name = "v_pred_hpd",
                               #  batch_size = 10e6,   # rows per vectorised chunk
                                 n_threads = parallel::detectCores(),
                                 mem_limit_gb = NULL) {
  ## -------------------------------------------------------------------------
  ## 1️⃣  Basic validation
  ## -------------------------------------------------------------------------
  if (!inherits(con, "DBIConnection")) stop("`con` must be a DBI connection")
  if (!is.numeric(prob) || prob <= 0 || prob >= 1)
    stop("`prob` must be between 0 and 1 (exclusive)")
  if (prob < 0.5) warning("Very low HPD masses (< 0.5) can give extremely narrow intervals")

  ## -------------------------------------------------------------------------
  ## 2️⃣  Engine‑wide pragmas (batch size, threads, optional memory limit)
  ## -------------------------------------------------------------------------
  # batch_size – how many rows are processed at a time in vectorised kernels
  #DBI::dbExecute(con, sprintf("PRAGMA batch_size = %d;", as.integer(batch_size)))

  # threads – use all cores you have (or specify a smaller number)
  DBI::dbExecute(con, sprintf("PRAGMA threads = %d;", as.integer(n_threads)))

  # optional memory limit (e.g., "32GB"); comment out if you do not want to set it
  if (!is.null(mem_limit_gb)) {
    DBI::dbExecute(con,
      sprintf("SET memory_limit='%sGB';", as.character(mem_limit_gb)))
  }

  ## -------------------------------------------------------------------------
  ## 3️⃣  Build the DDL statement (the only place where we inject `prob`)
  ## -------------------------------------------------------------------------
  sql <- sprintf("
    CREATE OR REPLACE VIEW %s AS
    WITH
    -------------------------------------------------
    -- 1️⃣  Count draws per group
    -------------------------------------------------
    draw_counts AS (
        SELECT
            LEAID,
            LEA_STATE,
            YEAR,
            RACE,
            SEX,
            model_id,
            subgroup_id,
            COUNT(*)                               AS n_draws
        FROM predicted_draws
        GROUP BY
            LEAID, LEA_STATE, YEAR, RACE, SEX, model_id, subgroup_id
    ),
    -------------------------------------------------
    -- 2️⃣  Number of draws that must be inside the HPD (k = ceil(p * n))
    -------------------------------------------------
    hpd_params AS (
        SELECT
            *,
            CAST(CEIL(%f * n_draws) AS BIGINT)   AS k      -- <-- user supplied probability
        FROM draw_counts
    ),
    -------------------------------------------------
    -- 3️⃣  Order draws and give each a row number inside its group
    -------------------------------------------------
    ordered_draws AS (
        SELECT
            d.LEAID,
            d.LEA_STATE,
            d.YEAR,
            d.RACE,
            d.SEX,
            d.model_id,
            d.subgroup_id,
            d.pred,
            ROW_NUMBER() OVER (
                PARTITION BY d.LEAID, d.LEA_STATE, d.YEAR,
                             d.RACE, d.SEX, d.model_id, d.subgroup_id
                ORDER BY d.pred
            )                                      AS rn,
            p.k
        FROM predicted_draws      d
        JOIN hpd_params           p USING (LEAID, LEA_STATE, YEAR,
                                            RACE, SEX, model_id, subgroup_id)
    ),
    -------------------------------------------------
    -- 4️⃣  Sliding window of size k
    -------------------------------------------------
    windows AS (
        SELECT
            LEAID,
            LEA_STATE,
            YEAR,
            RACE,
            SEX,
            model_id,
            subgroup_id,
            pred                                   AS lower_val,
            LEAD(pred, k-1) OVER (
                PARTITION BY LEAID, LEA_STATE, YEAR,
                             RACE, SEX, model_id, subgroup_id
                ORDER BY pred
            )                                      AS upper_val,
            (LEAD(pred, k-1) OVER (
                PARTITION BY LEAID, LEA_STATE, YEAR,
                             RACE, SEX, model_id, subgroup_id
                ORDER BY pred
            ) - pred)                               AS width
        FROM ordered_draws
    ),
    -------------------------------------------------
    -- 5️⃣  Pick the smallest‑width window per group (the HPD)
    -------------------------------------------------
    best_window AS (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY LEAID, LEA_STATE, YEAR,
                                RACE, SEX, model_id, subgroup_id
                   ORDER BY width
               )                                   AS rn_best
        FROM windows
        WHERE upper_val IS NOT NULL                -- drop incomplete tails
    )
    SELECT
        LEAID,
        LEA_STATE,
        YEAR,
        RACE,
        SEX,
        model_id,
        subgroup_id,
        lower_val   AS hpd_lower,
        upper_val   AS hpd_upper,
        width       AS interval_width
    FROM best_window
    WHERE rn_best = 1;
    ",
    DBI::dbQuoteIdentifier(con, view_name), prob, prob)

  ## -------------------------------------------------------------------------
  ## 4️⃣  Execute the DDL
  ## -------------------------------------------------------------------------
  message(sprintf("Creating/replacing view `%s` (HPD mass = %.3f)…",
                  view_name, prob))
  DBI::dbExecute(con, sql)

  ## -------------------------------------------------------------------------
  ## 5️⃣  Verify creation and return name invisibly
  ## -------------------------------------------------------------------------
  if (!DBI::dbExistsTable(con, view_name)) {
    stop("View creation failed – inspect DuckDB logs for the underlying error.")
  }
  invisible(view_name)
}
