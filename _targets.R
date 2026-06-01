# ---------------------------------------------------------------------------------------------
# Title: Build CRDC Arrest Rate Models
# Author: Jared Knowles, Civilytics Consulting
# Date: 05/05/2025
# Last Edited: 05/31/2026
# ------------------------------------------------------------------------------

# Load libraries ---------------------------------------------------------
library(targets)
library(tarchetypes) # Load other packages as needed.
library(tibble)

# Define computational resources  ---------------------------------------------
#
# SIZING — the full pipeline fits many large Bayesian models and takes ~DAYS even
# on a 24-core / 128 GB machine. The dominant tradeoff is MCMC parallelism x RAM:
#   peak RAM  ~=  (chains running in parallel) x (per-chain data + sampler footprint)
# To fit a smaller machine, REDUCE concurrency (fewer parallel chains) and/or raise
# threads-per-chain so each chain finishes faster while fewer run at once:
#   * NCHAINS   — chains per model (4 is the published setting).
#   * NTHREADS  — within-chain threads. nthreads==nchains => one sampling pass.
#   * N_PAR_CHAINS / MCMC_WORKERS — how many chains/models run concurrently.
# Lower CRDC_CORES (or set CRDC_NTHREADS higher) if you hit memory pressure. See
# REPRODUCIBILITY.md for a cores x RAM sizing table.
# All three are env-overridable so you need not edit this file to size a run.

CPU_CAPACITY <- {
  v <- suppressWarnings(as.integer(Sys.getenv("CRDC_CORES", "")))
  if (is.na(v) || v < 1) parallel::detectCores(logical = FALSE) else v
}

# The number of threads is per brms model. When NTHREADS == NCHAINS the model
# completes in one pass; if NTHREADS < NCHAINS it needs another sampling pass.
# This may be necessary on memory-constrained devices.
NTHREADS <- {
  v <- suppressWarnings(as.integer(Sys.getenv("CRDC_NTHREADS", "4"))); if (is.na(v) || v < 1) 4L else v
}
NCHAINS <- {
  v <- suppressWarnings(as.integer(Sys.getenv("CRDC_NCHAINS", "4"))); if (is.na(v) || v < 1) 4L else v
}
# Number of chains that can run in parallel given the core budget.
N_PAR_CHAINS <- CPU_CAPACITY %/% NTHREADS

# DEV_MODE greatly reduces runtime to confirm the pipeline works end-to-end before
# committing to the full multi-day run. Toggle WITHOUT editing this file:
#   CRDC_DEV_MODE=true Rscript -e 'targets::tar_make(...)'   (see scripts/smoke-pipeline.sh)
DEV_MODE <- isTRUE(as.logical(Sys.getenv("CRDC_DEV_MODE", "FALSE")))
# Set the global limit on how many students must be enrolled to be included in
# the model. The final report used 30 students total per LEA as the threshold.
# When in DEV_MODE this is greatly increased.
enroll_cap <- ifelse(DEV_MODE, 5000, 30)
NITER <- ifelse(DEV_MODE, 500, 3500)
ITER_MULTIPLIER <- 2L

# This normalizes the number of workers available for fitting models, which are
# listed as MCMC workers. We limit the number of MCMC workers to avoid
# parallelization explosion in the code.
if (N_PAR_CHAINS > NCHAINS) {
  MCMC_WORKERS <- N_PAR_CHAINS %/% NCHAINS
  N_PAR_CHAINS <- NCHAINS
} else {
  MCMC_WORKERS <- 1
}

# Set pipeline rules  ---------------------------------------------------------
# Set the options for the targets pipeline to work including loading key packages
# and setting up the parallelization strategy
tar_option_set(
  packages = c("tibble", "brms", "dplyr", "knitr", "tidyr", "qs2", "quarto"),
  controller = crew::crew_controller_group(
    crew::crew_controller_local(
      name = "main",
      workers = CPU_CAPACITY,
      garbage_collection = TRUE
    ), # For regular targets
    crew::crew_controller_local(
      name = "mcmc",
      workers = MCMC_WORKERS,
      garbage_collection = TRUE
    ) # FOR MCMC models
  ),
  storage = "main",
  retrieval = "main",
  memory = "transient",
  garbage_collection = TRUE,
  seed = 11213, # <-- <-- Set your own seed here
  format = "rds" # default storage format
)

