# Created by use_targets().
# Follow the comments below to fill in this target script.
# Then follow the manual to check and run the pipeline:
#   https://books.ropensci.org/targets/walkthrough.html#inspect-the-pipeline

# Load packages required to define the pipeline:
library(targets)
library(tarchetypes) # Load other packages as needed.
library(stantargets)
library(tibble)

# TODO: Document setting up cmdstanr / stantargets for reproducibility
# You may set up `mcmc` to have workers > 1, knowing that each worker will
# consume 8 CPU threads.

tar_option_set(
  packages = c("tibble", "brms", "dplyr", "knitr", "tidyr", "qs2", "quarto"), # packages that your targets need to run
  #error = "null"
   controller = crew::crew_controller_group(
    crew::crew_controller_local(name = "main", workers = 12L, garbage_collection = TRUE),   # For regular targets
    crew::crew_controller_local(name = "mcmc", workers = 1L, garbage_collection = TRUE) # FOR MCMC models
  ),
  storage="main",
  retrieval = "main",
  memory = "transient",
  garbage_collection = TRUE,
  seed = 11213,
  format = "rds" # default storage format
)



options(brms.threads = 2)
options(mc.cores = 12)
DEV_MODE <- TRUE

enroll_cap <- ifelse(DEV_MODE, 5000, 30)


# CRDC data paths
crdc_data <- tibble(
  year = c("21-22", "17-18", "15-16"),
  year_full = c("2021-22", "2017-18", "2015-16"),
  target_name = c("y2122", "y1718", "y1516"),
  ccd_year = c(2021, 2017, 2015),  # CCD years corresponding to CRDC years
  enrollment_path = c(
    "X:/datasets/ED/CRDC/2021-22-crdc-data/SCH/Enrollment.csv",
    "X:/datasets/ED/CRDC/2017-18-crdc-data-corrected-05242021/2017-18 Public-Use Files/Data/SCH/CRDC/CSV/Enrollment.csv",
    "X:/datasets/ED/CRDC/2015-16-crdc-data/Data Files and Layouts/CRDC 2015-16 School Data.csv"
  ),
  le_path = c(
    "X:/datasets/ED/CRDC/2021-22-crdc-data/SCH/Referrals and Arrests.csv",
    "X:/datasets/ED/CRDC/2017-18-crdc-data-corrected-05242021/2017-18 Public-Use Files/Data/SCH/CRDC/CSV/Referrals and Arrests.csv",
    "X:/datasets/ED/CRDC/2015-16-crdc-data/Data Files and Layouts/CRDC 2015-16 School Data.csv"
  )
)

future::plan(future.callr::callr)
tar_source("R/funs.R")
# Run the R scripts in the R/ folder with your custom functions:
#tar_source()

# TODO:
# Better Validate law enforcement referrals and arrests
# Better Validate reshaped data
# Make full model loop

