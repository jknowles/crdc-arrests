# Equity Analysis at a Large Scale: Using Small Area Estimation to Get the Most from the CRDC School Arrest Data

---

This repository contains the code and data to reproduce small area estimates of
school-based arrest rates from US Department of Education Civil Rights Data
Collection public datasets.

## Table of Contents

- [Abstract](#abstact)
- [Prerequisites](#prerequisites)
- [Usage](#installation)
- [Key Targets & Outputs](#key-targets--outputs)
- [Troubleshooting & Common Errors](#troubleshooting--common-errors)
- [Suggested Citation](#citation)


---

[Jared E. Knowles](https://www.civilytics.com/people/jared/) - President, Civilytics Consulting
[Hannah Miller](https://www.civilytics.com/people/hannah/) - Senior Partner, Civilytics Consulting

---

---

Jared Knowles and Hannah Miller. 2025. "Equity Analysis at a Large Scale: Using Small Area Estimation to Get the Most from the CRDC School Arrest Data." Available online at: https://www.civilytics.com/k12ed/school-based-arrest-rate-estimates/

This research was supported by a grant from the American Educational Research Association which receives funds for its "AERA Grants Program" from the National Science Foundation under NSF award NSF-DRL #1749275. Opinions reflect those of the author and do not necessarily reflect those AERA or NSF.
---

[Preprint](https://www.civilytics.com/k12ed/school-based-arrest-rate-estimates/)


## Abstract

From the final report:

> School-based punishment and discipline can be enormously consequential for students’ lives. Researchers have documented racial disparities in all outcomes along the school punishment continuum with Black students overrepresented among those experiencing every form of school punishment, including school-based arrests. To date, most public-facing analyses of school-based arrests focus on observed counts or rates with some exclusion restrictions based on sample size. These analyses quickly draw attention to outliers (some of which are data errors) and have limited use in making direct geographic, demographic, or temporal comparisons. Bayesian hierarchical models of rare events have been used to improve accuracy of rate estimates in a wide variety of fields. We show that by using this strategy we can greatly increase the ability to draw comparisons in arrest rates by increasing the rates’ precision. We evaluate the tradeoffs of several different model specifications of arrest rates in terms of precision and coverage and include applied examples of using model predictions to make informed comparisons.


## Prerequisites

This project has substantial computation requirements and configuring the
environment to run may be difficult depending on your setup. Here are some
recommendations to get you started.

| Component | Minimum Version | Notes |
|-----------|-----------------|-------|
| **R** | 4.4.x | Tested on R 4.4.3 (Linux) |
| **CmdStan** | 2.35+ | Required for `cmdstanr` backend |
| **Hardware** | ≥ 12 CPU cores, ≥ 64 GB RAM (recommended) | Parallel MCMC chains and large data joins |

### R Packages

You will want to install the following R packages in order to process the
data pipeline.

```r
install.packages(c(
  "targets", "tarchetypes", "stantargets",
  "tibble", "dplyr", "tidyr", "qs2", "quarto",
  "brms", "cmdstanr", "crew", "future.callr",
  "educationdata"
), repos = "https://cloud.r-project.org")
```

---


## Usage

This project is executed as a `targets` pipeline. This allows for caching of
intermediate results as well as organizing the data preparation, modeling, and
postprocessing of model outputs in a logical flow with correctly specified
dependencies. Learn more about targets here.

### Obtain the data

Download the official CSV version of the [Civil Rights Data Collection public use download
files](https://civilrightsdata.ed.gov/data). The pipeline requires two different files - one with
student enrollment by school and one with law enforcement arrests and referrals. For each year of
the data the required files have slightly different names.

You can follow the instructions in the [download guide](DOWNLOAD_GUIDE.md) to
obtain the three required waves of CRDC data (2015-16, 2017-18, and 2021-22).
Note that the file locations may have changed since publication. Report issues
with accessing the download as issues on this repository so it can be updated.

### Install depencencies

After installing the R packages required above you need to set up CmdStan to
fit the models effectively. The CmdStan setup varies slightly depending on
your machine architecture, but the code below should help.

**Set up CmdStan**

   ```r
   # we recommend running this in a fresh R session or restarting your current session
  install.packages("cmdstanr", repos = c('https://stan-dev.r-universe.dev', getOption("repos")))
   library(cmdstanr)
   install_cmdstan()
   cpp_options = list("CXXFLAGS += -march=native -mtune=native -DEIGEN_USE_BLAS -DEIGEN_USE_LAPACKE", "LDLIBS += -lblas -llapack -llapacke")
   cmdstanr::cmdstan_make_local(cpp_options = cpp_options, append = TRUE)
   cmdstanr::rebuild_cmdstan()
   # Verify installation
   cmdstan_path()  # should point to ~/.cmdstan/
   ```


### Enable development mode

Confirm your system is set up correctly by conducting a test run of the pipeline as below:

- **DEV_MODE** (`FALSE` by default) runs the full analysis. Set `TRUE` for an initial test.
- **enroll_cap** controls the minimum district enrollment to be included in the sample, set to 5,000
  for an initial test. Adjust via line 23 in `_targets.R`.

### Parallel Settings

Modify these values to match your hardware. The pipeline automatically configures crew controllers for regular targets and MCMC models.

```r
CPU_CAPACITY <- 32          # total cores available
NTHREADS      <- 4           # threads per MCMC chain
NCHAINS       <- 4           # number of chains
```

---

### Test the Pipeline

```r
# Load the targets package
library(targets)

# Visualise the dependency graph (optional)
tar_visnetwork()

# Run the full pipeline
tar_make()
```


---

## Key Targets & Outputs

The target pipeline will produce a number of outputs - the most important
are described below.

| Target | Description | Output |
|--------|-------------|--------|
| `combined_model_data` | Merged CRDC data across all years | RDS file (`_targets/objects/...`) |
| `three_year_data` | Modeling dataset with enrollment caps and restrictions | List with `$data` (tidy) |
| `nat_m*_mod` | National Bayesian models (baseline, demographic, referral‑adjusted, full) | `brmsfit` objects saved as RDS |
| `sg_m*_mod` | Subgroup (race/sex) models – one per demographic group | List of `brmsfit` objects |
| `combined_eda` | Quarto HTML report with descriptive statistics and plots | `crdc_combined_three_year_eda_report.html` |
| `annual_descriptives_*` | Year‑specific Quarto reports (template provided) | `annual_descriptives_<year>.html` |

All model objects are stored in the `main` storage format (`rds`) and can be loaded with `readRDS()`.

---

## Troubleshooting & Common Errors

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| **“CmdStan not found”** | CmdStan not installed or `$CMDSTAN` env var missing | Run `cmdstanr::install_cmdstan()` and ensure `Sys.getenv("CMDSTAN")` points to the installation directory. |
| **Memory allocation error** during MCMC | Too many threads/chains for available RAM | Reduce `NTHREADS`, `NCHAINS`, or set `DEV_MODE = TRUE`. |
| **File not found** for CRDC CSVs | Incorrect paths in `_targets.R` | Update the `enrollment_path` and `le_path` vectors to match your data location. |
| **Package compilation failure** (e.g., `nanonext`) | Missing system libraries (`libmbedtls`, `cmake`) | Install missing libs via apt (`sudo apt-get install libmbedtls-dev cmake`). |
| **Target fails with “object not found”** | Dependency target did not run successfully | Run `tar_make()` on the failing target’s dependencies first, or inspect logs with `tar_progress()`. |

All pipeline logs are written to `_targets/meta/` and can be inspected with `tail -f _targets/meta/<target>.log`.

---

## Suggested Citation

Jared Knowles and Hannah Miller. 2025. "Equity Analysis at a Large Scale: Using Small Area Estimation to Get the Most from the CRDC School Arrest Data." Available online at: https://www.civilytics.com/k12ed/school-based-arrest-rate-estimates/

When using this pipeline, please cite the Civil Rights Data Collection:

> U.S. Department of Education, Office for Civil Rights. (Year). *Civil Rights Data Collection*. Washington, DC.

---

## Acknowledgements

This research was supported by a grant from the American Educational Research Association which
receives funds for its "AERA Grants Program" from the National Science Foundation under NSF award
NSF-DRL #1749275. Opinions reflect those of the author and do not necessarily reflect those AERA or
NSF.

## API & Data Product

Model results are published so you don't have to re-run the pipeline:

- **API:** `https://crdc-api.civilytics.org/api/v1/` — district & state estimates
  (point + 50/80/95% credible intervals). See `api/llms.txt` and the OpenAPI spec
  at `/api/v1/openapi.json`.
- **Bulk draws:** partitioned Parquet on Hugging Face
  (`civilytics/crdc-school-arrest-rates`), queryable shard-by-shard with DuckDB.
- **Build it yourself:** the `api_db` and `draws_parquet` targets produce the
  summary DuckDB and Parquet from `tar_make()`. See `docs/api/data-dictionary.md`.