# Set MCMC options  ---------------------------------------------------------
# Set package specific options
options(brms.threads = NTHREADS)
options(mc.cores = CPU_CAPACITY)

# Set MCMC parameters for STAN sampling to ensure convergence
mod_control <- list(adapt_delta = 0.875, max_treedepth = 12L)


# Define data paths  ---------------------------------------------------------
# Tell targets where to find the source data from CRDC
crdc_data <- tibble(
    year = c("21-22", "17-18", "15-16"),
    year_full = c("2021-22", "2017-18", "2015-16"),
    target_name = c("y2122", "y1718", "y1516"),
    ccd_year = c(2021, 2017, 2015), # CCD years corresponding to CRDC years
    enrollment_path = c(
      "tmp/data/2021-22-crdc-data/SCH/Enrollment.csv",
      "tmp/data/2017-18-crdc-data-corrected-05242021/2017-18 Public-Use Files/Data/SCH/CRDC/CSV/Enrollment.csv",
      "tmp/data/2015-16-crdc-data/Data Files and Layouts/CRDC 2015-16 School Data.csv"
    ),
    le_path = c(
      "tmp/data/2021-22-crdc-data/SCH/Referrals and Arrests.csv",
      "tmp/data/2017-18-crdc-data-corrected-05242021/2017-18 Public-Use Files/Data/SCH/CRDC/CSV/Referrals and Arrests.csv",
      "tmp/data/2015-16-crdc-data/Data Files and Layouts/CRDC 2015-16 School Data.csv"
    )
  )

# Set up futures and load required functions
future::plan(future.callr::callr)
tar_source("R/funs.R")
# Read in postprocessing functions
tar_source("R/postprocess.R")
tar_source("R/district_dim.R")
tar_source("R/summarize_draws.R")
tar_source("R/export_parquet.R")
tar_source("R/build_api_artifacts.R")
# Define the targets pipeline
# The pipeline proceeds in two stages, the first stage processes the CRDC data
# for each year and combines all of the enrollment and law enforcement referral
# data into a longitudinal file suitable for modeling. There are custom functions
# that are applied to process the files and normalize the data as well as apply
# business rules to address data quality challenges. These are documented in the
# paper and are also discussed in the EDA reports.