list(
  # Data preparation loop to prepare and normalize CRDC files for
  # modeling.
   tar_map(
    values = crdc_data,
    names = "target_name",

    # CCD data targets matched to the year
    tar_target(ccd_dist_geo,
      ccd_dist_geo_data <- educationdata::get_education_data(level = "school-districts",
                                          source = "ccd",
                                          topic = "directory",
                                          filters = list(year = ccd_year),
                                          csv = TRUE)
    ),
    tar_target(ccd_sch_geo,
      ccd_sch_geo_data <- educationdata::get_education_data(level = "schools",
                                          source = "ccd",
                                          topic = "directory",
                                          filters = list(year = ccd_year),
                                          csv = TRUE)
    ),
      tar_target(crdc_raw, enrollment_path, format = "file"),
      tar_target(popcounts, read.csv(crdc_raw)),
      tar_target(schuniverse, get_crdc_sch_data(popcounts, year = year)),
      tar_target(schenrollraw, sch_denom_enroll(popcounts, year = year)),
      tar_target(incomplete_enroll, incomplete_enrollments(popcounts, year = year)),
      tar_target(enroll_validation, validate_enrollments(schenrollraw, year = year)),
      tar_target(crdc_le_raw, le_path, format = "file"),
      tar_target(lerefs, read.csv(crdc_le_raw)),
      tar_target(referrals, reshape_le(lerefs, year = year)),
      tar_target(combo, inner_join(referrals, schenrollraw)),
      tar_target(fullref_data, reshape_le_rate_long(combo, year = year)),
      tar_target(validate_mod_data, validate_le(fullref_data, year = year)),
      tar_target(model_data, left_join(schuniverse,
                                fullref_data,
                                by = join_by(COMBOKEY)))
  ),
  # Render the annual report for each year using tar_quarto_rep
  tarchetypes::tar_render_rep(
      name = annual_report,
      path = "annual_descriptives_template.qmd",
      params = crdc_data |> select(year_full, target_name) |>
          mutate(output_file = paste0("annual_descriptives_", year_full, ".html")),
      cue = tar_cue(mode = "never")
    ),
    # Combine model data from all years
  tar_target(combined_model_data,
    bind_rows(
        model_data_y2122,
        model_data_y1718,
        model_data_y1516
    )
    ),
    tar_target(combined_sch_data,
      bind_rows(
        ccd_sch_geo_y2122,
        ccd_sch_geo_y1718,
        ccd_sch_geo_y1516
      )
    ),
  # Render EDA document for combined data
  tarchetypes::tar_render(
    name = combined_eda,
    path = "combined_eda.qmd",
    output_file = "crdc_combined_three_year_eda_report.html"
  ),
  # Prep combined data for modeling
  tar_target(
    three_year_data, restrict_model_data(crdc_lea_collapse(combined_model_data),
                      enrollment_cap = enroll_cap)
  ),
  # Prep most recent year of data for modeling
    tar_target(
    recent_data, restrict_model_data(crdc_lea_collapse(combined_model_data),
                      enrollment_cap = enroll_cap, year = "21-22")
  ),

  # Define stan model files using BRMS to create the stan code
  tar_target(
      int_yr_mod,
      {
        writeLines(brms::make_stancode(
          ARRESTS | trials(stu_enroll) ~ 1 + YEAR + (1|LEAID),
          family = "binomial",
          data   = three_year_data,
          threads = brms::threading(2),
          prior = make_arrest_priors()
        ), "models/int_yr_only.stan")
      },
      format = "file"
    ),
  tar_target(
      int_yr_group_mod,
      {
        writeLines(brms::make_stancode(
          ARRESTS | trials(stu_enroll) ~ 1 + YEAR + RACE * SEX + (1|LEAID),
          family = "binomial",
          data   = three_year_data,
          threads = brms::threading(2),
          prior = make_arrest_priors()
        ), "models/int_yr_group.stan")
      },
      format = "file"
    ),
tar_target(
      int_yr_group_refrate_mod,
      {
        writeLines(brms::make_stancode(
          ARRESTS | trials(stu_enroll) ~ 1 + YEAR + RACE * SEX + referral_rate + (1|LEAID),
          family = "binomial",
          data   = three_year_data,
          threads = brms::threading(2),
          prior = make_arrest_priors()
        ), "models/int_yr_group_refrate.stan")
      },
      format = "file"
    ),
tar_target(
      int_yr_group_refrate_totrefs_mod,
      {
        writeLines(brms::make_stancode(
          ARRESTS | trials(stu_enroll) ~ 1 + YEAR + RACE * SEX + referral_rate + total_referrals + (1|LEAID),
          family = "binomial",
          data   = three_year_data,
          threads = brms::threading(2),
          prior = make_arrest_priors()
        ), "models/int_yr_group_refrate_totrefs.stan")
      },
      format = "file"
    ),

    tar_target(
      int_only_mod,
      {
        writeLines(brms::make_stancode(
          ARRESTS | trials(stu_enroll) ~ 1 + (1|LEAID),
          family = "binomial",
          data   = recent_data,
          threads = brms::threading(2),
          prior = make_arrest_priors()
        ), "models/int_only.stan")
      },
      format = "file"
    ),

    # Define stan-compatible data for modeling
    tar_target(
      three_year_data_stan,
      brms::make_standata(
        ARRESTS | trials(stu_enroll) ~ 1 + YEAR + RACE*SEX + referral_rate + total_referrals +  (1|LEAID),
          family = "binomial",
          data   = three_year_data,
          threads = brms::threading(2),
    ),
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),

  # Define stan-compatible data for modeling for the most recent year of data
    tar_target(
      recent_data_stan,
      brms::make_standata(
        ARRESTS | trials(stu_enroll) ~ 1 + (1|LEAID),
          family = "binomial",
          data   = recent_data,
          threads = brms::threading(2),
    ),
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
    ),

    # Fit 3 year models
    stantargets::tar_stan_mcmc(
        name = national_3yr,
        stan_files = list.files("models", "int_yr", full.names = TRUE),
        data = three_year_data_stan,
        chains = 4L,
        parallel_chains = 4L,
        threads_per_chain = 2L,
        iter_warmup = 1000L,
        iter_sampling = 2500L,
        dir = "models/exec",
        cpp_options = list(stan_threads = TRUE),
        seed = 11213L,
        resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
    ),

    # Fit most recent year models
    stantargets::tar_stan_mcmc(
        name = national_recent_yr,
        stan_files = "models/int_only.stan",
        data = recent_data_stan,
        chains = 4L,
        parallel_chains = 4L,
        threads_per_chain = 2L,
        iter_warmup = 1000L,
        iter_sampling = 2500L,
        dir = "models/exec",
        cpp_options = list(stan_threads = TRUE),
        seed = 11213L,
        resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
    ),
    #,

  #   # Demographic models using stantargets pattern

   tar_target(
      sg_int_yr_mod,
      {
        writeLines(brms::make_stancode(
          ARRESTS | trials(stu_enroll) ~ 1 + YEAR + (1|LEAID),
          family = "binomial",
          data   = three_year_data,
          threads = brms::threading(2),
          prior = make_arrest_priors()
        ),
          "models/demog/int_yr_only.stan")
      },
      format = "file"
    ),

    tar_target(
      sg_int_yr_refrate_mod,
      {
        writeLines(brms::make_stancode(
          ARRESTS | trials(stu_enroll) ~ 1 + YEAR + referral_rate + (1|LEAID),
          family = "binomial",
          data   = three_year_data,
          threads = brms::threading(2),
          prior = make_arrest_priors()
        ),
         "models/demog/int_yr_refrate.stan")
      },
      format = "file"
    ),

    tar_target(
      sg_int_yr_refrate_totrefs_mod,
      {
        writeLines(brms::make_stancode(
          ARRESTS | trials(stu_enroll) ~ 1 + YEAR + referral_rate + total_referrals + (1|LEAID),
          family = "binomial",
          data   = three_year_data,
          threads = brms::threading(2),
          prior = make_arrest_priors()
        ),
        "models/demog/int_yr_refrate_totrefs.stan")
      },
      format = "file"
    ),

  # # Use tar_stan_mcmc_rep for all subsets
  stantargets::tar_stan_mcmc_rep_summary(
    name = demographic_3yr_models,
    stan_files = list.files("models/demog", "int_yr", full.names = TRUE),
    data =  generate_demographic_data(three_year_data, n = 8), # Function that generates data for each rep
    batches = 8L,  # One batch per demographic subset
    reps = 1L,     # One rep per batch
    chains = 4L,
    parallel_chains = 4L,
    threads_per_chain = 2L,
    iter_warmup = 1000L,
    iter_sampling = 2500L,
    dir = "models/demog/exec",
    cpp_options = list(stan_threads = TRUE),
    seed = 11213L,
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),

     tar_target(
      sg_int_only_mod,
      {
        writeLines(brms::make_stancode(
          ARRESTS | trials(stu_enroll) ~ 1 + (1|LEAID),
          family = "binomial",
          data   = recent_data,
          threads = brms::threading(2),
          prior = make_arrest_priors()
        ),
          "models/demog/int_only.stan")
      },
      format = "file"
    ),

    tar_target(
      sg_int_only_refrate_mod,
      {
        writeLines(brms::make_stancode(
          ARRESTS | trials(stu_enroll) ~ 1 + referral_rate + (1|LEAID),
          family = "binomial",
          data   = recent_data,
          threads = brms::threading(2),
          prior = make_arrest_priors()
        ),
         "models/demog/int_only_refrate.stan")
      },
      format = "file"
    ),

    tar_target(
      sg_int_only_refrate_totrefs_mod,
      {
        writeLines(brms::make_stancode(
          ARRESTS | trials(stu_enroll) ~ 1 + referral_rate + total_referrals + (1|LEAID),
          family = "binomial",
          data   = recent_data,
          threads = brms::threading(2),
          prior = make_arrest_priors()
        ), "models/demog/int_only_refrate_totrefs.stan")
      },
      format = "file"
    ),

   stantargets::tar_stan_mcmc_rep_summary(
    name = demographic_recent_models,
    stan_files = list.files("models/demog", "int_only", full.names = TRUE),
    data =  generate_demographic_data(data = recent_data, n = 8), # Function that generates data for each rep
    batches = 8L,  # One batch per demographic subset
    reps = 1L,     # One rep per batch
    chains = 4L,
    parallel_chains = 4L,
    threads_per_chain = 2L,
    iter_warmup = 1000L,
    iter_sampling = 2500L,
    dir = "models/demog/exec",
    cpp_options = list(stan_threads = TRUE),
    seed = 11213L,
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  )

)
