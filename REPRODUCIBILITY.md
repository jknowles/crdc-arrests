# Reproducing the CRDC Arrests Pipeline

This document lets a newcomer reproduce the pipeline from source and sets honest
expectations about the compute involved.

## Toolchain

| Component | Version | Notes |
|-----------|---------|-------|
| R | 4.6.0 | pinned via `renv.lock` |
| R packages | see `renv.lock` | restored with `renv::restore()` |
| CmdStan | 2.37.0 | installed separately (renv cannot capture it) |
| Hardware (full run) | ≥ 24 cores, ≥ 128 GB RAM | see sizing below |

## One-time setup

```r
# from a fresh clone, in R at the project root:
source("setup.R")   # renv::restore() + install_cmdstan(2.37.0) + sanity checks
```

`setup.R` restores the locked package library, installs/points to CmdStan 2.37.0
(with the `-march=native` BLAS/LAPACK flags), and runs sanity checks (tarchetypes
loads, CmdStan resolves, DuckDB round-trips).

## Obtaining the source data

See [`DOWNLOAD_GUIDE.md`](DOWNLOAD_GUIDE.md). `Rscript download_crdc_files.R --auto`
extracts the three CRDC waves to exactly the paths `_targets.R` expects (the
contract is asserted by `tests/testthat/test-download-paths.R`).

## Running

```r
library(targets)
tar_make()          # the FULL run — see the warning below
```

### ⚠️ The full run takes DAYS

Fitting every national + subgroup Bayesian model is enormous. On a **24-core /
128 GB** machine the full `tar_make()` takes on the order of **several days** of
continuous compute. (A hypothetical Model 6 was abandoned after 7 days.) Plan
accordingly, and prefer to validate your setup first:

```bash
scripts/smoke-pipeline.sh   # DEV_MODE: builds nat_m1_mod + upstream in minutes
```

### Sizing the run to your machine (MCMC parallelism × RAM)

Peak RAM ≈ (chains running in parallel) × (per-chain data + sampler footprint).
Tune via environment variables (no need to edit `_targets.R`):

| Env var | Default | Effect |
|---------|---------|--------|
| `CRDC_CORES` | physical cores | total cores the pipeline may use |
| `CRDC_NTHREADS` | 4 | threads **per chain** (raise to finish each chain faster with fewer running at once) |
| `CRDC_NCHAINS` | 4 | chains per model |
| `CRDC_DEV_MODE` | FALSE | `true` → reduced iters + high enrollment cap (smoke) |

Rough guidance:

| Cores | RAM | Suggested settings |
|-------|-----|--------------------|
| ≥ 24 | ≥ 128 GB | defaults (`NCHAINS=4`, `NTHREADS=4`) — full speed |
| 12-16 | 64 GB | `CRDC_NTHREADS=4`, expect fewer concurrent chains; watch RSS |
| 8 | 32 GB | `CRDC_NTHREADS=8 CRDC_NCHAINS=4` (1 chain at a time) or use `CRDC_DEV_MODE=true` |
| memory pressure | — | lower `CRDC_CORES`, raise `CRDC_NTHREADS`, or raise `enroll_cap` |

### Per-stage resource costs (post-modeling artifact build)

| Stage | Cost |
|-------|------|
| Draws DB (`posterior_db`) | ~69 GB DuckDB, ~1.14 B rows |
| Summary API DB (`api_db`) | ~15 min, bounded memory + spill |
| Parquet export (`draws_parquet`) | ~3.6 min, chunked per `model_id` |

The artifact-build targets bound DuckDB `memory_limit` (~70% of RAM), cap threads,
and spill to `tmp/duckdb_spill`, so they complete on a 63 GB box. They retain the
DuckDB driver for the connection lifetime (an anonymous driver can be garbage-
collected mid-job → "Invalid connection").

## Determinism

The global seed is **11213** (`tar_option_set(seed=)`) and every model sets
`seed = 11213`. Results are **statistically reproducible but not bit-for-bit**:
the models sample with threaded Stan (`threads = threading(NTHREADS)`), and
floating-point reduction order across threads varies, so exact draw values differ
run to run while posterior summaries are equivalent.

## Provenance & resuming

`targets` caches every step in the `_targets/` store, so an interrupted run
resumes where it stopped: re-run `tar_make()` and only stale/incomplete targets
rebuild. `tar_progress()` / `tar_meta()` report status; logs are under
`_targets/meta/`. The published data release tag is
`civilytics-crdc-arrests-2025.1` (written into the API DB `meta` table).
