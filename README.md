# CRDC Arrest Rates Analysis Pipeline

A reproducible **R targets** pipeline for analyzing arrest rates in U.S. public schools using the Civil Rights Data Collection (CRDC). The workflow fits Bayesian hierarchical models with `brms`/`cmdstanr`, processes three waves of CRDC data (2015‑16, 2017‑18, 2021‑22), and generates exploratory reports and model diagnostics.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running the Pipeline](#running-the-pipeline)
- [Key Targets & Outputs](#key-targets--outputs)
- [Troubleshooting & Common Errors](#troubleshooting--common-errors)
- [Reproducibility Best Practices](#reproducibility-best-practices)
- [Citation](#citation)
- [License & Contact](#license--contact)

---

## Prerequisites

| Component | Minimum Version | Notes |
|-----------|-----------------|-------|
| **R** | 4.4.x | Tested on R 4.4.3 (Linux) |
| **CmdStan** | 2.35+ | Required for `cmdstanr` backend |
| **System libraries** | libcurl, OpenSSL, CMake, gcc/clang | Needed to compile several CRAN packages |
| **Hardware** | ≥ 32 CPU cores, ≥ 64 GB RAM (recommended) | Parallel MCMC chains and large data joins |

### R Packages

All required R packages are listed in `DESCRIPTION`‑style format below. Install them with:

```r
install.packages(c(
  "targets", "tarchetypes", "stantargets",
  "tibble", "dplyr", "tidyr", "qs2", "quarto",
  "brms", "cmdstanr", "crew", "future.callr",
  "educationdata"
), repos = "https://cloud.r-project.org")
```

> **Tip:** Use `renv::restore()` if a lockfile is added later.

---

## Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/your-org/crdc-arrest-pipeline.git
   cd crdc-arrest-pipeline
   ```

2. **Install system dependencies** (Ubuntu/Debian example)

   ```bash
    sudo apt-get update && \
    sudo apt-get install -y libcurl4-openssl-dev libssl-dev cmake
    sudo apt-get install liblapacke-dev liblapacke libopenblas-dev libopenblas-pthread-dev libopenblas-serial-dev libopenblas0 libopenblas0-pthread libopenblas0-serial
    sudo update-alternatives --config libblas.so.3-x86_64-linux-gnu
    sudo update-alternatives --config liblapack.so.3-x86_64-linux-gnu
    sudo update-alternatives --config liblapacke.so.3-x86_64-linux-gnu
   ```

3. **Install R packages** (see above). The previous step already installed `crew`, `future.callr`, and `educationdata`.

4. **Set up CmdStan**

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


---

## Configuration

### Data Paths

The pipeline expects CRDC CSV files in the locations defined in `_targets.R`. Two sets of default paths are provided:

- **Linux/macOS** – under `tmp/data/…`
- **Windows** – absolute network share (`X:/datasets/ED/CRDC/...`)

Edit the `crdc_data` tibble in [_targets.R_](./_targets.R) (lines 71‑85 for Linux/macOS, lines 90‑104 for Windows) to point at your local copies.

### Development Mode & Enrollment Cap

- **DEV_MODE** (`FALSE` by default) runs the full analysis. Set `TRUE` for quick tests.
- **enroll_cap** controls the minimum district enrollment (30 students in production, 5 000 in dev mode). Adjust via line 23 in `_targets.R`.

### Parallel Settings

```r
CPU_CAPACITY <- 32          # total cores available
NTHREADS      <- 4           # threads per MCMC chain
NCHAINS       <- 4           # number of chains
```

Modify these values to match your hardware. The pipeline automatically configures crew controllers for regular targets and MCMC models.

---

## Running the Pipeline

```r
# Load the targets package
library(targets)

# Visualise the dependency graph (optional)
tar_visnetwork()

# Run the full pipeline
tar_make()
```


All targets are defined in `_targets.R`. Use `tar_meta()` to list them or `tar_read(target_name)` to inspect a target’s value.

---

## Key Targets & Outputs

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

## Reproducibility Best Practices

1. **Pin R package versions** – use an `renv.lock` file (run `renv::snapshot()` after installing packages).
2. **Record CmdStan version** – `cmdstanr::cmdstan_version()`.
3. **Store raw data outside the repo** and reference it via absolute or relative paths; never commit large CSVs.
4. **Run on a dedicated compute node** with the same `CPU_CAPACITY`, `NTHREADS`, and `NCHAINS` settings used for the original analysis.
5. **Version‑control `_targets.R`** – any change to target definitions requires a new pipeline run.

---

## Citation

When using this pipeline, please cite the Civil Rights Data Collection:

> U.S. Department of Education, Office for Civil Rights. (Year). *Civil Rights Data Collection*. Washington, DC.

Additionally, acknowledge the software:

```bibtex
@software{crdc_arrest_pipeline,
  author = {Your Name},
  title = {{CRDC Arrest Rates Analysis Pipeline}},
  year = {2025},
  url = {https://github.com/your-org/crdc-arrest-pipeline}
}
```

---

## License & Contact

- **License:** Add appropriate license text here (e.g., MIT, GPL‑3.0).
- **Contact:** For questions or collaborations, reach out to `youremail@example.com`.

---
