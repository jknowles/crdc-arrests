# Equity Analysis at a Large Scale

**Using Small Area Estimation to Get the Most from the CRDC School Arrest Data**

Bayesian small-area estimates of school-based arrest rates from the US Department
of Education's Civil Rights Data Collection (2015-16, 2017-18, and 2021-22). This
repository holds the whole pipeline — data preparation, models, posterior draws,
and the published data products.

School-based arrests are rare and unevenly reported: the most common district
count is zero, and a classical interval around a rare rate is too wide to compare
districts with. Modelling those rates hierarchically narrows the intervals enough
to make comparisons between student groups, places, and years meaningful.

[Jared E. Knowles](https://www.civilytics.com/about/people/jared-knowles/) — President, Civilytics Consulting
[Hannah Miller](https://www.civilytics.com/about/people/hannah-miller/) — Senior Partner, Civilytics Consulting

## Use the estimates without running anything

| | |
|---|---|
| **Paper** | <https://www.civilytics.com/portfolio/equity-analysis-at-a-large-scale/> — the full report, with supplementary materials |
| **API** | <https://crdc-api.civilytics.org/api/v1/> — district and state estimates with 50/80/95% credible intervals |
| **Documentation** | <https://www.civilytics.org/crdc-arrests/> — overview and data dictionary |
| **District explorer** | <https://www.civilytics.org/crdc-demo/> — compare districts and student groups interactively |
| **Bulk data** | [`civilytics/crdc-school-arrest-rates`](https://huggingface.co/datasets/civilytics/crdc-school-arrest-rates) — partitioned Parquet on Hugging Face |

Everything below is for re-running or extending the analysis itself.

## Table of Contents

- [Abstract](#abstract)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [Key Targets & Outputs](#key-targets--outputs)
- [Troubleshooting & Common Errors](#troubleshooting--common-errors)
- [Suggested Citation](#suggested-citation)

## Abstract

From the final report:

> School-based punishment and discipline can be enormously consequential for students’ lives. Researchers have documented racial disparities in all outcomes along the school punishment continuum with Black students overrepresented among those experiencing every form of school punishment, including school-based arrests. To date, most public-facing analyses of school-based arrests focus on observed counts or rates with some exclusion restrictions based on sample size. These analyses quickly draw attention to outliers (some of which are data errors) and have limited use in making direct geographic, demographic, or temporal comparisons. Bayesian hierarchical models of rare events have been used to improve accuracy of rate estimates in a wide variety of fields. We show that by using this strategy we can greatly increase the ability to draw comparisons in arrest rates by increasing the rates’ precision. We evaluate the tradeoffs of several different model specifications of arrest rates in terms of precision and coverage and include applied examples of using model predictions to make informed comparisons.


## Repository Structure

The project is organized around a **modeling-pipeline core** plus **three subsystems**
built on top of it:

1. **Draws API** — a public data product (live API + Hugging Face dataset) so people use the estimates without re-running the models.
2. **Pipeline reproducibility** — environment capture so a new user can `tar_make()` from source.
3. **Artifact reproduction** — deterministically rebuild the published documents (white paper, results, figures) from published data, with no model run.

### Top-level layout

```text
_targets.R              Pipeline definition: data prep → models → draws → API + staged artifacts
_packages.R             Package-discovery shim for renv (string-only deps like cmdstanr/qs2)
R/                      All pipeline + helper functions (see table below)
tests/testthat/         Data-layer unit/integration tests (API tests live in api/tests/)
scripts/                Operational scripts: run-tests, smoke-pipeline, publish_*, render/cache

  ── Subsystem 1 · Draws API ───────────────────────────────────────────────
api/                    plumber API: endpoints, OpenAPI, Dockerfile, llms.txt
deploy/                 docker-compose + deploy config (Gitea Action → docker socket)
docs/api/               API docs-site sources: data dictionary, runbook, index

  ── Subsystem 2 · Reproducibility ─────────────────────────────────────────
renv/  renv.lock  .Rprofile   Locked R library (R 4.6.0) + activation
setup.R                 One-stop bootstrap: renv::restore + CmdStan pin + sanity checks
.renvignore             Keeps scratch/doc-only deps out of the locked library
REPRODUCIBILITY.md      Toolchain, machine sizing, determinism, artifact reproduction
DOWNLOAD_GUIDE.md       How to obtain the CRDC source data

  ── Subsystem 3 · Artifact reproduction ───────────────────────────────────
white_paper.qmd         The report (ported from the Word source), rebuilt from artifacts
supplement.qmd          Supplementary Materials: EDA, sample construction, model
                        diagnostics, and additional applied examples
social_media_posts.qmd  Branded social-media figures/tables
annual_descriptives_template.qmd / model_descriptives_template.qmd
                        Per-CRDC-wave descriptive report templates (tar_render_rep)
_brand.yml              Civilytics Quarto brand (colors / fonts / logo)
theme/  latex/  typst/  assets/   Brand theme files + logos (referenced by _brand.yml/formats)
inst/                   Paper source (Word .docx, .bib) — git-ignored EXCEPT *.bib
docs/data-stages.md     Provenance map: each published stage artifact → its pipeline stage

  ── Documentation ─────────────────────────────────────────────────────────
docs/models.md            Model specifications & sample-restriction notes
docs/hf-dataset-card.md   Hugging Face dataset card for the published data product

  ── Generated · NOT in git (produced by running the pipeline) ──────────────
_targets/               targets store (~18 GB; only meta/ tracked, for provenance/resume)
export/                 Built outputs: db/ (69 GB draws), api/, parquet/, figures/, stages/
tmp/                    Scratch: downloaded data/, duckdb_spill/, pages build, scratch scripts
```

### The `R/` directory

| Area | Files | Role |
|---|---|---|
| Data prep & utilities | `funs.R` | CRDC/CCD ingest, reshaping, validation; `get_*_prediction_summary()`, `calculate_model_stats()` |
| Draws & summaries | `postprocess.R`, `summarize_draws.R`, `export_parquet.R` | model draws → DuckDB → parquet / summary tables |
| API artifacts | `build_api_artifacts.R`, `district_dim.R` | build the API summary DB + district lookup |
| Artifact reproduction | `crdc_path.R`, `model_registry.R`, `stage_artifacts.R`, `publish_stages.R`, `paper_figures.R`, `check_read_contract.R` | artifact resolver/cache, model id↔label registry, stage materializers, HF publish, shared render helpers + branding, read-contract guard |

### How a document reproduces

Each `.qmd` reads **published artifacts** through `crdc_path()` — set
`CRDC_ARTIFACTS=export` to read locally (owner) or use the default `hf://…`
(new user) — and never touches the `_targets/` store, so it renders standalone
(`quarto render`). The same docs are also `cue="never"` render targets in
`_targets.R`. See [`docs/data-stages.md`](docs/data-stages.md) and
[Reproduce the published artifacts](#reproduce-the-published-artifacts-no-7day-run).


## Prerequisites

This project has substantial computation requirements and configuring the
environment to run may be difficult depending on your setup. Here are some
recommendations to get you started.

| Component | Minimum Version | Notes |
|-----------|-----------------|-------|
| **R** | 4.6.0 | Pinned via `renv.lock`; see [REPRODUCIBILITY.md](REPRODUCIBILITY.md) |
| **CmdStan** | 2.37.0 | Required for `cmdstanr` backend (installed via `setup.R`) |
| **Hardware** | ≥ 12 CPU cores, ≥ 64 GB RAM (recommended) | Parallel MCMC chains and large data joins |

### R Packages

You will want to install the following R packages in order to process the
data pipeline.

```r
install.packages(c(
  "targets", "tarchetypes",
  "tibble", "dplyr", "tidyr", "qs2", "quarto",
  "brms", "cmdstanr", "crew", "future.callr",
  "educationdata"
), repos = "https://cloud.r-project.org")
```

---


## Usage

> **New here?** Start with [REPRODUCIBILITY.md](REPRODUCIBILITY.md) — it covers
> `setup.R`, the multi-day compute reality, and how to size the run to your
> hardware (the MCMC-parallelism × RAM tradeoff). Use `scripts/smoke-pipeline.sh`
> (DEV_MODE) to validate your setup in minutes before the full run.

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

### Install dependencies

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
| `unified_m*_mod` | Unified Bayesian models (baseline, demographic, referral‑adjusted, full) | `brmsfit` objects saved as RDS |
| `stratified_m*_mod` | Stratified (race/sex) models – one per demographic group | List of `brmsfit` objects |
| `white_paper` | The full report (ported from the Word source), rebuilt from artifacts | `white_paper.html` |
| `supplement` | Supplementary Materials: EDA, sample construction, model diagnostics, applied examples | `supplement.html` |
| `social_media_posts` | Branded social-media figures/tables | `social_media_posts.html` + `export/figures/socialmedia-*` |
| `annual_report` / `model_descriptives` | Year‑specific Quarto reports (templates, one per CRDC wave) | `annual_descriptives_<year>.html` / `model_descriptives_<year>.html` |

All model objects are stored in the `main` storage format (`rds`) and can be loaded with `readRDS()`.

### Reproduce the published artifacts (no 7‑day run)

The render targets above are `cue = "never"`: a normal `tar_make()` never triggers
them. They read **published artifacts**, not the model store, so anyone can
rebuild the paper/figures from a ~1.7 GB download instead of the full pipeline:

```bash
# Owner (local artifacts already in export/):
CRDC_ARTIFACTS=export scripts/render-artifacts.sh
# New user (pull from Hugging Face; big objects cache on first use):
scripts/cache-artifacts.sh && scripts/render-artifacts.sh
```

See [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) (artifact reproduction) and
[`docs/data-stages.md`](docs/data-stages.md) (what each stage artifact is).

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

> Knowles, J. E., & Miller, H. (2025). *Equity Analysis at a Large Scale: Using
> Small Area Estimation to Get the Most from the CRDC School Arrest Data*.
> Civilytics Consulting.
> https://www.civilytics.com/portfolio/equity-analysis-at-a-large-scale/

GitHub reads [`CITATION.cff`](CITATION.cff) in this repository, so the
**"Cite this repository"** button in the sidebar will give you APA or BibTeX
directly.

When using this pipeline, please also cite the Civil Rights Data Collection:

> U.S. Department of Education, Office for Civil Rights. (Year). *Civil Rights Data Collection*. Washington, DC.

---

## Acknowledgements

This research was supported by a grant from the American Educational Research Association which
receives funds for its "AERA Grants Program" from the National Science Foundation under NSF award
NSF-DRL #1749275. Opinions reflect those of the author and do not necessarily reflect those AERA or
NSF.

## API & Data Product

The links at the top of this README are the published products. A few details
that don't fit in that table:

- **API:** machine-readable description in `api/llms.txt`, OpenAPI spec at
  `/api/v1/openapi.json`.
- **Docs:** also readable in-repo — [docs/api/index.md](docs/api/index.md) and
  [docs/api/data-dictionary.md](docs/api/data-dictionary.md).
- **Bulk draws:** the Hugging Face Parquet is partitioned, so it is queryable
  shard-by-shard with DuckDB rather than as one download.
- **Build it yourself:** the `api_db` and `draws_parquet` targets produce the
  summary DuckDB and Parquet from `tar_make()`.
