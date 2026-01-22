#!/usr/bin/env Rscript
# Script to automatically download and extract CRDC data files
#
# This script automates the download and extraction of CRDC data files
# from https://civilrightsdata.ed.gov/data
#
# Usage:
#   Option 1 (Automatic Download - Recommended):
#     Rscript download_crdc_files.R --auto
#
#   Option 2 (Manual Download):
#     1. Download the zip files manually from the CRDC website
#     2. Update the zip_file paths below to point to your downloaded files
#     3. Run: Rscript download_crdc_files.R --manual

# Load the functions
source("R/funs.R")

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
use_auto <- length(args) > 0 && args[1] == "--auto"
use_manual <- length(args) > 0 && args[1] == "--manual"

# If no arguments, ask user
if (length(args) == 0) {
  cat("\n=== CRDC Data Download Script ===\n")
  cat("Choose download method:\n")
  cat("  1. Automatic download (requires httr2 package)\n")
  cat("  2. Manual download (you download files first)\n\n")
  cat("Run with: Rscript download_crdc_files.R --auto\n")
  cat("       or: Rscript download_crdc_files.R --manual\n\n")
  stop("Please specify download method")
}

# Destination directory (relative to project root)
dest_dir <- "tmp/data"

# Years to process
years <- c("2021-22", "2017-18", "2015-16")

# Download and extract each year
results <- list()

if (use_auto) {
  cat("\n=== AUTOMATIC DOWNLOAD MODE ===\n")
  cat("This will attempt to download files directly from the CRDC website.\n")
  cat("Large files may take 10-30 minutes depending on your connection.\n\n")

  # Check for httr2
  if (!requireNamespace("httr2", quietly = TRUE)) {
    cat("ERROR: The httr2 package is required for automatic downloads.\n")
    cat("Install it with: install.packages('httr2')\n")
    cat("Or use manual download mode: Rscript download_crdc_files.R --manual\n")
    stop("httr2 package not installed")
  }

  for (year in years) {
    cat("\n", strrep("=", 60), "\n")
    cat("Processing year:", year, "\n")
    cat(strrep("=", 60), "\n\n")

    tryCatch({
      result <- auto_download_crdc_data(
        year = year,
        dest_dir = dest_dir,
        accept_terms = TRUE,  # By running this script, user accepts terms
        overwrite = FALSE
      )
      results[[year]] <- result
      cat("\n✓ Successfully processed", year, "\n")
    }, error = function(e) {
      cat("\n✗ Error processing", year, ":", e$message, "\n")
      cat("You may need to download this year manually.\n")
    })
  }

} else if (use_manual) {
  cat("\n=== MANUAL DOWNLOAD MODE ===\n")
  cat("Please ensure you have downloaded the zip files first.\n\n")

  # Define paths to manually downloaded zip files
  zip_files <- list(
    "2021-22" = "~/Downloads/2021-22-crdc-data.zip",
    "2017-18" = "~/Downloads/2017-18-crdc-data-corrected-05242021.zip",
    "2015-16" = "~/Downloads/2015-16-crdc-data.zip"
  )

  for (year in names(zip_files)) {
    cat("\n", strrep("=", 60), "\n")
    cat("Processing year:", year, "\n")
    cat(strrep("=", 60), "\n\n")

    zip_path <- zip_files[[year]]

    # Check if zip file exists
    if (!file.exists(zip_path)) {
      cat("WARNING: Zip file not found:", zip_path, "\n")
      cat("Please download it from https://civilrightsdata.ed.gov/data\n")
      cat("Skipping", year, "\n")
      next
    }

    # Extract the data
    tryCatch({
      result <- download_crdc_data(
        year = year,
        dest_dir = dest_dir,
        zip_file = zip_path,
        overwrite = FALSE
      )
      results[[year]] <- result
      cat("\n✓ Successfully processed", year, "\n")
    }, error = function(e) {
      cat("\n✗ Error processing", year, ":", e$message, "\n")
    })
  }
}

# Print summary
cat("\n", strrep("=", 60), "\n")
cat("SUMMARY\n")
cat(strrep("=", 60), "\n\n")

if (length(results) > 0) {
  cat("Successfully extracted", length(results), "year(s) of data:\n\n")

  for (year in names(results)) {
    cat("Year:", year, "\n")
    cat("  Enrollment:", results[[year]]$enrollment_path, "\n")
    cat("  Law Enforcement:", results[[year]]$le_path, "\n\n")
  }

  cat("\nNext steps:\n")
  cat("1. Verify the extracted files are correct\n")
  cat("2. The paths in _targets.R should already match these locations\n")
  cat("3. Run the targets pipeline: targets::tar_make()\n")
} else {
  cat("No files were successfully extracted.\n")
  cat("Please check the zip file paths and try again.\n")
}
