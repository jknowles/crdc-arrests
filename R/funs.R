#' Query prediction draw summaries from database
#'
#' @param con DuckDB connection object
#' @param LEAID Character vector of LEA IDs to filter (optional)
#' @param RACE Character vector of race categories to filter (optional)
#' @param SEX Character vector of sex categories to filter (optional)
#' @param YEAR Character vector of years to filter (optional)
#' @param model Character vector of model IDs to filter (optional)
#' @param confidence_level Confidence level for intervals (default: 0.95 for 95% CI)
#' @param central_tendency Either "mean" or "median" for fitted value (default: "mean")
#' @param table_name Name of the database table (default: "predicted_draws")
#' @return Data frame with summary statistics for each unique combination
get_prediction_summary <- function(con, LEAID = NULL, RACE = NULL, SEX = NULL,
                                  YEAR = NULL, model = NULL,
                                  confidence_level = 0.95,
                                  central_tendency = c("mean", "median"),
                                  table_name = "predicted_draws")
                                  {

  central_tendency <- match.arg(central_tendency)

  # Calculate quantiles for confidence intervals
  alpha <- 1 - confidence_level
  lower_q <- alpha / 2
  upper_q <- 1 - alpha / 2

  # Build WHERE conditions (same logic as first function)
  where_conditions <- c()

  if (!is.null(LEAID)) {
    leaid_list <- paste0("'", LEAID, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("LEAID IN (", leaid_list, ")"))
  }

  if (!is.null(RACE)) {
    race_list <- paste0("'", RACE, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("RACE IN (", race_list, ")"))
  }

  if (!is.null(SEX)) {
    sex_list <- paste0("'", SEX, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("SEX IN (", sex_list, ")"))
  }

  if (!is.null(YEAR)) {
    year_list <- paste0("'", YEAR, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("YEAR IN (", year_list, ")"))
  }

  if (!is.null(model)) {
    model_list <- paste0("'", model, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("model_id IN (", model_list, ")"))
  }

  # Build the summary query
  fitted_value_sql <- ifelse(central_tendency == "mean",
                            "AVG(pred)",
                            "PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pred)")

  query <- paste0("
    SELECT
      model_id,
      subgroup_id,
      LEAID,
      LEA_STATE,
      YEAR,
      RACE,
      SEX,
      COUNT(draw_id) as n_draws,
      ", fitted_value_sql, " as fitted_value,
      STDDEV(pred) as sd,
      MIN(pred) as min_pred,
      MAX(pred) as max_pred,
      PERCENTILE_CONT(", lower_q, ") WITHIN GROUP (ORDER BY pred) as ci_lower,
      PERCENTILE_CONT(", upper_q, ") WITHIN GROUP (ORDER BY pred) as ci_upper
    FROM ", table_name)

  # Add WHERE clause if we have conditions
  if (length(where_conditions) > 0) {
    query <- paste(query, "WHERE", paste(where_conditions, collapse = " AND "))
  }

  # Add GROUP BY and ORDER BY
  query <- paste(query, "
    GROUP BY model_id, subgroup_id, LEAID, LEA_STATE, YEAR, RACE, SEX
    ORDER BY model_id, LEAID, YEAR, RACE, SEX
  ")

  # Execute query and return results
  # Use message() instead of cat() to allow suppression in Quarto/Knitr
  # Check if we're in a reporting environment (Quarto/Knitr) and suppress output if so
  in_report <- !is.null(getOption("knitr.in.progress")) ||
              !is.null(getOption("quarto.render")) ||
              !is.null(Sys.getenv("QUARTO_PROJECT_DIR", unset = NA))

  result <- dbGetQuery(con, query)

  # Add helpful metadata as attributes
  attr(result, "confidence_level") <- confidence_level
  attr(result, "central_tendency") <- central_tendency

  if (!in_report) {
    message("Executing summary query with ", confidence_level*100, "% confidence intervals using ", central_tendency)
    message("Query:\n", query, "\n\n")
    message("Returned ", nrow(result), " summary rows")
  }
  return(result)
}


#' Query prediction draw summaries aggregated by state
#'
#' @param con DuckDB connection object
#' @param LEA_STATE Character vector of state codes to filter (optional)
#' @param RACE Character vector of race categories to filter (optional)
#' @param SEX Character vector of sex categories to filter (optional)
#' @param YEAR Character vector of years to filter (optional)
#' @param model Character vector of model IDs to filter (optional)
#' @param confidence_level Confidence level for intervals (default: 0.95 for 95% CI)
#' @param central_tendency Either "mean" or "median" for fitted value (default: "mean")
#' @param table_name Name of the database table (default: "predicted_draws")
#' @return Data frame with summary statistics aggregated by state
get_state_prediction_summary <- function(con, LEA_STATE = NULL, RACE = NULL, SEX = NULL,
                                        YEAR = NULL, model = NULL,
                                        confidence_level = 0.95,
                                        central_tendency = c("mean", "median"),
                                        table_name = "predicted_draws")
                                        {

  central_tendency <- match.arg(central_tendency)

  # Calculate quantiles for confidence intervals
  alpha <- 1 - confidence_level
  lower_q <- alpha / 2
  upper_q <- 1 - alpha / 2

  # Build WHERE conditions
  where_conditions <- c()

  if (!is.null(LEA_STATE)) {
    state_list <- paste0("'", LEA_STATE, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("LEA_STATE IN (", state_list, ")"))
  }

  if (!is.null(RACE)) {
    race_list <- paste0("'", RACE, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("RACE IN (", race_list, ")"))
  }

  if (!is.null(SEX)) {
    sex_list <- paste0("'", SEX, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("SEX IN (", sex_list, ")"))
  }

  if (!is.null(YEAR)) {
    year_list <- paste0("'", YEAR, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("YEAR IN (", year_list, ")"))
  }

  if (!is.null(model)) {
    model_list <- paste0("'", model, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("model_id IN (", model_list, ")"))
  }

  # Build the summary query - aggregating across all districts within each state
  fitted_value_sql <- ifelse(central_tendency == "mean",
                            "AVG(pred)",
                            "PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pred)")

  query <- paste0("
    SELECT
      model_id,
      subgroup_id,
      LEA_STATE,
      YEAR,
      RACE,
      SEX,
      COUNT(DISTINCT LEAID) as n_districts,
      COUNT(draw_id) as n_draws,
      COUNT(draw_id) / COUNT(DISTINCT draw_id) as n_observations,
      ", fitted_value_sql, " as fitted_value,
      STDDEV(pred) as sd,
      MIN(pred) as min_pred,
      MAX(pred) as max_pred,
      PERCENTILE_CONT(", lower_q, ") WITHIN GROUP (ORDER BY pred) as ci_lower,
      PERCENTILE_CONT(", upper_q, ") WITHIN GROUP (ORDER BY pred) as ci_upper
    FROM ", table_name)

  # Add WHERE clause if we have conditions
  if (length(where_conditions) > 0) {
    query <- paste(query, "WHERE", paste(where_conditions, collapse = " AND "))
  }

  # Group by state instead of individual districts
  query <- paste(query, "
    GROUP BY model_id, subgroup_id, LEA_STATE, YEAR, RACE, SEX
    ORDER BY model_id, LEA_STATE, YEAR, RACE, SEX
  ")

  # Execute query and return results

  result <- dbGetQuery(con, query)

  # Add helpful metadata as attributes
  attr(result, "confidence_level") <- confidence_level
  attr(result, "central_tendency") <- central_tendency
  attr(result, "aggregation_level") <- "state"
    # Execute query and return results
  # Use message() instead of cat() to allow suppression in Quarto/Knitr
  # Check if we're in a reporting environment (Quarto/Knitr) and suppress output if so
  in_report <- !is.null(getOption("knitr.in.progress")) ||
              !is.null(getOption("quarto.render")) ||
              !is.null(Sys.getenv("QUARTO_PROJECT_DIR", unset = NA))

  if(!in_report) {
    message("Returned", nrow(result), "state-level summary rows\n")
    message("Executing state-level summary query with", confidence_level*100, "% confidence intervals using", central_tendency, "\n")
  message("Query:\n", query, "\n\n")

  }

  return(result)
}


#' Query prediction draws from database
#'
#' @param con DuckDB connection object
#' @param LEAID Character vector of LEA IDs to filter (optional)
#' @param RACE Character vector of race categories to filter (optional)
#' @param SEX Character vector of sex categories to filter (optional)
#' @param YEAR Character vector of years to filter (optional)
#' @param model Character vector of model IDs to filter (optional)
#' @param table_name Name of the database table (default: "predicted_draws")
#' @return Data frame with all matching prediction draws
get_prediction_draws <- function(con, LEAID = NULL, RACE = NULL, SEX = NULL,
                                YEAR = NULL, model = NULL,
                                table_name = "predicted_draws")
                                {

  # Start building the query
  query <- paste("SELECT * FROM", table_name)
  where_conditions <- c()

  # Build WHERE conditions for each non-null parameter
  if (!is.null(LEAID)) {
    leaid_list <- paste0("'", LEAID, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("LEAID IN (", leaid_list, ")"))
  }

  if (!is.null(RACE)) {
    race_list <- paste0("'", RACE, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("RACE IN (", race_list, ")"))
  }

  if (!is.null(SEX)) {
    sex_list <- paste0("'", SEX, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("SEX IN (", sex_list, ")"))
  }

  if (!is.null(YEAR)) {
    year_list <- paste0("'", YEAR, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("YEAR IN (", year_list, ")"))
  }

  if (!is.null(model)) {
    model_list <- paste0("'", model, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("model_id IN (", model_list, ")"))
  }

  # Add WHERE clause if we have conditions
  if (length(where_conditions) > 0) {
    query <- paste(query, "WHERE", paste(where_conditions, collapse = " AND "))
  }

  # Add ordering for consistent results
  query <- paste(query, "ORDER BY model_id, LEAID, LEA_STATE, YEAR, RACE, SEX, draw_id")
  result <- dbGetQuery(con, query)
   # Use message() instead of cat() to allow suppression in Quarto/Knitr
  # Check if we're in a reporting environment (Quarto/Knitr) and suppress output if so
  in_report <- !is.null(getOption("knitr.in.progress")) ||
              !is.null(getOption("quarto.render")) ||
              !is.null(Sys.getenv("QUARTO_PROJECT_DIR", unset = NA))
  if(!in_report) {
    # Execute query and return results
    message("Executing query:\n", query, "\n\n")
    message("Returned", nrow(result), "rows\n")
  }

  return(result)
}

#' Query prediction draw summaries aggregated by state - sum of fitted values
#'
#' @param con DuckDB connection object
#' @param LEA_STATE Character vector of state codes to filter (optional)
#' @param RACE Character vector of race categories to filter (optional)
#' @param SEX Character vector of sex categories to filter (optional)
#' @param YEAR Character vector of years to filter (optional)
#' @param model Character vector of model IDs to filter (optional)
#' @param table_name Name of the database table (default: "predicted_draws")
#' @return Data frame with sum of fitted values by draw_id and state
get_state_prediction_draws <- function(con, LEA_STATE = NULL, RACE = NULL, SEX = NULL,
                                       YEAR = NULL, model = NULL,
                                       table_name = "predicted_draws")
{
  # Build WHERE conditions
  where_conditions <- c()

  if (!is.null(LEA_STATE)) {
    # Handle "ALL" case - if LEA_STATE is "ALL", we don't filter by state
    if (length(LEA_STATE) == 1 && LEA_STATE == "ALL") {
      # Don't add any state filtering condition - return all states
    } else {
      state_list <- paste0("'", LEA_STATE, "'", collapse = ",")
      where_conditions <- c(where_conditions, paste0("LEA_STATE IN (", state_list, ")"))
    }
  }

  if (!is.null(RACE)) {
    # Handle "ALL" case - if RACE is "ALL", we don't filter by race
    if (length(RACE) == 1 && RACE == "ALL") {
      # Don't add any race filtering condition - return all races
    } else {
      race_list <- paste0("'", RACE, "'", collapse = ",")
      where_conditions <- c(where_conditions, paste0("RACE IN (", race_list, ")"))
    }
  }

  if (!is.null(SEX)) {
    # Handle "ALL" case - if SEX is "ALL", we don't filter by sex
    if (length(SEX) == 1 && SEX == "ALL") {
      # Don't add any sex filtering condition - return all sexes
    } else {
      sex_list <- paste0("'", SEX, "'", collapse = ",")
      where_conditions <- c(where_conditions, paste0("SEX IN (", sex_list, ")"))
    }
  }

  if (!is.null(YEAR)) {
    year_list <- paste0("'", YEAR, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("YEAR IN (", year_list, ")"))
  }

  if (!is.null(model)) {
    model_list <- paste0("'", model, "'", collapse = ",")
    where_conditions <- c(where_conditions, paste0("model_id IN (", model_list, ")"))
  }

  # Build the query - sum fitted values by draw_id and state
  # When RACE or SEX is "ALL", we collapse the data by summing within each state
  # and exclude those columns from the result

  # Check if we need to collapse by RACE or SEX
  collapse_race <- !is.null(RACE) && length(RACE) == 1 && RACE == "ALL"
  collapse_sex <- !is.null(SEX) && length(SEX) == 1 && SEX == "ALL"

  # Build the query based on whether we're collapsing
  if (collapse_race || collapse_sex) {
    # When collapsing, don't include the collapsed columns in SELECT
    query <- paste0("
      SELECT
        model_id,
        draw_id,
        LEA_STATE,
        YEAR,
        SUM(pred) as fitted_value,
        COUNT(DISTINCT LEAID) as n_districts
      FROM ", table_name)
  } else {
    # When not collapsing, include all columns
    query <- paste0("
      SELECT
        model_id,
        draw_id,
        LEA_STATE,
        YEAR,
        RACE,
        SEX,
        SUM(pred) as fitted_value,
        COUNT(DISTINCT LEAID) as n_districts
      FROM ", table_name)
  }

  # Add WHERE clause if we have conditions
  if (length(where_conditions) > 0) {
    query <- paste(query, "WHERE", paste(where_conditions, collapse = " AND "))
  }

  # Build GROUP BY clause based on whether we're collapsing
  if (collapse_race || collapse_sex) {
    # When collapsing, group by all columns except the collapsed ones
    query <- paste(query, "
      GROUP BY model_id, draw_id, LEA_STATE, YEAR
      ORDER BY model_id, LEA_STATE, YEAR")
  } else {
    # When not collapsing, group by all columns
    query <- paste(query, "
      GROUP BY model_id, draw_id, LEA_STATE, YEAR, RACE, SEX
      ORDER BY model_id, LEA_STATE, YEAR, RACE, SEX")
  }

  # Execute query and return results
  result <- dbGetQuery(con, query)

  # Use message() instead of cat() to allow suppression in Quarto/Knitr
  # Check if we're in a reporting environment (Quarto/Knitr) and suppress output if so
  in_report <- !is.null(getOption("knitr.in.progress")) ||
              !is.null(getOption("quarto.render")) ||
              !is.null(Sys.getenv("QUARTO_PROJECT_DIR", unset = NA))

  if(!in_report) {
    message("Returned ", nrow(result), " state-level draw summary rows\n")
    message("Executing state-level draw summary query\n")
    message("Query:\n", query, "\n\n")
  }

  return(result)
}

#' Calculate summary statistics for one or more brms models
#'
#' @param models A single `brmsfit` object or a list of such objects.
#' @param model_prefix Optional prefix that will be prepended to the generated
#'   `model_name`. Useful when the same function is called on several groups of
#'   models (e.g., “baseline”, “sensitivity”).
#'
#' @return A data.frame where each row corresponds to a model and contains
#'   key diagnostics (R‑hat, ESS, runtime, etc.).
#' @examples
#' \dontrun{
#'   stats <- calculate_model_stats(my_brms_fit)
#' }
calculate_model_stats <- function(models, model_prefix = NULL) {
  # -------------------------------------------------------------------------
  # Helper utilities ---------------------------------------------------------
  # -------------------------------------------------------------------------

  ## Convert a single brmsfit object to a list for uniform processing
  as_model_list <- function(x) {
    if (inherits(x, "brmsfit")) list(x) else x
  }

  ## Safely extract an element that may be NULL; returns NA when missing
  safe_extract <- function(obj, path, default = NA) {
    Reduce(function(o, p) {
      if (is.null(o)) return(NULL)
      o[[p]]
    }, path, obj) %||% default
  }

  ## Compute the worst R‑hat across fixed and random effects
  get_worst_rhat <- function(summ) {
    rhat_vals <- c(summ$fixed$Rhat,
                    unlist(lapply(summ$random, `[[`, "Rhat"), use.names = FALSE))
    max(rhat_vals, na.rm = TRUE)
  }

  ## Gather Bulk ESS from fixed and random effects
  get_bulk_ess_stats <- function(summ) {
    ess_vals <- c(summ$fixed$Bulk_ESS,
                  unlist(lapply(summ$random, `[[`, "Bulk_ESS"), use.names = FALSE))
    list(min = min(ess_vals, na.rm = TRUE),
         mean = mean(ess_vals, na.rm = TRUE))
  }

  # -------------------------------------------------------------------------
  # Normalise input ----------------------------------------------------------
  # -------------------------------------------------------------------------

  models_list <- if (!is.list(models) || inherits(models, "brmsfit")) {
    as_model_list(models)
  } else {
    models
  }

  # Early‑exit guard – return an empty data.frame with the correct columns
  if (length(models_list) == 0L) {
    warning("No models supplied to calculate_model_stats()")
    return(data.frame())
  }

  # -------------------------------------------------------------------------
  # Main loop ---------------------------------------------------------------
  # -------------------------------------------------------------------------

  results <- lapply(seq_along(models_list), function(i) {
    model <- models_list[[i]]

    if (!inherits(model, "brmsfit")) {
      warning(sprintf("Item %d is not a brmsfit object – skipping", i))
      return(NULL)
    }

    # Model identifiers -------------------------------------------------------
    model_id   <- safe_extract(model, c("id"), paste0("model_", i))
    model_name <- if (is.null(model_prefix)) model_id else sprintf("%s_%s",
                                                                 model_prefix,
                                                                 model_id)

    # Core diagnostics --------------------------------------------------------
    summ      <- summary(model)
    timings   <- brms:::elapsed_time(model)

    worst_rhat  <- get_worst_rhat(summ)
    bulk_ess    <- get_bulk_ess_stats(summ)

    # Miscellaneous counts ----------------------------------------------------
    parameters   <- sum(unlist(model$fit@par_dims, use.names = FALSE))
    data_rows    <- nrow(model$data)

    # Runtime (minutes) – guard against missing timing info -------------------
    runtime_min  <- if (!is.null(timings$total)) {
      max(timings$total, na.rm = TRUE) / 60
    } else NA_real_

    # Assemble a single‑row data.frame ----------------------------------------
    data.frame(
      model_name     = model_name,
      model_id       = model_id,
      ndraws         = ndraws(model),
      chains         = nchains(model),
      threads        = safe_extract(model, c("threads", "threads")),
      thin           = brms:::nthin(model),
      leas           = safe_extract(summ, c("ngrps", "LEAID")),
      parameters     = parameters,
      worst_rhat     = worst_rhat,
      min_bulk_ess   = bulk_ess$min,
      mean_bulk_ess  = bulk_ess$mean,
      runtime_minutes= runtime_min,
      data_rows      = data_rows,
      stringsAsFactors = FALSE
    )
  })

  # Remove any NULL entries (e.g., skipped objects) and bind rows ----------
  results <- do.call(rbind, Filter(Negate(is.null), results))

  return(results)
}
# -------------------------------------------------------------------------


# Model cov summary function
calculate_model_cov_summaries <- function(model_list, ndraws = 100, type = "sg") {
  # Initialize an empty dataframe to store results
  results_df <- NULL

  # Loop through each model in the list using base R
  for (i in seq_along(model_list)) {
    # Get the current model
    m_tmp <- model_list[[i]]

    # Add predicted draws
    tmp <- add_predicted_draws(m_tmp$data, m_tmp, ndraws = ndraws)

    # Extract RACE and SEX from model id
    tmp$RACE <- substr(m_tmp$id, 1, 2)
    tmp$SEX <- substr(m_tmp$id, 4, 4)

    # Perform the summarization
    model_results <- tmp |>
      group_by(LEA_STATE, LEAID, RACE, SEX) |>
      summarize(
        ARRESTS = first(ARRESTS),
        stu_enroll = first(stu_enroll),
        estimate = median(.prediction / (stu_enroll / 1000)),
        .groups = "drop"
      ) |>
      group_by(RACE, SEX) |>
      summarize(
        enroll = sum(stu_enroll),
        arrests = sum(ARRESTS),
        mean_arr = mean(estimate),
        sd_arr = sd(estimate),
        .groups = "drop"
      ) |>
      mutate(
        cov_arr = (sd_arr / mean_arr) * 100,
        type = type  # Adding model identifier to track source
      )

    # Append to results dataframe
    if (is.null(results_df)) {
      results_df <- model_results
    } else {
      results_df <- rbind(results_df, model_results)
    }
  }

  return(results_df)
}


#' Intersect CRDC and CCD data
#'
#' @param crdc CRDC data frame
#' @param ccd CCD data frame
#'
#' @return Intersected data frame with combined CRDC and CCD information
intersect_crdc_ccd <- function(crdc, ccd) {
  ccd$COMBOKEY <- stringr::str_pad(ccd$ncessch_num, width = 12,
                                  side = "left", pad = "0")
  ccd <- ccd |> select(COMBOKEY, highest_grade_offered, lowest_grade_offered, latitude, longitude, enrollment)
  outdf <- inner_join(crdc, ccd, by = join_by(COMBOKEY))
  return(outdf)
}

#' Generate subset data for modeling
#'
#' @param data The full dataset to subset
#' @param race_val Race value to filter by
#' @param sex_val Sex value to filter by
#'
#' @return A stan_list object ready for brms modeling
generate_subset_data <- function(data, race_val, sex_val) {
  subset_data <- data %>%
    filter(RACE == race_val, SEX == sex_val)

  # Ensure all required variables are present and properly formatted
  subset_data <- subset_data %>%
    filter(!is.na(ARRESTS), !is.na(stu_enroll), !is.na(referral_rate), !is.na(total_referrals)) %>%
    filter(stu_enroll > 0) %>%  # Ensure we have valid denominators
    droplevels()  # Remove unused factor levels

  # Convert YEAR to factor if it isn't already, and ensure it has proper levels
  if (!is.factor(subset_data$YEAR)) {
    subset_data$YEAR <- as.factor(subset_data$YEAR)
  }
t
  # Ensure LEAID is properly formatted for random effects
  if (!is.factor(subset_data$LEAID)) {
    subset_data$LEAID <- as.factor(subset_data$LEAID)
  }

  stan_list <- brms::make_standata(
    ARRESTS | trials(stu_enroll) ~ 1 + YEAR + referral_rate + total_referrals + (1|LEAID),
    family = "binomial",
    data = subset_data,
    threads = brms::threading(2)
  )
  return(stan_list)
}

#' Generate demographic data for modeling
#'
#' @param data The full dataset to process
#'
#' @return A processed data frame ready for modeling
generate_demographic_data <- function(data) {
  # Ensure all required variables are present and properly formatted
  subset_data <- data %>%
    filter(stu_enroll > 0)

  # Convert YEAR to factor if it isn't already, and ensure it has proper levels
  if (!is.factor(subset_data$YEAR)) {
    subset_data$YEAR <- as.factor(subset_data$YEAR)
  }

  # Ensure LEAID is properly formatted for random effects
  if (!is.factor(subset_data$LEAID)) {
    subset_data$LEAID <- as.factor(subset_data$LEAID)
  }

  # Ensure LEAID is properly formatted for random effects
  if (!is.factor(subset_data$LEA_STATE)) {
    subset_data$LEA_STATE <- as.factor(subset_data$LEA_STATE)
  }

  # # Add metadata for tracking which demographic group this is
  subset_data <- subset_data |>
    mutate(group = paste(RACE, SEX, sep = "_")) |>
    as.data.frame()

  return(subset_data)
}

#' Collapse CRDC data to LEA level
#'
#' @param combined_data The combined CRDC and CCD data
#'
#' @return A collapsed data frame at the LEA level
crdc_lea_collapse <- function(combined_data) {

  combined_data <- combined_data |> filter(highest_grade_offered >= 7)

  combined_data |>
  select(LEAID, LEA_NAME, YEAR) |>
  distinct_all() |>
  group_by(LEAID) |>
  mutate(last_name = ifelse(any(YEAR == "21-22"),
                            LEA_NAME[YEAR == "21-22"],
                            ifelse(any(YEAR == "17-18"),
                            LEA_NAME[YEAR == "17-18"],
                            LEA_NAME[YEAR == "15-16"]))) |>
  ungroup() |>
  select(LEAID, last_name) |>
  distinct_all() -> lea_names_canonical

combined_data <- left_join(combined_data |> select(-LEA_NAME),
                          lea_names_canonical |>
                            rename(LEA_NAME = last_name),
                          by = join_by(LEAID))

rm(lea_names_canonical)

# Where there are more arrests than students we reduce
  # arrests to be equal to the number of students enrolled
  combined_data$ARRESTS[combined_data$ARRESTS > combined_data$stu_enroll] <-
    combined_data$stu_enroll[combined_data$ARRESTS > combined_data$stu_enroll]
  combined_data$REFERRALS[combined_data$REFERRALS  > combined_data$stu_enroll] <-
    combined_data$stu_enroll[combined_data$REFERRALS  > combined_data$stu_enroll]

# Collapse to district
dist_ref_arr <- combined_data %>%
  group_by(YEAR, LEA_STATE, LEAID, LEA_NAME, RACE, SEX) %>%
  summarize(ARRESTS = sum(ARRESTS),
            REFERRALS = sum(REFERRALS),
            stu_enroll = sum(stu_enroll)) %>%
  mutate(arrest_rate = scaled_rate(ARRESTS, stu_enroll, scale_factor = 1000),
         referral_rate = scaled_rate(REFERRALS, stu_enroll, scale_factor = 1000)) %>%
  group_by(YEAR, LEA_STATE, LEAID, LEA_NAME) |>
  mutate(total_enroll = sum(stu_enroll[RACE != "TOTAL" &
                                         SEX != "TOTAL"]),
         total_referrals = sum(REFERRALS[RACE != "TOTAL" &
                                         SEX != "TOTAL"]))

}



#' Calculate scaled rate
#'
#' @param numerator Numerator for the rate calculation
#' @param denominator Denominator for the rate calculation
#' @param scale_factor Factor to scale the result by (default: 1000)
#'
#' @return Scaled rate value
scaled_rate <- function(numerator, denominator, scale_factor = 1000) {
  result <- rep(NA_real_, length(numerator))
  valid <- denominator != 0
  result[valid] <- numerator[valid] / (denominator[valid] /scale_factor)
  zero_denom <- denominator == 0
  result[zero_denom & numerator == 0] <- 0
  result[zero_denom & numerator > 0] <- NA_real_
  result
}

#' Restrict model data for analysis
#'
#' @param data The full dataset to filter and process
#' @param enrollment_cap Minimum enrollment threshold (default: 30)
#' @param dev_mode Whether to run in development mode (default: FALSE)
#' @param year Specific year to filter by (optional)
#'
#' @return A list containing processed data and factor mappings
restrict_model_data <- function(data, enrollment_cap = 30, dev_mode = FALSE, year = NULL) {

  if (is.null(year)) {
    data <- data |> filter(RACE %in% c("WH", "BL", "AM", "HI"))
    data <- data |> filter(!SEX %in% c("TOTAL"))
    data <- data |> filter(total_enroll >= enrollment_cap)
  } else {
    data <- data |> filter(!SEX %in% c("TOTAL"))
    data <- data |> filter(RACE %in% c("WH", "BL", "AM", "HI")) |>
                     filter(YEAR == year) |>
                    filter(total_enroll >= enrollment_cap)
  }

  # Global filters
  data <- data |> filter(LEA_STATE != "PR") |>
          filter(!is.na(ARRESTS), !is.na(stu_enroll), !is.na(referral_rate),
        !is.na(total_referrals))

  if (dev_mode) {
      sampled_leaids <- data |>
      select(LEA_STATE, LEAID) |>
      distinct() |>
      group_by(LEA_STATE) |>
      slice_sample(n = 25) |>  # Sample up to 25, or all if fewer than 25
      pull(LEAID)

    # Filter to only include rows with the sampled LEAIDs
    data <- data |> filter(LEAID %in% sampled_leaids)
  }

  # Shuffle data for better performance parallelizing
  data <- data[sample(nrow(data)),]

  # Where there are more arrests than students we reduce
  # arrests to be equal to the number of students enrolled
  data$ARRESTS[data$ARRESTS > data$stu_enroll] <- data$stu_enroll[data$ARRESTS > data$stu_enroll]
  data$REFERRALS[data$REFERRALS  > data$stu_enroll] <- data$stu_enroll[data$REFERRALS  > data$stu_enroll]
  # log total referrals to improve sampler performance
  data$total_referrals <- log1p(data$total_referrals)
  data$referral_rate <- log1p(data$referral_rate)

  data <- data |> filter(stu_enroll > 0)

  data <- ungroup(data)
  data <- as.data.frame(data)

  state_factor <- data.frame(
    stan_value = factor(unique(data$LEA_STATE)) |> as.integer(),
    human_value = factor(unique(data$LEA_STATE)) |> as.character()
  )
  lea_factor <- data.frame(
    stan_value = factor(unique(data$LEAID)) |> as.integer(),
    human_value = factor(unique(data$LEAID)) |> as.character()
  )

  # let's convert and store vectors
  out <- list(data = data,
              state_keys = state_factor,
            lea_keys = lea_factor)

  return(out)

}

make_arrest_priors <- function(int_only = FALSE) {

  wi_priors <- prior(normal(-8, 3), class = "Intercept") +
  prior(cauchy(1, 2), class = "sd", group = "LEAID") +
  prior(cauchy(1, 2), class = "sd", group = "LEA_STATE")

  if (int_only) {
  wi_priors
  } else {
    wi_priors +   prior(normal(0, 5), class = "b") # TODO: Is 5 too big?
  }

}

#' Zero out missing values
#'
#' @param x a numeric vector with missing values
#'
#' @return a numeric vector with missing values replaced by 0
#' @export
#'
#' @examples
#' na_zero(1:10)
#' na_zero(c(NA, NA, 2:10))
na_zero <- function(x) {
  x[is.na(x)] <- 0
  return(x)
}


#' Reshape LE rate data to long format
#'
#' @param sch_referrals The school referrals data
#' @param year The year to process (default: "2021-22")
#'
#' @return A long-format data frame with arrest and referral rates
reshape_le_rate_long <- function(sch_referrals, year = "2021-22") {
  # Remove disability categories we won't use
    sch_referrals <- sch_referrals %>%
      select(COMBOKEY:SEX, ARRESTS:stu_enroll)

    sch_referrals_long <- sch_referrals %>%
    mutate(stu_enroll = na_zero(stu_enroll),
          ARRESTS = na_zero(ARRESTS),
          REFERRALS = na_zero(REFERRALS))  %>%
    mutate(arrest_rate = scaled_rate(ARRESTS, stu_enroll, scale_factor = 1000),
          referral_rate = scaled_rate(REFERRALS, stu_enroll, scale_factor = 1000))

    # Aggregate the total for each race across both sexes
  sch_referrals_long_sex <- sch_referrals_long %>%
    mutate(SEX = "TOTAL") %>%
    group_by(COMBOKEY, RACE, SEX) %>%
    summarise(stu_enroll = sum(stu_enroll, na.rm = TRUE),
              ARRESTS = sum(ARRESTS, na.rm = TRUE),
              REFERRALS = sum(REFERRALS, na.rm = TRUE)) %>%
    mutate(arrest_rate = scaled_rate(ARRESTS, stu_enroll, scale_factor = 1000),
          referral_rate = scaled_rate(REFERRALS, stu_enroll, scale_factor = 1000))


  # Aggregate the total for each sex across all races
  sch_referrals_long_race <- sch_referrals_long %>%
    mutate(RACE = "TOTAL") %>%
    group_by(COMBOKEY, RACE, SEX) %>%
    summarise(stu_enroll = sum(stu_enroll, na.rm = TRUE),
              ARRESTS = sum(ARRESTS, na.rm = TRUE),
              REFERRALS = sum(REFERRALS, na.rm = TRUE)) %>%
    mutate(arrest_rate = scaled_rate(ARRESTS, stu_enroll, scale_factor = 1000),
          referral_rate = scaled_rate(REFERRALS, stu_enroll, scale_factor = 1000))

  # Aggregate the total for each school across all races and sexes
  sch_referrals_long_total <- sch_referrals_long %>%
    mutate(RACE = "TOTAL") %>%
    mutate(SEX = "TOTAL") %>%
    group_by(COMBOKEY,
            RACE, SEX) %>%
    summarise(stu_enroll = sum(stu_enroll, na.rm = TRUE),
              ARRESTS = sum(ARRESTS, na.rm = TRUE),
              REFERRALS = sum(REFERRALS, na.rm = TRUE)) %>%
    mutate(arrest_rate = scaled_rate(ARRESTS, stu_enroll, scale_factor = 1000),
          referral_rate = scaled_rate(REFERRALS, stu_enroll, scale_factor = 1000))

  # Stack all of these combinations together
  sch_referrals_long <- bind_rows(
    sch_referrals_long,
    sch_referrals_long_race,
    sch_referrals_long_sex,
    sch_referrals_long_total
  )

  rm(sch_referrals_long_race, sch_referrals_long_sex,
    sch_referrals_long_total)

  # Add a year variable
  sch_referrals_long$YEAR <- year
  sch_referrals_long <- sch_referrals_long %>% group_by(COMBOKEY) %>%
  mutate(total_arrests = ARRESTS[RACE == "TOTAL" & SEX == "TOTAL"],
         total_referrals = REFERRALS[RACE == "TOTAL" & SEX == "TOTAL"],
         total_enroll = stu_enroll[RACE == "TOTAL" & SEX == "TOTAL"])

    return(sch_referrals_long)

}

# TODO improve validations
validate_le <- function(sch_referrals_long, year = "21-22") {
  # TODO: make pipeline fail if criteria are not met
  if (year == "21-22"){
    all(table(sch_referrals_long$RACE, sch_referrals_long$SEX) == 98010)
    sum(sch_referrals_long$ARRESTS[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"]) == 34846
    sum(sch_referrals_long$REFERRALS[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"]) == 209353
    sum_a <- sum(sch_referrals_long$stu_enroll[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"])
    sum_b <- sum(sch_referrals_long$total_enroll)/24 # 24 subgroup combinations
    sum_a == sum_b
    sum_a <- sum(sch_referrals_long$ARRESTS[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"])
    sum_b <- sum(sch_referrals_long$total_arrests)/24 # 24 subgroup combinations
    sum_a == sum_b
    sum_a <- sum(sch_referrals_long$REFERRALS[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"])
    sum_b <- sum(sch_referrals_long$total_referrals)/24 # 24 subgroup combinations
    sum_a == sum_b
  } else if(year == "17-18") {
    table(sch_referrals_long$RACE, sch_referrals_long$SEX)
    # Check that we did our sums correctly
    # These are our totals from above
    sum(sch_referrals_long$stu_enroll[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"])
    sum(sch_referrals_long$ARRESTS[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"]) == 52300
    sum(sch_referrals_long$REFERRALS[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"]) == 221303
    # Enroll
    sum_a <- sum(sch_referrals_long$stu_enroll[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"])
    sum_b <- sum(sch_referrals_long$total_enroll)/24 # 24 subgroup combinations
    sum_a == sum_b

  } else if(year == "15-16"){

  }
  return(TRUE)

}

incomplete_referrals <- function(sch_ref, year){
    sch_ref <- sch_ref %>% select(COMBOKEY:last_col())
    names(sch_ref) <- gsub("_IDEA_", "_", names(sch_ref))

  incomplete_referrals <- sch_ref %>% select(!matches("TOT_")) %>%
  select(!matches("_504_")) %>%
  # select(!matches("_IDEA_")) %>%
  select(!matches("_LEP_")) %>%
  pivot_longer(cols = matches("SCH_DIS"), names_prefix = "SCH_",
               names_to = c("DISAB", "REF_TYPE", "RACE", "SEX"),
               names_sep = "_")


  if (year == "21-22"){
    incomplete_referrals$RESERVE_CODE <- crdc_missing_code_2122(incomplete_referrals$value)
  } else if (year == "17-18") {
        incomplete_referrals$RESERVE_CODE <- crdc_missing_code(incomplete_referrals$value)
  } else {
      incomplete_referrals$RESERVE_CODE <- crdc_missing_code_1516(incomplete_referrals$value)
    }

    incomplete_referrals <- incomplete_referrals |>
      filter(!RESERVE_CODE  %in% c("Not Missing", "Not Applicable / Skipped"))
    return(incomplete_referrals)
}

reshape_le <- function(sch_ref, year = "21-22") {
  if (year == "15-16") {
    sch_ref$LEAID <-   stringr::str_pad(sch_ref$LEAID,
      width = 7, side = "left", pad = "0")
    sch_ref$COMBOKEY <- fix_1516_crdc_combokey(sch_ref$LEAID,
                                            sch_ref$SCHID)
    sch_ref <- sch_ref %>% select(LEA_STATE:COMBOKEY,
         matches("SCH_DISCWODIS_REF"),
         matches("SCH_DISCWDIS_REF"),
         matches("SCH_DISCWODIS_ARR"),
         matches("SCH_DISCWDIS_ARR"))

  }

 # TODO: Calculate district level impact of 504 exclusion by total
  # Drop non COMBOKEY identifier columns
  sch_ref <- sch_ref %>% select(COMBOKEY:last_col())
  names(sch_ref) <- gsub("_IDEA_", "_", names(sch_ref))
  # Do the same thing as above, but overwrite the reserve values with NA and keep all schools
  sch_ref %>% select(!matches("TOT_")) %>%
    select(!matches("_504_")) %>%
    select(!matches("_LEP_")) %>%
    select(!matches("_EL_")) %>%
    pivot_longer(cols = matches("SCH_DIS"), names_prefix = "SCH_",
                names_to = c("DISAB", "REF_TYPE", "RACE", "SEX"),
                names_sep = "_") %>%
    group_by(COMBOKEY, DISAB, REF_TYPE, RACE, SEX) %>%
    summarize(referrals = sum(crdc_sub(value), na.rm = TRUE)) -> sch_referrals
  # status are wide
  sch_referrals %>% pivot_wider(names_from = c(DISAB, REF_TYPE),
                                values_from = referrals,
                                names_sep = "_") -> sch_referrals

  # Sum arrests/referrals across disability categories
  sch_referrals$ARRESTS <- sch_referrals$DISCWDIS_ARR + sch_referrals$DISCWODIS_ARR
  sch_referrals$REFERRALS <- sch_referrals$DISCWDIS_REF + sch_referrals$DISCWODIS_REF

  # Create a school-level total for all arrests and all referrals
  sch_referrals %>%
    group_by(COMBOKEY) %>%
    mutate(total_arrests = sum(ARRESTS),
          total_referrals = sum(REFERRALS)) -> sch_referrals

  return(sch_referrals)

}

validate_enrollments <- function(data, year) {
  # TODO: Increase the resolution of this validation
  sch_pops <- data
  good_val <- sum(sch_pops$stu_enroll, na.rm = TRUE)
  sch_pops <- na.omit(sch_pops)
    #summary(sch_pops$stu_enroll)
    sch_pops %>% group_by(COMBOKEY) %>%
      mutate(total_enroll = sum(stu_enroll, na.rm = TRUE)) -> sch_pops

  if (year != "17-18"){
    stopifnot(good_val == sum(sch_pops$stu_enroll))
  } else {
    stopifnot(sum(sch_pops$total_enroll) / 14 == sum(sch_pops$stu_enroll, na.rm = TRUE))
  }
}

incomplete_enrollments <- function(data, year) {
  enrollment <- data
    if (year == "15-16") {
    enrollment$COMBOKEY <- fix_1516_crdc_combokey(enrollment$LEAID,
                                            enrollment$SCHID)
      enrollment <- enrollment %>%
        select(LEA_STATE:COMBOKEY, matches("SCH_ENR"))
  }
    enrollment <- enrollment %>% select(COMBOKEY:last_col())

    # Now we exclude counts that will lead to duplication for features we will not use.
    # We want to only retain student counts by SEX and RACE and then pivot the data long
    # so each school has a row for each combination of SEX and RACE
    enrollment %>% select(!matches("TOT_")) %>%
      select(!matches("JJ")) %>%
      select(!matches("_504")) %>%  # drop in all years to avoid double counting
      select(!matches("PSENR")) %>%
      select(!matches("_PS504ENR")) |> #drop in 2021-22
      select(!matches("LEPENR")) %>% select(!matches("LEPPROGENR")) %>%
      select(!matches("_ELENR_")) |> #drop in 2021-22
      select(!matches("_ENR_EL_")) |>
      select(!matches("_PSELPROGENR")) |> #drop in 2021-22
      select(!matches("_ELPROGENR")) |> #drop in 2021-22
      select(!matches("PSELENR_")) |> #drop in 2021-22
      select(!matches("IDEAENR")) %>%
      select(!matches("ENR_IDEA")) %>%
      select(!matches("_LEP_")) %>%
      tidyr::pivot_longer(cols = matches("SCH_ENR_"), names_prefix = "SCH_ENR_",
                  names_to = c("RACE", "SEX"),
                  names_sep = "_") %>% as.data.frame -> sch_pops

  if (year == "21-22"){
      sch_pops <- sch_pops |> filter(SEX != "X")
      incomplete_enrollment <- sch_pops[crdc_missing_code_2122(sch_pops$value) != "Not Missing",]
      incomplete_enrollment$RESERVE_CODE <- crdc_missing_code_2122(incomplete_enrollment$value)
  } else if (year == "17-18") {
      incomplete_enrollment <- sch_pops[crdc_missing_code(sch_pops$value) != "Not Missing",]
      incomplete_enrollment$RESERVE_CODE <- crdc_missing_code(incomplete_enrollment$value)
  } else {
      incomplete_enrollment <- sch_pops[crdc_missing_code_1516(sch_pops$value) != "Not Missing",]
      incomplete_enrollment$RESERVE_CODE <- crdc_missing_code_1516(incomplete_enrollment$value)
  }
  return(incomplete_enrollment)

}

# Recode race
crdc_race_recode <- function(x) {
  x[x == "WH"] <- "White"
  x[x == "BL"] <- "Black"
  x[x == "TOTAL"] <- "Total"
  x[x == "HI"] <- "Hispanic"
  x[x == "AM"] <- "Amer. Ind."
  return(x)
}

fix_1516_crdc_combokey <- function(LEAID, SCHID) {
  # Pad to the left
  LEAID <- stringr::str_pad(LEAID, width = 7, side = "left", pad = "0")
  #table(nchar(sch_crdc$SCHID))
  # Pad schid to the left
  SCHID <- stringr::str_pad(SCHID, width = 5, side = "left", pad = "0")
  COMBOKEY2 <- paste0(LEAID, SCHID)
  stopifnot(all(nchar(COMBOKEY2) == 12))
  return(COMBOKEY2)
}

sch_denom_enroll <- function(enrollment, year = "21-22") {
  if (year == "15-16") {
     enrollment$COMBOKEY <- fix_1516_crdc_combokey(enrollment$LEAID,
                                            enrollment$SCHID)
    enrollment$LEAID <-   stringr::str_pad(enrollment$LEAID, width = 7, side = "left", pad = "0")
      enrollment <- enrollment %>%
        select(LEA_STATE:COMBOKEY, matches("SCH_ENR"))

  }
  enrollment <- enrollment %>% select(COMBOKEY:last_col())

  # Now we exclude counts that will lead to duplication for features we will not use.
  # We want to only retain student counts by SEX and RACE and then pivot the data long
  # so each school has a row for each combination of SEX and RACE
  enrollment %>% select(!matches("TOT_")) %>%
    select(!matches("JJ")) %>%
    select(!matches("_504")) %>%  # drop in all years to avoid double counting
    select(!matches("PSENR")) %>%
    select(!matches("_PS504ENR")) |> #drop in 2021-22
    select(!matches("LEPENR")) %>% select(!matches("LEPPROGENR")) %>%
    select(!matches("_ELENR_")) |> #drop in 2021-22
    select(!matches("_ENR_EL_")) |>
    select(!matches("_PSELPROGENR")) |> #drop in 2021-22
    select(!matches("_ELPROGENR")) |> #drop in 2021-22
    select(!matches("PSELENR_")) |> #drop in 2021-22
    select(!matches("IDEAENR")) %>%
    select(!matches("ENR_IDEA")) %>%
    select(!matches("_LEP_")) %>%
    tidyr::pivot_longer(cols = matches("SCH_ENR_"), names_prefix = "SCH_ENR_",
                names_to = c("RACE", "SEX"),
                names_sep = "_") %>% as.data.frame -> sch_pops


  # Replace missing data/reserve codes with an NA
  if (year == "15-16") {
    sch_pops$stu_enroll <- crdc_sub_1516(sch_pops$value)
  } else {
    sch_pops$stu_enroll <- crdc_sub(sch_pops$value)
  }

  sch_pops$value <- NULL

  xval <- sum(sch_pops$stu_enroll[sch_pops$SEX == "X"], na.rm = TRUE)
  cli::cli_alert("Removing {xval} students with non-binary sex.")

  sch_pops <- sch_pops |>
    filter(SEX != "X")

  return(sch_pops)

}

get_crdc_sch_data <- function(enrollment, year = NULL) {
  sch_join_data <- enrollment %>% select(LEA_STATE, LEAID, LEA_NAME,
                                       SCHID, SCH_NAME, COMBOKEY, JJ) %>%
  distinct(.keep_all = TRUE)
   if (year == "15-16") {
     sch_join_data$LEAID <-   stringr::str_pad(sch_join_data$LEAID, width = 7,
      side = "left", pad = "0")
    sch_join_data$COMBOKEY <- fix_1516_crdc_combokey(enrollment$LEAID,
                                            enrollment$SCHID)
   }
  return(sch_join_data)
}

#' Handle CRDC skip and reserve codes
#'
#' @param x A vector of values to process for skip/reserve codes
#'
#' @return A vector with skip/reserve codes converted to NA
crdc_sub <- function(x) {
  # These are truly missing
  x[x == -4] <- NA
  x[x == -5] <- NA
  x[x == -6] <- NA
  # For arrests and referrals these skip patterns occur
  # -9 is most common, NotApplicable/Skipped
  x[x == -9] <- NA
  # -3 is least common and represents a specific failure in skip logic for the arrest/referral (ARRS) module
  x[x == -3] <- NA
  # 11 and 12 represent suppression
  x[x == -11] <- NA # suppressed in 2017-18
  x[x == -12] <- NA # suppressed in 2021-22
  x[x == -13] <- NA
  return(x)
}

# 2015-16 skip and reserve codes
crdc_sub_1516 <- function(x) {
  # These are truly missing
  x[x == -8] <- NA
  x[x == -9] <- NA
  # System error
  x[x == -7] <- NA
  # Action plan and force certified
  x[x == -6] <- NA
  x[x == -5] <- NA
  # Suppressed values
  x[x == -2] <- NA
  return(x)
}

fix_1516_crdc_combokey <- function(LEAID, SCHID) {
  # Pad to the left
  LEAID <- stringr::str_pad(LEAID, width = 7, side = "left", pad = "0")
  #table(nchar(sch_crdc$SCHID))
  # Pad schid to the left
  SCHID <- stringr::str_pad(SCHID, width = 5, side = "left", pad = "0")
  COMBOKEY2 <- paste0(LEAID, SCHID)
  stopifnot(all(nchar(COMBOKEY2) == 12))
  return(COMBOKEY2)
}


na_sum <- function(x) {
  x[is.na(x)] <- 0
  return(sum(x))
}


match_test <- function(x, y, distinct = TRUE) {
  if (distinct) {
    x <- unique(x)
    y <- unique(y)
    cat("**** Distinct Matches ****")
    cat("\n")

  }

  xiny <- sum(x %in% y)
  total_x <- length(x)

  yinx <- sum(y %in% x)
  total_y <- length(y)

  cat("**** Match Summary ****")
  cat("\n")
  cat("X in Y")
  cat("\n")
  cat(paste0("Of the ", total_x, " X values, ", xiny, " (",
             100*round(xiny/total_x, 2), "%) were matched."))
  cat("\n")
  cat("********************************************")
  cat("\n")
  cat("Y in X")
  cat("\n")
  cat(paste0("Of the ", total_y, " Y values, ", yinx, " (",
             100*round(yinx/total_y, 2), "%) were matched."))
  cat("\n")
  cat("******************************************")

}

crdc_missing_code <- function(x) {
  y <- rep("Not Missing", length(x))
  y[x == -3] <- "Skip Logic Failure"
  y[x == -4] <- "Missing Optional Data"
  # What is an action plan?
  y[x == -5] <- "Action Plan"
  # Action plans provide steps on how LEA will collect this in the next
  # administration. Force certified submission do not have action plans.
  # LEAs that are force certified are found in Public-Use Data File User's Manual
  y[x == -6] <- "Force Certified"
  y[x == -8] <- "EdFacts Missing Data"
  y[x == -9] <- "Not Applicable / Skipped"
  y[x == -13] <- "Missing DIND skip logic"

  y[x == -11] <- "Suppressed Data"
  return(y)


}

crdc_missing_code_2122 <- function(x) {
  y <- rep("Not Missing", length(x))
  y[x == -3] <- "Skip Logic Failure"
  y[x == -4] <- "Missing Optional Data"
  # What is an action plan?
  y[x == -5] <- "Action Plan"
  # Action plans provide steps on how LEA will collect this in the next
  # administration. Force certified submission do not have action plans.
  # LEAs that are force certified are found in Public-Use Data File User's Manual
  y[x == -6] <- "Force Certified"
  y[x == -8] <- "EdFacts Missing Data"
  y[x == -9] <- "Not Applicable / Skipped"
  y[x == -13] <- "Missing DIND skip logic"
  y[x == -12] <- "Suppressed Data"
  return(y)


}


#' Identify CRDC missing codes for 2015-16 data
#'
#' @param x A vector of values to identify missing codes for
#'
#' @return A vector with missing code descriptions
crdc_missing_code_1516 <- function(x) {
  y <- rep("Not Missing", length(x))
  y[x == -2] <- "Small Cell Suppression"
  # What is an action plan?
  y[x == -5] <- "Action Plan"
  # Action plans provide steps on how LEA will collect this in the next
  # administration. Force certified submission do not have action plans.
  # LEAs that are force certified are found in Public-Use Data File User's Manual
  y[x == -6] <- "Force Certified"
  y[x == -7] <- "System Error"
  y[x == -8] <- "EdFacts Missing Data"
  y[x == -9] <- "Not Applicable / Skipped"
  return(y)
}

#' Find offending character in string
#'
#' @param x The string to analyze
#' @param maxStringLength Maximum string length to check (default: 256)
#'
#' @return Prints the character by character analysis to console
find_offending_character <- function(x, maxStringLength=256){
  print(x)
  for (c in 1:maxStringLength){
    offendingChar <- substr(x,c,c)
    print(offendingChar) #uncomment if you want the indiv characters printed
    #the next character is the offending multibyte Character
  }
}

#' Parse model name into components
#'
#' @param x The model name string to parse
#' @param prefix Prefix to remove (optional)
#' @param suffix Suffix to remove (optional)
#' @param split Split pattern (default: "_")
#'
#' @return A parsed vector of components from the model name
parse_model_name <- function(x, prefix, suffix, split = "_") {
  if(length(prefix) > 1) {
    prefix <- paste0(prefix, collapse = "|")
  }
  if(length(suffix) > 1) {
    suffix <- paste0(suffix, collapse = "|")
  }
  x <- gsub(prefix, "", x)
  x <- gsub(suffix, "", x)
  x <- stringr::str_split(x, pattern = split, simplify = TRUE)
  return(x)


}

pretty_count <- function(x) {
  x <- round(x, digits = 0)
  x <- prettyNum(x, big.mark = ",")
  return(x)
}


pretty_per <- function (x, ndigit = 1)
{
    if (any(x >= 100) & !all(is.na(x))) {
        message("Values over 100 found, did you mean to use proportions?")
    }
    x <- format(round(x, digits = ndigit + 2) * 100, nsmall = ndigit)
    x <- paste0(x, "%")
    x[x == "NA%"] <- " - "
    x <- trimws(x)
    return(x)
}


#' Canonical CRDC CSV paths per year, relative to `dest_dir`.
#'
#' Single source of truth for the file locations the targets pipeline expects.
#' These MUST match the `enrollment_path`/`le_path` columns in `_targets.R`'s
#' `crdc_data` tibble (asserted by tests/testthat/test-download-paths.R).
#' Pure: computes paths only, touches no filesystem.
#'
#' @param year one of "2021-22", "2017-18", "2015-16".
#' @param dest_dir extraction root (default "tmp/data").
#' @return list(enrollment_path, le_path).
crdc_expected_paths <- function(year, dest_dir = "tmp/data") {
  valid_years <- c("2021-22", "2017-18", "2015-16")
  if (!year %in% valid_years) {
    stop("Year must be one of: ", paste(valid_years, collapse = ", "))
  }
  switch(year,
    "2021-22" = list(
      enrollment_path = file.path(dest_dir, "2021-22-crdc-data", "SCH", "Enrollment.csv"),
      le_path         = file.path(dest_dir, "2021-22-crdc-data", "SCH", "Referrals and Arrests.csv")
    ),
    "2017-18" = {
      base <- file.path(dest_dir, "2017-18-crdc-data-corrected-05242021",
                        "2017-18 Public-Use Files", "Data", "SCH", "CRDC", "CSV")
      list(enrollment_path = file.path(base, "Enrollment.csv"),
           le_path         = file.path(base, "Referrals and Arrests.csv"))
    },
    "2015-16" = {
      f <- file.path(dest_dir, "2015-16-crdc-data", "Data Files and Layouts",
                     "CRDC 2015-16 School Data.csv")
      list(enrollment_path = f, le_path = f)
    }
  )
}


#' Download and extract CRDC data files
#'
#' Downloads the Civil Rights Data Collection (CRDC) public use files from the
#' U.S. Department of Education website and extracts them to a specified directory.
#' The function handles the different file structures across the three data years
#' (2015-16, 2017-18, 2021-22).
#'
#' @param year Character string specifying the data year. Must be one of:
#'   "2021-22", "2017-18", or "2015-16"
#' @param dest_dir Character string specifying the destination directory where
#'   files will be extracted (default: "tmp/data")
#' @param download_url Character string with the download URL. If NULL (default),
#'   the function will prompt the user to manually download the file from
#'   https://civilrightsdata.ed.gov/data
#' @param zip_file Character string with path to an already-downloaded zip file.
#'   If provided, the function will skip downloading and extract this file instead.
#' @param overwrite Logical indicating whether to overwrite existing files
#'   (default: FALSE)
#'
#' @return A list with two elements:
#'   \item{enrollment_path}{Path to the enrollment CSV file}
#'   \item{le_path}{Path to the law enforcement referrals and arrests CSV file}
#'
#' @details
#' The CRDC data files have different structures across years:
#' \itemize{
#'   \item 2021-22: Files are in SCH/ subdirectory
#'   \item 2017-18: Files are in nested Public-Use Files/Data/SCH/CRDC/CSV/ structure
#'   \item 2015-16: Files are in Data Files and Layouts/ subdirectory, with both
#'         enrollment and law enforcement data in a single file
#' }
#'
#' Note: Due to the large file sizes and the need to accept terms of use on the
#' CRDC website, this function requires manual download of the zip files. Users
#' should:
#' 1. Visit https://civilrightsdata.ed.gov/data
#' 2. Select the appropriate year
#' 3. Download the CSV version of the public use files
#' 4. Provide the path to the downloaded zip file using the zip_file parameter
#'
#' @examples
#' \dontrun{
#' # After manually downloading the 2021-22 data file:
#' paths <- download_crdc_data(
#'   year = "2021-22",
#'   zip_file = "~/Downloads/2021-22-crdc-data.zip"
#' )
#'
#' # Check the extracted file paths
#' print(paths$enrollment_path)
#' print(paths$le_path)
#' }
#'
#' @export
download_crdc_data <- function(year,
                               dest_dir = "tmp/data",
                               download_url = NULL,
                               zip_file = NULL,
                               overwrite = FALSE) {

  # Validate year up front (fail-fast). crdc_expected_paths() re-checks, but the
  # early guard gives a clear error before any directory/extraction work runs.
  valid_years <- c("2021-22", "2017-18", "2015-16")
  if (!year %in% valid_years) {
    stop("Year must be one of: ", paste(valid_years, collapse = ", "))
  }

  # Create destination directory if it doesn't exist
  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE)
    message("Created directory: ", dest_dir)
  }

  # Determine the expected directory name after extraction
  year_dir <- switch(year,
    "2021-22" = "2021-22-crdc-data",
    "2017-18" = "2017-18-crdc-data-corrected-05242021",
    "2015-16" = "2015-16-crdc-data"
  )

  extract_dir <- file.path(dest_dir, year_dir)

  # Check if files already exist
  if (dir.exists(extract_dir) && !overwrite) {
    message("Data directory already exists: ", extract_dir)
    message("Set overwrite = TRUE to re-extract")
  } else {
    # Handle file download/extraction
    if (is.null(zip_file)) {
      # Provide instructions for manual download
      message("\n=== Manual Download Required ===")
      message("Please download the CRDC data files manually:")
      message("1. Visit: https://civilrightsdata.ed.gov/data")
      message("2. Select year: ", year)
      message("3. Download the CSV version of the public use files")
      message("4. Run this function again with the zip_file parameter:")
      message("   download_crdc_data(year = '", year, "', zip_file = 'path/to/downloaded/file.zip')")
      message("\nAlternatively, if you have a direct download URL, provide it via the download_url parameter.")
      stop("Manual download required. See instructions above.")
    }

    # Verify zip file exists
    if (!file.exists(zip_file)) {
      stop("Zip file not found: ", zip_file)
    }

    message("Extracting ", zip_file, " to ", extract_dir)

    # Extract the zip file
    tryCatch({
      unzip(zip_file, exdir = extract_dir, overwrite = overwrite)
      message("Successfully extracted files to: ", extract_dir)
    }, error = function(e) {
      stop("Failed to extract zip file: ", e$message)
    })
  }

  # Canonical paths (single source of truth shared with the targets pipeline).
  paths <- crdc_expected_paths(year, dest_dir = dest_dir)
  enrollment_path <- paths$enrollment_path
  le_path <- paths$le_path

  # Verify files exist
  if (!file.exists(enrollment_path)) {
    warning("Enrollment file not found at expected location: ", enrollment_path)
  }
  if (!file.exists(le_path)) {
    warning("Law enforcement file not found at expected location: ", le_path)
  }

  # Return paths
  result <- list(
    enrollment_path = enrollment_path,
    le_path = le_path,
    extract_dir = extract_dir
  )

  message("\n=== Extraction Complete ===")
  message("Enrollment file: ", enrollment_path)
  message("Law enforcement file: ", le_path)
  message("\nYou can now update the paths in _targets.R to point to these files.")

  return(invisible(result))
}


#' Automatically download CRDC data files from the official website
#'
#' This function attempts to automatically download Civil Rights Data Collection
#' (CRDC) public use files from the U.S. Department of Education website. It tries
#' multiple URL patterns and includes robust error handling with fallback to manual
#' download instructions.
#'
#' @param year Character string specifying the data year. Must be one of:
#'   "2021-22", "2017-18", or "2015-16"
#' @param dest_dir Character string specifying the destination directory where
#'   files will be downloaded and extracted (default: "tmp/data")
#' @param overwrite Logical indicating whether to overwrite existing files
#'   (default: FALSE)
#' @param accept_terms Logical indicating explicit acceptance of CRDC terms of use.
#'   Must be TRUE to proceed with download (default: FALSE)
#' @param timeout Numeric timeout in seconds for download (default: 3600 = 1 hour)
#'
#' @return A list with two elements:
#'   \item{enrollment_path}{Path to the enrollment CSV file}
#'   \item{le_path}{Path to the law enforcement referrals and arrests CSV file}
#'
#' @details
#' This function requires the httr2 package for robust HTTP downloads.
#' Install it with: install.packages("httr2")
#'
#' The function attempts multiple URL patterns to find the correct download link:
#' \itemize{
#'   \item Direct asset URLs
#'   \item Alternative download paths
#'   \item Legacy URL patterns
#' }
#'
#' If automatic download fails, the function provides detailed instructions for
#' manual download and falls back to using the existing download_crdc_data()
#' function for extraction.
#'
#' @examples
#' \dontrun{
#' # Download and extract 2021-22 data
#' paths <- auto_download_crdc_data(
#'   year = "2021-22",
#'   accept_terms = TRUE
#' )
#'
#' # Download all years
#' for (year in c("2021-22", "2017-18", "2015-16")) {
#'   auto_download_crdc_data(year = year, accept_terms = TRUE)
#' }
#' }
#'
#' @export
auto_download_crdc_data <- function(year,
                                    dest_dir = "tmp/data",
                                    overwrite = FALSE,
                                    accept_terms = FALSE,
                                    timeout = 3600) {

  # Validate year parameter
  valid_years <- c("2021-22", "2017-18", "2015-16")
  if (!year %in% valid_years) {
    stop("Year must be one of: ", paste(valid_years, collapse = ", "))
  }

  # Require explicit acceptance of terms
  if (!accept_terms) {
    message("\n=== CRDC Terms of Use ===")
    message("By downloading and using this data, you agree to:")
    message("1. The CRDC terms of use and data use agreement")
    message("2. Proper attribution of the data source")
    message("3. Compliance with all applicable privacy and data protection laws")
    message("\nFull terms available at: https://civilrightsdata.ed.gov/data")
    message("\nTo proceed, call this function with accept_terms = TRUE")
    stop("Terms of use must be explicitly accepted")
  }

  # Check for httr2 package
  if (!requireNamespace("httr2", quietly = TRUE)) {
    message("\n=== Package Installation Required ===")
    message("The httr2 package is required for automated downloads.")
    message("Install it with: install.packages('httr2')")
    message("\nAlternatively, download manually from:")
    message("https://civilrightsdata.ed.gov/data")
    stop("Package 'httr2' is required but not installed")
  }

  # Create destination directory
  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE)
    message("Created directory: ", dest_dir)
  }

  # Define multiple URL patterns to try
  # These are common patterns - actual URLs may vary
  url_patterns <- list(
    "2021-22" = c(
      "https://civilrightsdata.ed.gov/assets/ocr/docs/2021-22-crdc-data.zip",
      #"https://civilrightsdata.ed.gov/assets/downloads/2021-22-crdc-data.zip",
      #"https://www2.ed.gov/about/offices/list/ocr/docs/2021-22-crdc-data.zip",
      "https://ocrdata.ed.gov/assets/downloads/2021-22-crdc-data.zip"
    ),
    "2017-18" = c(
      "https://civilrightsdata.ed.gov/assets/ocr/docs/2017-18-crdc-data.zip",
      #"https://civilrightsdata.ed.gov/assets/downloads/2017-18-crdc-data-corrected-05242021.zip",
      #"https://www2.ed.gov/about/offices/list/ocr/docs/2017-18-crdc-data-corrected-05242021.zip",
      "https://ocrdata.ed.gov/assets/downloads/2017-18-crdc-data-corrected-05242021.zip"
    ),
    "2015-16" = c(
      "https://civilrightsdata.ed.gov/assets/ocr/docs/2015-16-crdc-data.zip",
      #"https://civilrightsdata.ed.gov/assets/downloads/2015-16-crdc-data.zip",
      #"https://www2.ed.gov/about/offices/list/ocr/docs/2015-16-crdc-data.zip",
      "https://ocrdata.ed.gov/assets/downloads/2015-16-crdc-data.zip"
    )
  )

  urls_to_try <- url_patterns[[year]]

  # Determine zip file name
  zip_filename <- paste0(gsub("-", "", year), "-crdc-data.zip")
  if (year == "2017-18") {
    zip_filename <- "2017-18-crdc-data-corrected-05242021.zip"
  }
  zip_path <- file.path(dest_dir, zip_filename)

  # Check if already downloaded
  if (file.exists(zip_path) && !overwrite) {
    message("Zip file already exists: ", zip_path)
    message("Proceeding to extraction...")
  } else {
    message("\n=== Attempting Automated Download ===")
    message("Year: ", year)
    message("Destination: ", zip_path)
    message("\nThis may take several minutes for large files...")
    message("File sizes: 2021-22 (~500MB), 2017-18 (~800MB), 2015-16 (~1.5GB)")

    download_success <- FALSE
    last_error <- NULL

    # Try each URL pattern
    for (i in seq_along(urls_to_try)) {
      url <- urls_to_try[i]
      message("\nAttempt ", i, "/", length(urls_to_try), ": ", url)

      tryCatch({
        # Create request with httr2
        req <- httr2::request(url) |>
          httr2::req_user_agent("R CRDC Analysis Pipeline (Educational Research)") |>
          httr2::req_timeout(timeout) |>
          httr2::req_retry(max_tries = 3, max_seconds = 120)

        # First check if URL exists with HEAD request
        message("  Checking URL availability...")
        head_resp <- tryCatch({
          httr2::req_method(req, "HEAD") |>
            httr2::req_perform()
        }, error = function(e) NULL)

        if (!is.null(head_resp) && httr2::resp_status(head_resp) == 200) {
          message("  ✓ URL is accessible, starting download...")

          # Perform the actual download
          httr2::req_perform(req, path = zip_path)

          # Verify file was downloaded and has content
          if (file.exists(zip_path) && file.info(zip_path)$size > 1000000) {
            message("  ✓ Download successful!")
            message("  File size: ", round(file.info(zip_path)$size / 1024^2, 1), " MB")
            download_success <- TRUE
            break
          } else {
            message("  ✗ Downloaded file is too small or corrupt")
            if (file.exists(zip_path)) file.remove(zip_path)
          }
        } else {
          message("  ✗ URL not accessible (HTTP ",
                  if (!is.null(head_resp)) httr2::resp_status(head_resp) else "error", ")")
        }

      }, error = function(e) {
        message("  ✗ Error: ", conditionMessage(e))
        last_error <- e
      })
    }

    # If all attempts failed, provide manual download instructions
    if (!download_success) {
      message("\n", strrep("=", 70))
      message("AUTOMATED DOWNLOAD FAILED")
      message(strrep("=", 70))
      message("\nAll automatic download attempts were unsuccessful.")
      message("This may be due to:")
      message("  • Changed URL structure on the CRDC website")
      message("  • Network connectivity issues")
      message("  • Firewall or proxy restrictions")
      message("  • Website maintenance or temporary unavailability")
      message("\n=== MANUAL DOWNLOAD REQUIRED ===")
      message("Please download the file manually:")
      message("1. Visit: https://civilrightsdata.ed.gov/data")
      message("2. Select year: ", year)
      message("3. Click 'Download CSV' for the public use files")
      message("4. Save the zip file to: ", dest_dir)
      message("5. Run this command:")
      message("   download_crdc_data(")
      message("     year = '", year, "',")
      message("     zip_file = '", zip_path, "',")
      message("     dest_dir = '", dest_dir, "'")
      message("   )")
      message(strrep("=", 70))

      stop("Automated download failed. Please download manually (see instructions above).")
    }
  }

  # Extract using the existing function
  message("\n=== Extracting Files ===")
  result <- download_crdc_data(
    year = year,
    dest_dir = dest_dir,
    zip_file = zip_path,
    overwrite = overwrite
  )

  return(invisible(result))
}
