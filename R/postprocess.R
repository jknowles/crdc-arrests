library(DBI)
library(duckdb)
library(tidybayes)
library(dplyr)

#' Process target models and stream prediction draws to DuckDB
#'
#' @param target_obj The target object (single model or list of models)
#' @param model_id Character string identifying the model group
#' @param ndraws Number of posterior draws to generate
#' @param con DuckDB connection object
#' @param table_name Name of the database table to write to
#' @param batch_size Number of rows to process in each batch (memory management)
#' @param create_table Whether to create/overwrite the table (first call should be TRUE)
process_target_draws <- function(target_obj, model_id, ndraws, con,
                                table_name = "predicted_draws",
                                batch_size = 25000,
                                create_table = FALSE) {

  # Determine if target is a single model or list of models
  is_model_list <- is.list(target_obj) &&
                   length(target_obj) > 1 &&
                   all(sapply(target_obj, function(x) inherits(x, "brmsfit")))

  if (is_model_list) {
    cat("Processing model list:", model_id, "with", length(target_obj), "models\n")

    # Process each model in the list
    for (i in seq_along(target_obj)) {
      model <- target_obj[[i]]

      # Extract subgroup identifier from model$id if available
      subgroup_id <- if (!is.null(model$id)) {
        model$id
      } else {
        paste0(model_id, "_", i)
      }

      cat("  Processing subgroup:", subgroup_id, "\n")

      # Process this individual model
      process_single_model_draws(
        model = model,
        model_id = model_id,
        subgroup_id = subgroup_id,
        ndraws = ndraws,
        con = con,
        table_name = table_name,
        batch_size = batch_size,
        create_table = create_table
      )

      # After first model, subsequent ones append
      create_table <- FALSE

      # Clean up
      rm(model)
      gc()
    }

  } else {
    # Single model case
    cat("Processing single model:", model_id, "\n")

    if (!inherits(target_obj, "brmsfit")) {
      stop("Target object is not a brmsfit model or list of brmsfit models")
    }

    process_single_model_draws(
      model = target_obj,
      model_id = model_id,
      subgroup_id = model_id,  # Same as model_id for single models
      ndraws = ndraws,
      con = con,
      table_name = table_name,
      batch_size = batch_size,
      create_table = create_table
    )
  }

  cat("Completed processing:", model_id, "\n")
}
#' Helper function to process a single brms model
process_single_model_draws <- function(model, model_id, subgroup_id, ndraws, con,
                                     table_name, batch_size, create_table,
                                     default_year = "21-22") {

  # Get model data and remove any grouping attributes
  model_data <- model$data %>% ungroup()
  n_rows <- nrow(model_data)
  n_batches <- ceiling(n_rows / batch_size)

  # Check if key variables exist in the data
  has_year <- "YEAR" %in% names(model_data)
  has_race <- "RACE" %in% names(model_data)
  has_sex <- "SEX" %in% names(model_data)

  # Extract demographic info from model$id if needed
  demo_info <- parse_demographic_id(model$id)

  cat("    Processing", format(n_rows, big.mark = ","), "rows in", n_batches, "batches")
  if (!has_year) cat(" (adding YEAR:", default_year, ")")
  if (!has_race) cat(" (adding RACE:", demo_info$race, ")")
  if (!has_sex) cat(" (adding SEX:", demo_info$sex, ")")
  cat("\n")

  for (batch in seq_len(n_batches)) {
    start_idx <- (batch - 1) * batch_size + 1
    end_idx <- min(batch * batch_size, n_rows)

    # Extract batch of data
    data_batch <- model_data[start_idx:end_idx, ]

    # Generate predictions and handle missing variables
    pred_batch <- add_predicted_draws(data_batch, model, ndraws = ndraws) %>%
      # Remove any grouping
      ungroup() %>%
      # Rename problematic column names FIRST
      rename(
        draw_id = .draw,
        pred = .prediction
      ) %>%
      # Add missing variables as needed
      {if (!has_year) mutate(., YEAR = default_year) else .} %>%
      {if (!has_race) mutate(., RACE = demo_info$race) else .} %>%
      {if (!has_sex) mutate(., SEX = demo_info$sex) else .} %>%
      # Select essential columns (now with clean names)
      select(LEAID, LEA_STATE, YEAR, RACE, SEX, pred, draw_id) %>%
      # Add model identifiers
      mutate(
        model_id = model_id,
        subgroup_id = subgroup_id,
        batch_num = batch
      )

    # Write to database
    if (create_table) {
      dbWriteTable(con, table_name, pred_batch, overwrite = TRUE)
      create_table <- FALSE
    } else {
      dbAppendTable(con, table_name, pred_batch)
    }

    # Progress indicator
    if (batch %% 5 == 0 || batch == n_batches) {
      cat("      Batch", batch, "of", n_batches, "completed\n")
    }

    # Clean up batch
    rm(pred_batch, data_batch)
    gc()
  }
}

