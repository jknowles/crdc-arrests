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

CPU_CAPACITY <- 32
#parallel::detectCores()
NTHREADS <- 4
NCHAINS <- 4
N_PAR_CHAINS <- CPU_CAPACITY %/% NTHREADS

DEV_MODE <- FALSE
enroll_cap <- ifelse(DEV_MODE, 5000, 30)
NITER <- ifelse(DEV_MODE, 500, 4000)
ITER_MULTIPLIER <- 2L


if (N_PAR_CHAINS > NCHAINS) {
  MCMC_WORKERS <- N_PAR_CHAINS %/% NCHAINS
  N_PAR_CHAINS <- NCHAINS
} else {
  MCMC_WORKERS <- 1
}

tar_option_set(
  packages = c("tibble", "brms", "dplyr", "knitr", "tidyr", "qs2", "quarto"), # packages that your targets need to run
  #error = "null"
   controller = crew::crew_controller_group(
    crew::crew_controller_local(name = "main", workers = CPU_CAPACITY, garbage_collection = TRUE),   # For regular targets
    crew::crew_controller_local(name = "mcmc", workers = MCMC_WORKERS, garbage_collection = TRUE) # FOR MCMC models
  ),
  storage="main",
  retrieval = "main",
  memory = "transient",
  garbage_collection = TRUE,
  seed = 11213,
  format = "rds" # default storage format
)



options(brms.threads = NTHREADS)
options(mc.cores = CPU_CAPACITY)


# TODO: Consider increasing this
# TODO: Revisit the total_referrals formula component because it is collinear
# with the LEAID term
# Remove total_referrals from 1 year model (it is collinear with the intercept)
# Log total_referrals for the three year models log1p(total_referrals)
# three_year_data$data <- three_year_data$data %>%
  #mutate(
   # totref_log = log1p(total_referrals),      # log(1 + x)
    #totref_std = scale(totref_log)[,1]        # mean‑0, sd‑1
  #)
mod_control <- list(adapt_delta = 0.875,
                    max_treedepth = 12L)

