# Subsystem 2 — Pipeline Reproducibility (Design Spec)

**Date:** 2026-06-01
**Branch:** `feature/pipeline-repro`
**Status:** approved — proceeding to writing-plans
**Roadmap:** [`ROADMAP.md`](./ROADMAP.md) §"Subsystem 2"
**Subsystem 1 context:** [`2026-05-30-draws-api-design.md`](./2026-05-30-draws-api-design.md)

## Goal

A stranger can clone the repo and `tar_make()` the pipeline from source and get
**statistically equivalent** results, with honest expectations about the
multi-day compute and concrete guidance on fitting that compute to their
hardware. This subsystem finishes the reproducibility debt that Subsystem 1
(API/data-product targets) began: it adds environment capture, onboarding, a
hardened build path, and machine-sizing/determinism documentation.

## Locked decisions (from brainstorming — not relitigated)

- **Reproducibility target = docs + local only.** CI must **never** fit models —
  the full model pipeline takes **~7 days on 24-core/128 GB** (this dev box is
  only 63 GB).
- **Env capture = `renv.lock` + `setup.R` + `REPRODUCIBILITY.md`.** Pin R 4.6.0;
  pin **CmdStan 2.37.0** separately via `cmdstanr::install_cmdstan(version = "2.37.0")`
  (renv cannot capture CmdStan; 2.37.0 is the version installed at `~/.cmdstan/`
  on the build box). A pipeline **Dockerfile is deferred** to "future if the
  project gains traction."
- **renv generation strategy:** `renv::init(bare = TRUE)` + `renv::snapshot()`
  against the already-installed library — record exact versions **without**
  recompiling brms/Stan on this box. A stranger runs `renv::restore()` to build
  their own isolated library.
- **Hardening scope = all three** GC-prone / single-shot targets
  (`api_db`, `draws_parquet`, `posterior_db`), with the proven logic extracted
  into committed `R/` functions.
- **CI = lightweight parse-only** validation (source `_targets.R` + `tar_validate()`),
  not a full `renv::restore`.
- **Download path mismatch fixed by fixing the download function** (keep
  `_targets.R` as the source of truth).
- **Verification includes the real heavy build** of `api_db` + `draws_parquet`
  against the live 69 GB DB before merge (the single gated heavy step).

## Out of scope

- Model fitting in CI.
- FIPS→state map fix (geo-match is already 1.0 — a non-issue).
- Pipeline Dockerfile (deferred).
- Subsystem 3 (artifact reproduction — Quarto render targets).

---

## A. Environment capture (renv + setup + .Rprofile)

- **`renv.lock`** — generated via `renv::init(bare = TRUE)` then `renv::snapshot()`
  against the currently-installed library. Captures exact package versions
  (including `tarchetypes`, which `_targets.R` does `library(tarchetypes)` on and
  which a fresh machine would otherwise lack) and R 4.6.0. No reinstall/recompile
  of brms/Stan on this box.
- **Pre-snapshot dependency reconciliation (required — a plain snapshot would
  ship a broken lock):** the current library is **missing two real
  dependencies** — `cmdstanr` (the brms backend, used at 10 `backend = "cmdstanr"`
  call sites) and `qs2` (declared in `_targets.R`'s
  `tar_option_set(packages = ...)`, so workers `library(qs2)`). Install both into
  the current library **before** snapshotting so the lock is complete. Both are
  light (cmdstanr is pure-R from the stan-dev r-universe; qs2 is a small compile);
  brms/Stan are already installed and are **not** recompiled. `stantargets` is
  **unused legacy** (referenced only in `inst/.old/`) — it is dropped from the
  README install list and is **not** locked.
- **`.Rprofile`** — the renv autoloader (written by renv). Tracked in git.
- **`setup.R`** — one-stop bootstrap script:
  1. `renv::restore()` (restore the locked library),
  2. `cmdstanr::install_cmdstan(version = "2.37.0")`, including the
     `-march=native` BLAS/LAPACK `cmdstan_make_local()` block currently in the
     README,
  3. sanity checks that fail fast with actionable messages: `cmdstanr::cmdstan_path()`
     resolves, `library(tarchetypes)` loads, a trivial DuckDB round-trip works,
     and (optional, non-fatal) an `educationdata` reachability probe.
- **`.gitignore`** — add `renv/library/`, `renv/staging/`, `renv/local/`; **track**
  `renv.lock`, `renv/activate.R`, `renv/settings.json`, `.Rprofile`.

**Interface:** `Rscript setup.R` from a clean clone leaves the machine ready to
`tar_make()` (modulo CmdStan toolchain prerequisites the script will name).

## B. Download path-contract fix