#' Extract demographic info from model ID
parse_demographic_id <- function(model_id) {
  if (is.null(model_id) || !grepl("_", model_id)) {
    return(list(race = NA, sex = NA))
  }

  # Split on underscore and take first two parts
  parts <- strsplit(model_id, "_")[[1]]

  # Handle different ID formats
  if (length(parts) >= 2) {
    race <- parts[1]
    sex <- parts[2]
  } else {
    race <- NA
    sex <- NA
  }

  return(list(race = race, sex = sex))
}
#' Main function to process all targets
process_all_targets <- function(ndraws = 500, db_path = "export/db/crdc_arrests.duckdb") {

  # Connect to DuckDB
  con <- dbConnect(duckdb(), dbdir = db_path, read_only = FALSE)
  on.exit(dbDisconnect(con))

  # Define target names and their corresponding objects
  target_info <- list(
    nat_m1_mod = "nat_m1_mod",
    nat_m2_mod = "nat_m2_mod",
    sg_m1_mod = "sg_m1_mod",
    sg_m2_mod = "sg_m2_mod",
    sg_m3_mod = "sg_m3_mod",
    sg_m4_mod = "sg_m4_mod",
    sg_m5_mod = "sg_m5_mod"
  )

  create_table <- TRUE

  for (i in seq_along(target_info)) {
    target_name <- names(target_info)[i]
    cat("\n=== Processing target:", target_name, "===\n")

    # Load the target using targets
    target_obj <- targets::tar_read_raw(target_info[[i]])

    # Process the target
    process_target_draws(
      target_obj = target_obj,
      model_id = target_name,
      ndraws = ndraws,
      con = con,
      create_table = create_table
    )

    create_table <- FALSE  # Only create table on first iteration

    # Clean up
    rm(target_obj)
    gc()
  }

  # Create indices for efficient querying - CLEAN COLUMN NAMES
  cat("\nCreating database indices...\n")
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_composite_key ON predicted_draws (LEAID, LEA_STATE, YEAR, RACE, SEX)")
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_model_subgroup ON predicted_draws (model_id, subgroup_id)")
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_demographics ON predicted_draws (RACE, SEX)")
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_draw ON predicted_draws (draw_id)")
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_prediction ON predicted_draws (pred)")

  # Report final statistics
  result <- dbGetQuery(con, "SELECT COUNT(*) as total_rows FROM predicted_draws")
  model_counts <- dbGetQuery(con, "SELECT model_id, COUNT(*) as n_rows FROM predicted_draws GROUP BY model_id ORDER BY model_id")

  cat("\n=== Processing Complete ===\n")
  cat("Total rows:", format(result$total_rows, big.mark = ","), "\n")
  cat("Database size:", round(file.size(db_path) / 1e9, 2), "GB\n")
  cat("\nRows by model:\n")
  print(model_counts)
}
