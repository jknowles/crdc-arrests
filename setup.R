#!/usr/bin/env Rscript
# One-time environment bootstrap for the CRDC arrests pipeline.
# Run once from a fresh clone:  source("setup.R")  (or: Rscript setup.R)
# Restores the locked R library, installs/points to CmdStan 2.37.0, and runs
# sanity checks. Does NOT fit any models — see scripts/smoke-pipeline.sh for that.

message("== CRDC pipeline setup ==")

## 1. Restore the locked R package library --------------------------------
if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", repos = "https://cloud.r-project.org")
}
message("[1/3] renv::restore() — restoring locked library (may take a while on first run)")
renv::restore(prompt = FALSE)

## 2. Install / verify CmdStan 2.37.0 -------------------------------------
message("[2/3] CmdStan 2.37.0")
if (!requireNamespace("cmdstanr", quietly = TRUE)) {
  install.packages("cmdstanr",
                   repos = c("https://stan-dev.r-universe.dev", getOption("repos")))
}
have_cmdstan <- tryCatch(!is.null(cmdstanr::cmdstan_version(error_on_NA = FALSE)),
                         error = function(e) FALSE)
if (!have_cmdstan) {
  cmdstanr::install_cmdstan(version = "2.37.0")
  # Native-tuned build (matches the published environment).
  cpp_options <- list(
    "CXXFLAGS += -march=native -mtune=native -DEIGEN_USE_BLAS -DEIGEN_USE_LAPACKE",
    "LDLIBS += -lblas -llapack -llapacke")
  cmdstanr::cmdstan_make_local(cpp_options = cpp_options, append = TRUE)
  cmdstanr::rebuild_cmdstan()
} else {
  message("    CmdStan already present: ", cmdstanr::cmdstan_path())
}

## 3. Sanity checks --------------------------------------------------------
message("[3/3] sanity checks")
stopifnot(requireNamespace("tarchetypes", quietly = TRUE))   # pipeline can be sourced
local({
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  stopifnot(DBI::dbGetQuery(con, "SELECT 1 AS ok")$ok == 1)   # DuckDB round-trip
})
ok_edu <- requireNamespace("educationdata", quietly = TRUE)  # CCD pulls (non-fatal)
if (!ok_edu) message("    NOTE: educationdata not available — CCD directory pulls will fail.")

message("== Setup complete. Validate with: scripts/smoke-pipeline.sh ==")
