#!/usr/bin/env Rscript
# Example: Automated CRDC Data Download
#
# This script demonstrates how to use the automated download functions
# to retrieve CRDC data files.

# Load the functions
source("R/funs.R")

# Example 1: Download a single year
# ----------------------------------
cat("\n=== Example 1: Download Single Year ===\n")

# First, install httr2 if needed
if (!requireNamespace("httr2", quietly = TRUE)) {
  cat("Installing httr2 package...\n")
  install.packages("httr2")
}

# Download 2021-22 data
tryCatch({
  result <- auto_download_crdc_data(
    year = "2021-22",
    dest_dir = "tmp/data",
    accept_terms = TRUE,  # You must explicitly accept terms
    overwrite = FALSE
  )

  cat("\nSuccess! Files extracted to:\n")
  cat("  Enrollment:", result$enrollment_path, "\n")
  cat("  Law Enforcement:", result$le_path, "\n")

}, error = function(e) {
  cat("\nError:", e$message, "\n")
  cat("Try manual download instead.\n")
})


# Example 2: Download all years
# ------------------------------
cat("\n\n=== Example 2: Download All Years ===\n")

years <- c("2021-22", "2017-18", "2015-16")
results <- list()

for (year in years) {
  cat("\n", strrep("-", 50), "\n")
  cat("Downloading", year, "...\n")
  cat(strrep("-", 50), "\n")

  tryCatch({
    result <- auto_download_crdc_data(
      year = year,
      dest_dir = "tmp/data",
      accept_terms = TRUE,
      overwrite = FALSE
    )
    results[[year]] <- result
    cat("✓ Success!\n")

  }, error = function(e) {
    cat("✗ Failed:", e$message, "\n")
  })
}

# Summary
cat("\n\n=== Download Summary ===\n")
cat("Successfully downloaded", length(results), "out of", length(years), "years\n")

if (length(results) > 0) {
  cat("\nExtracted files:\n")
  for (year in names(results)) {
    cat("\n", year, ":\n")
    cat("  Enrollment:", results[[year]]$enrollment_path, "\n")
    cat("  Law Enforcement:", results[[year]]$le_path, "\n")
  }
}


# Example 3: Manual download fallback
# ------------------------------------
cat("\n\n=== Example 3: Manual Download (if automated fails) ===\n")

# If automated download doesn't work, use manual download:
manual_example <- function() {
  # 1. Download files manually from https://civilrightsdata.ed.gov/data
  # 2. Save to ~/Downloads/
  # 3. Extract with:

  result <- download_crdc_data(
    year = "2021-22",
    zip_file = "~/Downloads/2021-22-crdc-data.zip",
    dest_dir = "tmp/data"
  )

  return(result)
}

cat("If automated download fails, use manual_example() function above\n")
cat("See README.md for detailed instructions\n")