if (Sys.info()["sysname"] %in%  c("Darwin", "Linux")) {
  # CRDC data paths
crdc_data <- tibble(
  year = c("21-22", "17-18", "15-16"),
  year_full = c("2021-22", "2017-18", "2015-16"),
  target_name = c("y2122", "y1718", "y1516"),
  ccd_year = c(2021, 2017, 2015),  # CCD years corresponding to CRDC years
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
} else {
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
}


future::plan(future.callr::callr)
tar_source("R/funs.R")


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
      tar_target(full_crdc_data, left_join(schuniverse,
                                fullref_data,
                                by = join_by(COMBOKEY))),
      tar_target(model_data, intersect_crdc_ccd(crdc = full_crdc_data, ccd = ccd_sch_geo))
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
  # # Render EDA document for combined data
  # tarchetypes::tar_render(
  #   name = combined_eda,
  #   path = "combined_eda.qmd",
  #   output_file = "crdc_combined_three_year_eda_report.html"
  # ),
  # Prep combined data for modeling
  tar_target(
    three_year_data, restrict_model_data(crdc_lea_collapse(combined_model_data),
                      enrollment_cap = enroll_cap, dev_mode = DEV_MODE)
  ),
  # Prep most recent year of data for modeling
    tar_target(
    recent_data, restrict_model_data(crdc_lea_collapse(combined_model_data),
                      enrollment_cap = enroll_cap, year = "21-22", dev_mode = DEV_MODE )
  ),


  tar_target(
    nat_m1_fml,
    brms::brmsformula(ARRESTS | trials(stu_enroll) ~ 1 + RACE*SEX +  (1|LEAID)  + (1|LEA_STATE),
          family = "binomial")
  ),

  tar_target(
    nat_m1_mod,
    brm(nat_m1_fml,
    data = recent_data$data,
    seed = 11213,
    prior = make_arrest_priors(),
    sample_prior = TRUE,
    iter = NITER %/% 2, # we need fewer here
    thin = 1,
    chains = NCHAINS,
    cores = NCHAINS,
    threads = threading(NTHREADS, static = TRUE),
    backend = "cmdstanr"
    ),
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),


  tar_target(nat_m2_fml,
    brms::brmsformula(
      ARRESTS | trials(stu_enroll) ~ 1 + RACE * SEX + referral_rate + (1|LEAID)  + (1|LEA_STATE),
      family = "binomial"
    )
  ),

  tar_target(
    nat_m2_mod,
    brm(nat_m2_fml,
      data = recent_data$data,
        seed = 11213,
    prior = make_arrest_priors(),
    sample_prior = TRUE,
    iter = NITER,
    thin = 1,
    control =  mod_control,
    chains = NCHAINS,
    cores = NCHAINS,
    threads = threading(NTHREADS, static = TRUE),
    backend = "cmdstanr"
  ),
  resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),

    tar_target(nat_m3_fml,
    brms::brmsformula(
      ARRESTS | trials(stu_enroll) ~ 1 + YEAR + RACE * SEX + (1|LEAID)  + (1|LEA_STATE),
      family = "binomial"
    )
  ),

  tar_target(
    nat_m3_mod,
    brm(nat_m3_fml,
      data = three_year_data$data,
        seed = 11213,
    prior = make_arrest_priors(),
    sample_prior = TRUE,
    iter = NITER,
    thin = 1,
    control =  mod_control,
    chains = NCHAINS,
    cores = NCHAINS,
    threads = threading(NTHREADS, static = TRUE),
    backend = "cmdstanr"
  ),
  resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),


    tar_target(nat_m4_fml,
    brms::brmsformula(
      ARRESTS | trials(stu_enroll) ~ 1 + YEAR + RACE * SEX + referral_rate + (1|LEAID)  + (1|LEA_STATE),
      family = "binomial"
    )
  ),

  tar_target(
    nat_m4_mod,
    brm(nat_m4_fml,
      data = three_year_data$data,
        seed = 11213,
    prior = make_arrest_priors(),
    sample_prior = TRUE,
    iter = NITER * ITER_MULTIPLIER,
    thin = ITER_MULTIPLIER,
    control =  mod_control,
    chains = NCHAINS,
    cores = NCHAINS,
    threads = threading(NTHREADS, static = TRUE),
    backend = "cmdstanr"
  ),
  resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
  ),

  tar_target(nat_m5_fml,
    brms::brmsformula(
      ARRESTS | trials(stu_enroll) ~ 1 + YEAR + RACE * SEX + referral_rate + total_referrals + (1|LEAID)  + (1|LEA_STATE),
      family = "binomial"
    )
  ),

  tar_target(
    nat_m5_mod,
    brm(nat_m5_fml,
      data = three_year_data$data,
        seed = 11213,
    prior = make_arrest_priors(),
    sample_prior = TRUE,
    iter = NITER * ITER_MULTIPLIER,
    thin = ITER_MULTIPLIER,
    control =  mod_control,
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
     brms::brmsformula(ARRESTS | trials(stu_enroll) ~ 1 + (1|LEA_STATE) + (1|LEAID),
           family = "binomial")
  ),


  tar_target(
    sg_m1_mod,
    command =
      {
      obj <- brm(
        sg_m1_fml,
      data = recent_data_group,
       seed = 11213,
    prior = make_arrest_priors(int_only = TRUE),
    sample_prior = TRUE,
    iter = NITER,
    chains = NCHAINS,
    cores = NCHAINS,
    threads = threading(NTHREADS, static = TRUE),
    backend = "cmdstanr")
    obj$id <- recent_data_group$group[1] # we need to label the group here
    obj
      }
        ,
    pattern = map(recent_data_group),
    iteration = "list",
    resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
    ),


  tar_target(
    sg_m2_fml,
     brms::brmsformula( ARRESTS | trials(stu_enroll) ~ 1 + referral_rate + (1|LEA_STATE) +  (1|LEAID),
           family = "binomial")
  ),

  tar_target(
      sg_m2_mod,
      command =
        {
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
      backend = "cmdstanr")
      obj$id <- recent_data_group$group[1] # we need to label the group here
      obj
        },
      pattern = map(recent_data_group),
      iteration = "list",
      resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
      ),

tar_target(
    sg_m3_fml,
     brms::brmsformula( ARRESTS | trials(stu_enroll) ~ 1 + YEAR + (1|LEA_STATE) + (1|LEAID),
           family = "binomial")
  ),

  tar_target(
      sg_m3_mod,
      command =
        {
        obj <- brm(
          sg_m3_fml,
        data = three_year_data_group,
        seed = 11213,
      prior = make_arrest_priors(),
      sample_prior = TRUE,
      iter = NITER,
      chains = NCHAINS,
      cores = NCHAINS,
      threads = threading(NTHREADS, static = TRUE),
      backend = "cmdstanr")
      obj$id <- three_year_data_group$group[1] # we need to label the group here
      obj
        }
          ,
      pattern = map(three_year_data_group),
      iteration = "list",
      resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
      ),


  tar_target(
    sg_m4_fml,
     brms::brmsformula(  ARRESTS | trials(stu_enroll) ~ 1 + YEAR + referral_rate + (1|LEA_STATE) + (1|LEAID),
           family = "binomial")
  ),

  tar_target(
      sg_m4_mod,
      command =
        {
        obj <- brm(
          sg_m4_fml,
        data = three_year_data_group,
        seed = 11213,
      prior = make_arrest_priors(),
      sample_prior = TRUE,
      iter = NITER * ITER_MULTIPLIER,
      thin = ITER_MULTIPLIER,
      chains = NCHAINS,
      cores = NCHAINS,
      control =  mod_control,
      threads = threading(NTHREADS, static = TRUE),
      backend = "cmdstanr")
      obj$id <- three_year_data_group$group[1] # we need to label the group here
      obj
        },
      pattern = map(three_year_data_group),
      iteration = "list",
      resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
      ),

  tar_target(
    sg_m5_fml,
     brms::brmsformula(  ARRESTS | trials(stu_enroll) ~ 1 + YEAR + referral_rate + total_referrals + (1|LEA_STATE) + (1|LEAID),
           family = "binomial")
  ),

  tar_target(
      sg_m5_mod,
      command =
        {
        obj <- brm(
          sg_m5_fml,
        data = three_year_data_group,
        seed = 11213,
      prior = make_arrest_priors(),
      sample_prior = TRUE,
      iter = NITER * ITER_MULTIPLIER,
      thin = ITER_MULTIPLIER,
      chains = NCHAINS,
      cores = NCHAINS,
      control =  mod_control,
      threads = threading(NTHREADS, static = TRUE),
      backend = "cmdstanr")
      obj$id <- three_year_data_group$group[1] # we need to label the group here
      obj
        },
      pattern = map(three_year_data_group),
      iteration = "list",
      resources = tar_resources(crew = tar_resources_crew(controller = "mcmc"))
      )


)