**Problem (confirmed):** `download_crdc_data()` extracts 2017-18 to
`tmp/data/2017-18-crdc-data/SCH/...`, but `_targets.R` (and
`DOWNLOAD_GUIDE.md`'s "Expected Directory Structure") expect
`tmp/data/2017-18-crdc-data-corrected-05242021/2017-18 Public-Use Files/Data/SCH/CRDC/CSV/...`.
A stranger running `--auto` gets "file not found" on year 2017-18. The 2021-22
and 2015-16 paths already match.

**Fix:**

- Correct the 2017-18 `year_dir` and file-path construction in
  `download_crdc_data()` (`R/funs.R`) to the exact paths `_targets.R` expects.
- Extract a pure helper **`crdc_expected_paths(year, dest_dir = "tmp/data")`**
  returning `list(enrollment_path, le_path)` with **no filesystem dependency**;
  `download_crdc_data()` uses it to compute return paths.
- **Path-contract test** — `tests/testthat/test-download-paths.R`: for each of
  the three years, assert `crdc_expected_paths()` equals the literal
  `enrollment_path` / `le_path` strings in `_targets.R`'s `crdc_data` tibble.
  The test reads those literals from a single shared definition so the contract
  cannot silently drift.
- Reconcile any residual prose mismatch in `DOWNLOAD_GUIDE.md`.

## C. Harden the committed artifact targets (all three)

The proven, memory-safe logic currently lives in `tmp/` scripts that were used
to build and publish the launch artifacts. Fold that logic into committed `R/`
functions. Each function that touches the 69 GB draws DB must:

- **retain the DuckDB driver** for the connection's lifetime
  (`drv <- duckdb::duckdb(dbdir = ..., read_only = ...); con <- DBI::dbConnect(drv)`
  with explicit `dbDisconnect(con, shutdown = TRUE); duckdb::duckdb_shutdown(drv)`),
  because an anonymous `dbConnect(duckdb::duckdb(), ...)` gets GC'd → "Invalid
  connection";
- bound resources: `PRAGMA temp_directory` (spill volume), `memory_limit`,
  `threads` sized to a fraction of physical RAM.

Changes:

- **`R/export_parquet.R`** — replace the single-shot global-`ORDER BY` `COPY`
  (which OOM-crashed on 1.14 B rows) with the **chunk-per-`model_id`** approach
  from `tmp/export_parquet_chunked.R`: per-model `COPY ... PARTITION_BY`,
  `SET preserve_insertion_order = false`, identical partition scheme
  (`model_id, YEAR, LEA_STATE`) and within-shard sort (`LEAID, RACE, SEX`) so
  output is byte-for-byte the same shape as before.
- **New `R/build_api_artifacts.R`** — `build_api_db(...)` mirroring
  `tmp/build_api_artifacts.R`: retained driver over the read-only 69 GB DB,
  bounded memory, calling the existing `build_arrest_summary()` /
  `build_state_summary()` / `write_api_meta()` and writing the `district_dim`
  lookup.
- **`R/postprocess.R` `process_all_targets()`** (currently
  `con <- dbConnect(duckdb(), ...)` at ~line 179) — switch to the retained-driver
  pattern with explicit shutdown.
- **`_targets.R`** — the `api_db` and `draws_parquet` target bodies call the new
  `R/` helpers instead of inline anonymous-driver / single-shot `COPY` code.

**Result:** a clean `tar_make()` (given the upstream model store) builds the data
product within 63 GB of RAM.

## D. DEV_MODE smoke test (env-var)

- `_targets.R` line ~30: `DEV_MODE <- as.logical(Sys.getenv("CRDC_DEV_MODE", "FALSE"))`.
  Downstream `enroll_cap` and `NITER` already derive from `DEV_MODE`, so no other
  change is needed for the toggle.
- **`scripts/smoke-pipeline.sh`** — one command that sets `CRDC_DEV_MODE=true`
  and runs a **bounded subset** of targets (data-prep through one small model) to
  prove the toolchain and dependency graph end-to-end locally. Documents expected
  runtime. Requires CmdStan; **local only, never CI.**

## E. Machine-sizing + determinism documentation

The full pipeline is intentionally enormous; the docs and code must set that
expectation and teach users to size the run to their hardware. The dominant
tradeoff is **MCMC parallelism × RAM width**.

- **`_targets.R`** — make `CPU_CAPACITY` / `NTHREADS` / `NCHAINS` env-overridable
  (with the current values as defaults) and add a comment block explaining the
  tradeoff: peak RAM ≈ (number of parallel chains) × (per-chain data + sampler
  footprint); `threading()` trades more cores-per-chain for fewer concurrent
  chains to shrink peak RAM; the `MCMC_WORKERS` / `N_PAR_CHAINS` derivation is
  documented inline.
- **`REPRODUCIBILITY.md`** (new) covers:
  - toolchain versions (R 4.6.0, CmdStan pin) and the `renv::restore` +
    `install_cmdstan` restore steps (CmdStan **2.37.0**);
  - **the honest reality:** a full run takes **~days even on 24-core/128 GB**,
    with a sizing table (cores × RAM → recommended `NCHAINS` / `NTHREADS`, and
    when to raise `enroll_cap` or use `DEV_MODE`);
  - per-stage resource costs: 69 GB draws DB, 1.14 B rows, ~15 min summary build,
    ~3.6 min chunked parquet export;
  - seeds/determinism: global seed 11213 and per-model `seed = 11213`; threaded
    Stan is **statistically reproducible, not bit-for-bit** — state this plainly;
  - `_targets/` store and `posterior_db` provenance, and resume notes (how the
    store lets a run be interrupted and resumed).
- **`README.md`** — fix the stale **R 4.4.x → 4.6.0** prerequisite and link
  `REPRODUCIBILITY.md`.

## F. Light CI — parse-only validation

Add a job (or step) to `.gitea/workflows/test.yml`:

- `runs-on: ubuntu-latest`, `container: rocker/r-ver:4.6.0`.
- **Shell-checkout** pattern (the runner has no node and advertises
  `ubuntu-latest`, not self-hosted): `apt-get install git`, then a tokenized
  `git clone`, matching the existing workflow steps.
- Install only the packages required to **source** `_targets.R`:
  `targets, tarchetypes, tibble, future, future.callr, crew, DBI, dplyr`
  (final list pinned during implementation by sourcing and resolving missing
  symbols).
- Run `Rscript -e 'library(tarchetypes); targets::tar_validate()'` (which sources
  `_targets.R` and checks the graph parses and loads).
- **No `renv::restore`, no model fitting.** This guards exactly the regression we
  hit at launch: `library(tarchetypes)` missing → pipeline cannot be sourced.

## G. Tidy

- Remove `inst/.old` (6 stale files; gitignored, so a local `rm` only).
- Prune the **superseded** `tmp/` scripts/logs once their logic lands in `R/`
  (`export_parquet_chunked.R`, `build_api_artifacts.R`, `validate_api_artifacts.R`,
  and their `*.log` files). **Keep** `tmp/data/` (downloaded CRDC source) and
  `tmp/duckdb_spill/`.
- `.gitignore` review per §A (renv ignores; track `renv.lock`).

## H. Verification

- **Unit tests** against a small **synthetic `predicted_draws` DuckDB fixture**
  exercising the hardened functions: retained driver, chunk-per-`model_id`
  output shape/partitioning, and the memory pragmas being applied. Extend the
  existing `tests/testthat/test-export_parquet.R`.
- The §B path-contract test.
- Run the suite with `./scripts/run-tests.sh`.
- **Real heavy build (gated):** after the refactor, execute the hardened
  `api_db` + `draws_parquet` targets against the live 69 GB draws DB
  (~20 min, bounded memory) to prove the **committed** pipeline path builds
  end-to-end within 63 GB before merge. Confirm with the user before launching
  this step.

---

## Files touched (summary)

| File | Change |
|------|--------|
| `renv.lock`, `.Rprofile`, `renv/activate.R`, `renv/settings.json` | new (env capture) |
| `setup.R` | new (bootstrap: restore + install_cmdstan + sanity checks) |
| `REPRODUCIBILITY.md` | new (toolchain, sizing, determinism, provenance) |
| `R/funs.R` | fix 2017-18 paths; add `crdc_expected_paths()` |
| `R/export_parquet.R` | chunk-per-`model_id`, retained driver, bounded memory |
| `R/build_api_artifacts.R` | new (`build_api_db()` helper) |
| `R/postprocess.R` | retained-driver fix in `process_all_targets()` |
| `_targets.R` | env-var `DEV_MODE` + sizing; `api_db`/`draws_parquet` call new helpers; sizing comments |
| `scripts/smoke-pipeline.sh` | new (DEV_MODE one-command smoke) |
| `.gitea/workflows/test.yml` | add parse-only validation job |
| `tests/testthat/test-download-paths.R` | new (path contract) |
| `tests/testthat/test-export_parquet.R` | extend (chunked fixture) |
| `README.md` | R 4.4.x → 4.6.0; CmdStan 2.37.0; drop unused `stantargets` from install list; link `REPRODUCIBILITY.md` |
| `DOWNLOAD_GUIDE.md` | reconcile prose with fixed paths |
| `.gitignore` | renv ignores |
| `inst/.old`, superseded `tmp/` scripts | removed |

## Conventions / gotchas honored

- R/Rscript for ad-hoc work (allowlisted, no prompt); tests via `./scripts/run-tests.sh`.
- `origin` dual-pushes GitHub `jknowles/crdc-arrests` (canonical, public) + Gitea
  `jared/crdc-arrests`; a stale `GITHUB_TOKEN` may need `GITHUB_TOKEN= GH_TOKEN=` prefix.
- Gitea runner has no node, advertises `ubuntu-latest` → shell `git clone` checkout
  in all workflows.
- Always retain DuckDB drivers (anonymous driver GC → "Invalid connection").
- Confirm with the user before heavy compute or any push.