list(
  # Data preparation loop to prepare and normalize CRDC files for
  # modeling. This code loops over each entry in crdc_data above and can be run
  # in parallel
  tar_map(
    values = crdc_data,
    names = "target_name",
    # Get CCD data to join with CRDC data for things like names and district locations
    tar_target(
      ccd_dist_geo,
      ccd_dist_geo_data <- educationdata::get_education_data(
        level = "school-districts",
        source = "ccd",
        topic = "directory",
        filters = list(year = ccd_year),
        csv = TRUE
      )
    ),
    tar_target(
      ccd_sch_geo,
      ccd_sch_geo_data <- educationdata::get_education_data(
        level = "schools",
        source = "ccd",
        topic = "directory",
        filters = list(year = ccd_year),
        csv = TRUE
      )
    ),
    tar_target(crdc_raw, enrollment_path, format = "file"),
    tar_target(popcounts, read.csv(crdc_raw)),
    tar_target(schuniverse, get_crdc_sch_data(popcounts, year = year)),
    tar_target(schenrollraw, sch_denom_enroll(popcounts, year = year)),
    tar_target(
      incomplete_enroll,
      incomplete_enrollments(popcounts, year = year)
    ),
    tar_target(
      enroll_validation,
      validate_enrollments(schenrollraw, year = year)
    ),
    tar_target(crdc_le_raw, le_path, format = "file"),
    tar_target(lerefs, read.csv(crdc_le_raw)),
    tar_target(referrals, reshape_le(lerefs, year = year)),
    tar_target(combo, inner_join(referrals, schenrollraw)),
    tar_target(fullref_data, reshape_le_rate_long(combo, year = year)),
    tar_target(validate_mod_data, validate_le(fullref_data, year = year)),
    tar_target(
      full_crdc_data,
      left_join(schuniverse, fullref_data, by = join_by(COMBOKEY))
    ),
    tar_target(
      model_data,
      intersect_crdc_ccd(crdc = full_crdc_data, ccd = ccd_sch_geo)
    )
  ),
  # Render the annual report for each year using tar_quarto_rep
  # tarchetypes::tar_render_rep(
  #     name = annual_report,
  #     path = "annual_descriptives_template.qmd",
  #     params = crdc_data |> select(year_full, target_name) |>
  #         mutate(output_file = paste0("annual_descriptives_", year_full, ".html")),
  #     cue = tar_cue(mode = "never")
  #   ),
  # Combine model data from all years
  tar_target(
    combined_model_data,
    bind_rows(
      model_data_y2122,
      model_data_y1718,
      model_data_y1516
    )
  ),
  tar_target(
    combined_sch_data,
    bind_rows(
      ccd_sch_geo_y2122,
      ccd_sch_geo_y1718,
      ccd_sch_geo_y1516
    )
  ),
  # # Render EDA document for combined data
  # tarchetypes::tar_render(
  #   name = combined_eda,
  #   path = "combined_eda.qmd",
  #   output_file = "crdc_combined_three_year_eda_report.html"
  # ),
  # Prep combined data for modeling
  tar_target(
    three_year_data,
    restrict_model_data(
      crdc_lea_collapse(combined_model_data),
      enrollment_cap = enroll_cap,
      dev_mode = DEV_MODE
    )
  ),
  # Prep most recent year of data for modeling
  tar_target(
    recent_data,
    restrict_model_data(
      crdc_lea_collapse(combined_model_data),
      enrollment_cap = enroll_cap,
      year = "21-22",
      dev_mode = DEV_MODE
    )
  ),

  tar_target(
    nat_m1_fml,
    brms::brmsformula(
      ARRESTS | trials(stu_enroll) ~ 1 +
        RACE * SEX +
        (1 | LEAID) +
        (1 | LEA_STATE),
      family = "binomial"
    )
  ),

  tar_target(
    nat_m1_mod,
    brm(
      nat_m1_fml,
      data = recent_data$data,
      seed = 11213,
      prior = make_arrest_priors(),
      sample_prior = TRUE,
      iter = NITER,
      thin = 1,
      chains = NCHAINS,
      cores = NCHAINS,
      threads = threading(NTHREADS, static = TRUE),
      backend = "cmdstanr"
    ),
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),

  tar_target(
    nat_m2_fml,
    brms::brmsformula(
      ARRESTS | trials(stu_enroll) ~ 1 +
        RACE * SEX +
        referral_rate +
        (1 | LEAID) +
        (1 | LEA_STATE),
      family = "binomial"
    )
  ),

  tar_target(
    nat_m2_mod,
    brm(
      nat_m2_fml,
      data = recent_data$data,
      seed = 11213,
      prior = make_arrest_priors(),
      sample_prior = TRUE,
      iter = NITER,
      thin = 1,
      control = mod_control,
      chains = NCHAINS,
      cores = NCHAINS,
      threads = threading(NTHREADS, static = TRUE),
      backend = "cmdstanr"
    ),
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),

  tar_target(
    nat_m3_fml,
    brms::brmsformula(
      ARRESTS | trials(stu_enroll) ~ 1 +
        YEAR +
        RACE * SEX +
        (1 | LEAID) +
        (1 | LEA_STATE),
      family = "binomial"
    )
  ),

  tar_target(
    nat_m3_mod,
    brm(
      nat_m3_fml,
      data = three_year_data$data,
      seed = 11213,
      prior = make_arrest_priors(),
      sample_prior = TRUE,
      iter = NITER,
      thin = 1,
      control = mod_control,
      chains = NCHAINS,
      cores = NCHAINS,
      threads = threading(NTHREADS, static = TRUE),
      backend = "cmdstanr"
    ),
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),

  tar_target(
    nat_m4_fml,
    brms::brmsformula(
      ARRESTS | trials(stu_enroll) ~ 1 +
        YEAR +
        RACE * SEX +
        referral_rate +
        (1 | LEAID) +
        (1 | LEA_STATE),
      family = "binomial"
    )
  ),

  tar_target(
    nat_m4_mod,
    brm(
      nat_m4_fml,
      data = three_year_data$data,
      seed = 11213,
      prior = make_arrest_priors(),
      sample_prior = TRUE,
      iter = NITER + 500,
      thin = ITER_MULTIPLIER,
      control = mod_control,
      chains = NCHAINS,
      cores = NCHAINS,
      threads = threading(NTHREADS, static = TRUE),
      backend = "cmdstanr"
    ),
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),

  tar_target(
    nat_m5_fml,
    brms::brmsformula(
      ARRESTS | trials(stu_enroll) ~ 1 +
        YEAR +
        RACE * SEX +
        referral_rate +
        total_referrals +
        (1 | LEAID) +
        (1 | LEA_STATE),
      family = "binomial"
    )
  ),

  tar_target(
    nat_m5_mod,
    brm(
      nat_m5_fml,
      data = three_year_data$data,
      seed = 11213,
      prior = make_arrest_priors(),
      sample_prior = TRUE,
      iter = NITER + 500,
      thin = ITER_MULTIPLIER,
      control = mod_control,
      chains = NCHAINS,
      cores = NCHAINS,
      threads = threading(NTHREADS, static = TRUE),
      backend = "cmdstanr"
    ),
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),

  tar_target(
    recent_data_group,
    generate_demographic_data(recent_data$data) |>
      dplyr::group_by(group) |>
      targets::tar_group(),
    iteration = "group"
  ),

  tar_target(
    three_year_data_group,
    generate_demographic_data(three_year_data$data) |>
      dplyr::group_by(group) |>
      targets::tar_group(),
    iteration = "group"
  ),

  tar_target(
    sg_m1_fml,
    brms::brmsformula(
      ARRESTS | trials(stu_enroll) ~ 1 + (1 | LEA_STATE) + (1 | LEAID),
      family = "binomial"
    )
  ),

  tar_target(
    sg_m1_mod,
    command = {
      obj <- brm(
        sg_m1_fml,
        data = recent_data_group,
        seed = 11213,
        prior = make_arrest_priors(int_only = TRUE),
        sample_prior = TRUE,
        iter = (500 + NITER) %/% 2,
        chains = NCHAINS,
        cores = NCHAINS,
        threads = threading(NTHREADS, static = TRUE),
        backend = "cmdstanr"
      )
      obj$id <- recent_data_group$group[1] # we need to label the group here
      obj
    },
    pattern = map(recent_data_group),
    iteration = "list",
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),

  tar_target(
    sg_m2_fml,
    brms::brmsformula(
      ARRESTS | trials(stu_enroll) ~ 1 +
        referral_rate +
        (1 | LEA_STATE) +
        (1 | LEAID),
      family = "binomial"
    )
  ),

  tar_target(
    sg_m2_mod,
    command = {
      obj <- brm(
        sg_m2_fml,
        data = recent_data_group,
        seed = 11213,
        prior = make_arrest_priors(),
        sample_prior = TRUE,
        iter = NITER,
        chains = NCHAINS,
        cores = NCHAINS,
        threads = threading(NTHREADS, static = TRUE),
        backend = "cmdstanr"
      )
      obj$id <- recent_data_group$group[1] # we need to label the group here
      obj
    },
    pattern = map(recent_data_group),
    iteration = "list",
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),

  tar_target(
    sg_m3_fml,
    brms::brmsformula(
      ARRESTS | trials(stu_enroll) ~ 1 + YEAR + (1 | LEA_STATE) + (1 | LEAID),
      family = "binomial"
    )
  ),

  tar_target(
    sg_m3_mod,
    command = {
      obj <- brm(
        sg_m3_fml,
        data = three_year_data_group,
        seed = 11213,
        prior = make_arrest_priors(),
        sample_prior = TRUE,
        iter = NITER,
        thin = ITER_MULTIPLIER,
        chains = NCHAINS,
        cores = NCHAINS,
        threads = threading(NTHREADS, static = TRUE),
        backend = "cmdstanr"
      )
      obj$id <- three_year_data_group$group[1] # we need to label the group here
      obj
    },
    pattern = map(three_year_data_group),
    iteration = "list",
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),

  tar_target(
    sg_m4_fml,
    brms::brmsformula(
      ARRESTS | trials(stu_enroll) ~ 1 +
        YEAR +
        referral_rate +
        (1 | LEA_STATE) +
        (1 | LEAID),
      family = "binomial"
    )
  ),

  tar_target(
    sg_m4_mod,
    command = {
      obj <- brm(
        sg_m4_fml,
        data = three_year_data_group,
        seed = 11213,
        prior = make_arrest_priors(),
        sample_prior = TRUE,
        iter = NITER + 800,
        thin = ITER_MULTIPLIER,
        chains = NCHAINS,
        cores = NCHAINS,
        control = mod_control,
        threads = threading(NTHREADS, static = TRUE),
        backend = "cmdstanr"
      )
      obj$id <- three_year_data_group$group[1] # we need to label the group here
      obj
    },
    pattern = map(three_year_data_group),
    iteration = "list",
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),

  tar_target(
    sg_m5_fml,
    brms::brmsformula(
      ARRESTS | trials(stu_enroll) ~ 1 +
        YEAR +
        referral_rate +
        total_referrals +
        (1 | LEA_STATE) +
        (1 | LEAID),
      family = "binomial"
    )
  ),

  tar_target(
    sg_m5_mod,
    command = {
      obj <- brm(
        sg_m5_fml,
        data = three_year_data_group,
        seed = 11213,
        prior = make_arrest_priors(),
        sample_prior = TRUE,
        iter = NITER + 500,
        thin = ITER_MULTIPLIER,
        chains = NCHAINS,
        cores = NCHAINS,
        control = mod_control,
        threads = threading(NTHREADS, static = TRUE),
        backend = "cmdstanr"
      )
      obj$id <- three_year_data_group$group[1] # we need to label the group here
      obj
    },
    pattern = map(three_year_data_group),
    iteration = "list",
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),
  tar_target(
    posterior_db,
    process_all_targets(ndraws = 500, db_path = "export/db/crdc_arrests.duckdb")
  ),

  # --- API data product targets -------------------------------------------
  tar_target(
    combined_dist_geo,
    list(ccd_dist_geo_y2122, ccd_dist_geo_y1718, ccd_dist_geo_y1516)
  ),
  tar_target(
    district_dim,
    build_district_dim(combined_dist_geo)
  ),
  # enrollment denominator + observed arrests per (LEAID, YEAR, RACE, SEX)
  tar_target(
    enroll_lookup,
    dplyr::distinct(dplyr::select(
      dplyr::bind_rows(recent_data$data, three_year_data$data),
      LEAID, YEAR, RACE, SEX, stu_enroll,
      observed_arrests = ARRESTS))
  ),
  # arrest_summary + state_summary materialized into the API DuckDB.
  # depends on posterior_db so the draws DB exists.
  tar_target(
    api_db,
    {
      posterior_db  # force dependency on the draws DB build
      build_api_db(
        draws_db_path = "export/db/crdc_arrests.duckdb",
        api_path      = "export/api/crdc_api.duckdb",
        enroll_lookup = enroll_lookup,
        district_dim  = district_dim,
        data_release  = "civilytics-crdc-arrests-2025.1",
        memory_limit  = sprintf("%dGB", duckdb_mem_limit_gb()),
        threads       = 6,
        temp_dir      = "tmp/duckdb_spill"
      )
    },
    format = "file"
  ),
  tar_target(
    draws_parquet,
    {
      posterior_db
      build_draws_parquet(
        draws_db_path = "export/db/crdc_arrests.duckdb",
        out_dir       = "export/parquet",
        memory_limit  = sprintf("%dGB", duckdb_mem_limit_gb()),
        threads       = 6,
        temp_dir      = "tmp/duckdb_spill"
      )
    },
    format = "file"
  )

  # Hypothetical Model 6 specification. Not run. Run attempted in September 2025
  # but was canceled after 7 days of continuous compute failed to produce results.
  #,
  #     tar_target(nat_m6_fml,
  #   brms::brmsformula(
  #     ARRESTS | trials(stu_enroll) ~ 1 + YEAR + RACE * SEX + referral_rate + total_referrals + (1 + RACE * SEX |LEAID)  + (1|LEA_STATE),
  #     family = "binomial"
  #   )
  # ),
  # tar_target(
  #   nat_m6_mod,
  #   brm(nat_m6_fml,
  #     data = three_year_data$data,
  #       seed = 11213,
  #   prior = make_arrest_priors(),
  #   sample_prior = TRUE,
  #   iter = NITER + 500,
  #   thin = ITER_MULTIPLIER,
  #   control =  mod_control,
  #   chains = NCHAINS,
  #   cores = NCHAINS,
  #   threads = threading(NTHREADS, static = TRUE),
  #   backend = "cmdstanr"
  # ),
  # resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  # )
)
