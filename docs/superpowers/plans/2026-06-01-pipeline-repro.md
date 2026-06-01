# Pipeline Reproducibility (Subsystem 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the CRDC arrests pipeline reproducible by a stranger from source — capture the environment (renv.lock + setup.R + CmdStan pin), fix the download→`_targets.R` path contract, harden the three memory-fragile DuckDB targets so a clean `tar_make()` builds the data product within 63 GB, document the multi-day compute and how to size it, and add a parse-only CI guard.

**Architecture:** R + `targets` pipeline. Memory-safe DuckDB work uses a *retained driver* (`drv <- duckdb::duckdb(...); con <- dbConnect(drv)`) and *chunk-per-`model_id`* COPY with bounded `memory_limit`/`threads`/spill. Heavy `tmp/` reference scripts are folded into committed `R/` functions. renv captures the library by hydrating already-installed packages (no brms/Stan recompile); CmdStan is pinned separately (2.37.0).

**Tech Stack:** R 4.6.0, targets/tarchetypes, brms+cmdstanr (CmdStan 2.37.0), DuckDB, renv 1.x, testthat 3e, Gitea Actions (rocker/r-ver:4.6.0).

**Spec:** [`../specs/2026-06-01-pipeline-repro-design.md`](../specs/2026-06-01-pipeline-repro-design.md)

**Conventions (apply to every task):**
- Run tests with `./scripts/run-tests.sh` (optionally `./scripts/run-tests.sh <filter>`). Ad-hoc R via `Rscript -e '...'`.
- Commit after each green task. Do **not** push and do **not** start the §H heavy build without explicit user confirmation (both are called out below).
- The repo is on branch `feature/pipeline-repro`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `R/funs.R` | (modify) add pure `crdc_expected_paths()`; fix `download_crdc_data()` 2017-18 paths |
| `R/export_parquet.R` | (modify) chunk-per-`model_id` COPY + optional bounded-memory pragmas on the passed connection |
| `R/build_api_artifacts.R` | (create) retained-driver wrappers `build_api_db()` + `build_draws_parquet()` + `duckdb_mem_limit_gb()` |
| `R/postprocess.R` | (modify) retained-driver fix in `process_all_targets()` |
| `_targets.R` | (modify) env-var `DEV_MODE`/cores/threads + sizing comments; `api_db`/`draws_parquet` bodies call new wrappers |
| `_packages.R` | (create) library() declarations so renv discovers string-only deps (cmdstanr, qs2, …) |
| `setup.R` | (create) bootstrap: renv::restore + install_cmdstan(2.37.0) + sanity checks |
| `REPRODUCIBILITY.md` | (create) toolchain, sizing table, determinism, provenance |
| `scripts/smoke-pipeline.sh` | (create) one-command DEV_MODE smoke |
| `.gitea/workflows/test.yml` | (modify) add parse-only `pipeline-validate` job |
| `tests/testthat/setup.R` | (modify) also source `funs.R` + `build_api_artifacts.R` |
| `tests/testthat/helper-fixtures.R` | (modify) add on-disk draws-DB fixture |
| `tests/testthat/test-download-paths.R` | (create) path-contract test |
| `tests/testthat/test-export_parquet.R` | (modify) add chunk-per-model test |
| `tests/testthat/test-build_api_artifacts.R` | (create) retained-driver wrapper tests |
| `README.md` | (modify) R 4.4.x→4.6.0, CmdStan 2.37.0, drop stantargets, link REPRODUCIBILITY |
| `DOWNLOAD_GUIDE.md` | (modify) reconcile prose with fixed paths |
| `.gitignore` | (modify) renv ignores |
| `inst/.old`, superseded `tmp/*.R`,`tmp/*.log` | (delete) |

---

## Task 1: Remove stale `inst/.old`

**Files:**
- Delete: `inst/.old/` (6 files; `/inst` is gitignored, so this is a local cleanup only)

- [ ] **Step 1: Confirm the directory is gitignored (no tracked files)**

Run: `cd /home/jared/Nextcloud/Civilytics/Code/aera-crdc2 && git ls-files inst/.old | wc -l`
Expected: `0` (nothing tracked — safe to delete locally)

- [ ] **Step 2: Delete the directory**

Run: `rm -rf inst/.old && ls inst/ 2>/dev/null || echo "inst now empty/absent"`
Expected: `.old` no longer present.

- [ ] **Step 3: No commit needed** (nothing tracked changed). Proceed to Task 2.

---

## Task 2: Path contract — `crdc_expected_paths()` + path-contract test (RED first)

**Files:**
- Modify: `tests/testthat/setup.R`
- Create: `tests/testthat/test-download-paths.R`
- Modify: `R/funs.R` (add `crdc_expected_paths()` just above `download_crdc_data()` at line ~1440)

- [ ] **Step 1: Make the test suite source `funs.R`**

In `tests/testthat/setup.R`, change the file vector to include `funs.R` first:

```r
# Sourced automatically by testthat::test_dir before tests run.
# Guard with file.exists so the suite works as files are added task-by-task.
for (f in c("funs.R", "district_dim.R", "summarize_draws.R",
            "export_parquet.R", "build_api_artifacts.R")) {
  p <- file.path("..", "..", "R", f)
  if (file.exists(p)) source(p)
}
```

- [ ] **Step 2: Write the failing path-contract test**

Create `tests/testthat/test-download-paths.R`:

```r
test_that("crdc_expected_paths matches the canonical _targets.R contract", {
  # Canonical paths copied verbatim from _targets.R `crdc_data`. Keep in sync:
  # this test fails loudly if the download helper ever drifts from the pipeline.
  expected <- list(
    "2021-22" = list(
      enrollment_path = "tmp/data/2021-22-crdc-data/SCH/Enrollment.csv",
      le_path         = "tmp/data/2021-22-crdc-data/SCH/Referrals and Arrests.csv"),
    "2017-18" = list(
      enrollment_path = "tmp/data/2017-18-crdc-data-corrected-05242021/2017-18 Public-Use Files/Data/SCH/CRDC/CSV/Enrollment.csv",
      le_path         = "tmp/data/2017-18-crdc-data-corrected-05242021/2017-18 Public-Use Files/Data/SCH/CRDC/CSV/Referrals and Arrests.csv"),
    "2015-16" = list(
      enrollment_path = "tmp/data/2015-16-crdc-data/Data Files and Layouts/CRDC 2015-16 School Data.csv",
      le_path         = "tmp/data/2015-16-crdc-data/Data Files and Layouts/CRDC 2015-16 School Data.csv")
  )
  for (y in names(expected)) {
    got <- crdc_expected_paths(y, dest_dir = "tmp/data")
    expect_equal(got$enrollment_path, expected[[y]]$enrollment_path, info = y)
    expect_equal(got$le_path,         expected[[y]]$le_path,         info = y)
  }
})

test_that("crdc_expected_paths rejects unknown years", {
  expect_error(crdc_expected_paths("2099-00"), "Year must be one of")
})
```

- [ ] **Step 3: Run it — expect failure (function undefined)**

Run: `./scripts/run-tests.sh download-paths`
Expected: FAIL — `could not find function "crdc_expected_paths"`.

- [ ] **Step 4: Implement `crdc_expected_paths()`**

In `R/funs.R`, immediately above `download_crdc_data <- function(` (line ~1440), insert:

```r
#' Canonical CRDC CSV paths per year, relative to `dest_dir`.
#'
#' Single source of truth for the file locations the targets pipeline expects.
#' These MUST match the `enrollment_path`/`le_path` columns in `_targets.R`'s
#' `crdc_data` tibble (asserted by tests/testthat/test-download-paths.R).
#' Pure: computes paths only, touches no filesystem.
#'
#' @param year one of "2021-22", "2017-18", "2015-16".
#' @param dest_dir extraction root (default "tmp/data").
#' @return list(enrollment_path, le_path).
crdc_expected_paths <- function(year, dest_dir = "tmp/data") {
  valid_years <- c("2021-22", "2017-18", "2015-16")
  if (!year %in% valid_years) {
    stop("Year must be one of: ", paste(valid_years, collapse = ", "))
  }
  switch(year,
    "2021-22" = list(
      enrollment_path = file.path(dest_dir, "2021-22-crdc-data", "SCH", "Enrollment.csv"),
      le_path         = file.path(dest_dir, "2021-22-crdc-data", "SCH", "Referrals and Arrests.csv")
    ),
    "2017-18" = {
      base <- file.path(dest_dir, "2017-18-crdc-data-corrected-05242021",
                        "2017-18 Public-Use Files", "Data", "SCH", "CRDC", "CSV")
      list(enrollment_path = file.path(base, "Enrollment.csv"),
           le_path         = file.path(base, "Referrals and Arrests.csv"))
    },
    "2015-16" = {
      f <- file.path(dest_dir, "2015-16-crdc-data", "Data Files and Layouts",
                     "CRDC 2015-16 School Data.csv")
      list(enrollment_path = f, le_path = f)
    }
  )
}
```

- [ ] **Step 5: Run it — expect pass**

Run: `./scripts/run-tests.sh download-paths`
Expected: PASS (both tests).

- [ ] **Step 6: Commit**

```bash
git add R/funs.R tests/testthat/setup.R tests/testthat/test-download-paths.R
git commit -m "feat(repro): add crdc_expected_paths() + path-contract test"
```

---

## Task 3: Wire `download_crdc_data()` to the contract (fixes 2017-18)

**Files:**
- Modify: `R/funs.R` — `download_crdc_data()` `year_dir` switch (line ~1459) and path block (lines ~1502-1516)

- [ ] **Step 1: Fix the 2017-18 extraction directory name**

In `download_crdc_data()`, change the `year_dir` switch so 2017-18 matches the pipeline:

```r
  year_dir <- switch(year,
    "2021-22" = "2021-22-crdc-data",
    "2017-18" = "2017-18-crdc-data-corrected-05242021",
    "2015-16" = "2015-16-crdc-data"
  )
```

- [ ] **Step 2: Replace the per-year path block with the shared helper**

Replace the whole `if (year == "2021-22") { ... } else { ... }` path-determination block (lines ~1502-1516) with:

```r
  # Canonical paths (single source of truth shared with the targets pipeline).
  paths <- crdc_expected_paths(year, dest_dir = dest_dir)
  enrollment_path <- paths$enrollment_path
  le_path <- paths$le_path
```

(Leave the subsequent `file.exists()` warnings and the returned `result` list unchanged.)

- [ ] **Step 3: Add a regression test asserting the function agrees with the helper**

Append to `tests/testthat/test-download-paths.R`:

```r
test_that("download_crdc_data computes the contract paths without downloading", {
  # No zip_file + existing dir short-circuits extraction; we only check paths.
  dest <- tempfile("crdc_dest_")
  dir.create(file.path(dest, "2017-18-crdc-data-corrected-05242021"), recursive = TRUE)
  res <- suppressWarnings(suppressMessages(
    download_crdc_data(year = "2017-18", dest_dir = dest)))
  exp <- crdc_expected_paths("2017-18", dest_dir = dest)
  expect_equal(res$enrollment_path, exp$enrollment_path)
  expect_equal(res$le_path, exp$le_path)
})
```

- [ ] **Step 4: Run tests — expect pass**

Run: `./scripts/run-tests.sh download-paths`
Expected: PASS (all three tests). The new test confirms `download_crdc_data()` returns the corrected 2017-18 paths.

- [ ] **Step 5: Reconcile `DOWNLOAD_GUIDE.md`**

Confirm `DOWNLOAD_GUIDE.md`'s "Expected Directory Structure" already shows `2017-18-crdc-data-corrected-05242021/2017-18 Public-Use Files/...` (it does). Add one line under that block:

```markdown
> The automated `download_crdc_data()` extracts to exactly these paths, which match `_targets.R`. If a future CRDC re-release changes the folder names, update `crdc_expected_paths()` in `R/funs.R` and the `crdc_data` tibble in `_targets.R` together.
```

- [ ] **Step 6: Commit**

```bash
git add R/funs.R tests/testthat/test-download-paths.R DOWNLOAD_GUIDE.md
git commit -m "fix(repro): download_crdc_data 2017-18 paths match _targets.R contract"
```

---

## Task 4: Chunk-per-`model_id` parquet export (replace single-shot COPY)

**Files:**
- Modify: `R/export_parquet.R`
- Modify: `tests/testthat/test-export_parquet.R` (add a multi-model test)

- [ ] **Step 1: Write the failing multi-model test**

Append to `tests/testthat/test-export_parquet.R`:

```r
test_that("export_draws_parquet chunks per model_id (all models exported)", {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  draws <- rbind(
    data.frame(LEAID="0100005", LEA_STATE="AL", YEAR="21-22", RACE="BL", SEX="M",
               pred=0:9, draw_id=1:10, model_id="nat_m2_mod",
               subgroup_id="nat_m2_mod", stringsAsFactors=FALSE),
    data.frame(LEAID="0100006", LEA_STATE="AL", YEAR="21-22", RACE="WH", SEX="F",
               pred=rep(5L,10), draw_id=1:10, model_id="sg_m2_mod",
               subgroup_id="sg_m2_mod", stringsAsFactors=FALSE)
  )
  DBI::dbWriteTable(con, "predicted_draws", draws)
  out <- file.path(tempfile(), "pq")
  export_draws_parquet(con, out_dir = out)
  files <- list.files(out, recursive = TRUE, pattern = "\\.parquet$")
  expect_true(any(grepl("model_id=nat_m2_mod", files)))
  expect_true(any(grepl("model_id=sg_m2_mod", files)))
  rcon <- DBI::dbConnect(duckdb::duckdb()); on.exit(DBI::dbDisconnect(rcon, shutdown=TRUE), add=TRUE)
  n <- DBI::dbGetQuery(rcon, sprintf(
    "SELECT COUNT(*) n FROM read_parquet('%s/**/*.parquet', hive_partitioning=true)", out))$n
  expect_equal(n, 20)
})
```

- [ ] **Step 2: Run it — expect pass on output, but we still need the chunked impl**

Run: `./scripts/run-tests.sh export_parquet`
Expected: PASS with the current single-shot COPY too (output is correct for 2 models). This test *locks the behavior* before we change the implementation. If it FAILS, stop and investigate.

- [ ] **Step 3: Replace the single-shot COPY with a per-model loop + optional pragmas**

Replace the entire body of `R/export_parquet.R` with:

```r
library(DBI)

#' Export predicted_draws to Hive-partitioned Parquet for bulk distribution.
#'
#' Memory-safe: chunks per `model_id` (each pass sorts/buffers one model's rows,
#' not all 1.14B at once) and optionally bounds DuckDB memory/threads/spill. The
#' single-shot global ORDER BY + ~1500 simultaneous partition write-buffers OOM'd
#' a 63 GB box; this does not. Partition scheme (model_id, YEAR, LEA_STATE) and
#' within-shard sort (LEAID, RACE, SEX) are unchanged, so output shape is identical.
#'
#' @param draws_con open DBI connection holding `predicted_draws`.
#' @param out_dir output directory (created if missing).
#' @param memory_limit optional DuckDB memory_limit, e.g. "24GB" (NULL = leave default).
#' @param threads optional DuckDB thread cap (NULL = leave default).
#' @param temp_dir optional spill directory for temp_directory (NULL = leave default).
export_draws_parquet <- function(draws_con, out_dir,
                                 memory_limit = NULL, threads = NULL,
                                 temp_dir = NULL) {
  stopifnot(!grepl("'", out_dir))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  if (!is.null(temp_dir)) {
    dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
    DBI::dbExecute(draws_con, sprintf("PRAGMA temp_directory='%s'", temp_dir))
  }
  if (!is.null(memory_limit)) {
    DBI::dbExecute(draws_con, sprintf("SET memory_limit='%s'", memory_limit))
  }
  if (!is.null(threads)) {
    DBI::dbExecute(draws_con, sprintf("SET threads=%d", as.integer(threads)))
  }
  # No global buffering to preserve insertion order; we ORDER BY inside each COPY.
  DBI::dbExecute(draws_con, "SET preserve_insertion_order=false")

  models <- DBI::dbGetQuery(
    draws_con,
    "SELECT DISTINCT model_id FROM predicted_draws ORDER BY model_id")$model_id

  for (m in models) {
    stopifnot(!grepl("'", m))
    sql <- sprintf("
      COPY (
        SELECT * FROM predicted_draws WHERE model_id = '%s'
        ORDER BY YEAR, LEA_STATE, LEAID, RACE, SEX
      ) TO '%s'
      (FORMAT parquet, PARTITION_BY (model_id, YEAR, LEA_STATE), OVERWRITE_OR_IGNORE)",
      m, out_dir)
    DBI::dbExecute(draws_con, sql)
  }
  invisible(out_dir)
}
```

- [ ] **Step 4: Run the full parquet suite — expect pass**

Run: `./scripts/run-tests.sh export_parquet`
Expected: PASS — all tests including the original single-model Hive/sort test, the quote-rejection test, and the new multi-model test.

- [ ] **Step 5: Commit**

```bash
git add R/export_parquet.R tests/testthat/test-export_parquet.R
git commit -m "fix(repro): chunk parquet export per model_id with bounded memory"
```

---

## Task 5: Retained-driver wrappers `build_api_db()` + `build_draws_parquet()`

**Files:**
- Create: `R/build_api_artifacts.R`
- Modify: `tests/testthat/helper-fixtures.R` (add on-disk draws-DB fixture)
- Create: `tests/testthat/test-build_api_artifacts.R`

- [ ] **Step 1: Add an on-disk draws-DB fixture**

Append to `tests/testthat/helper-fixtures.R`:

```r
# A tiny on-disk predicted_draws DuckDB file (for the retained-driver wrappers,
# which open their own connection from a db path).
fixture_draws_db_file <- function(models = c("nat_m2_mod", "sg_m2_mod")) {
  path <- tempfile(fileext = ".duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = path)
  draws <- do.call(rbind, lapply(models, function(m)
    data.frame(LEAID = "0100005", LEA_STATE = "AL", YEAR = "21-22",
               RACE = "BL", SEX = "M", pred = 0:9, draw_id = 1:10,
               model_id = m, subgroup_id = m, stringsAsFactors = FALSE)))
  DBI::dbWriteTable(con, "predicted_draws", draws)
  DBI::dbDisconnect(con, shutdown = TRUE)
  path
}
```

- [ ] **Step 2: Write the failing wrapper tests**

Create `tests/testthat/test-build_api_artifacts.R`:

```r
test_that("build_draws_parquet exports every model from a db path", {
  dbpath <- fixture_draws_db_file(c("nat_m2_mod", "sg_m2_mod"))
  out <- file.path(tempfile(), "parquet")
  res <- build_draws_parquet(dbpath, out)
  expect_equal(res, out)
  files <- list.files(out, recursive = TRUE, pattern = "\\.parquet$")
  expect_true(any(grepl("model_id=nat_m2_mod", files)))
  expect_true(any(grepl("model_id=sg_m2_mod", files)))
})

test_that("build_api_db writes arrest_summary, state_summary, district_dim, meta", {
  dbpath <- fixture_draws_db_file("nat_m2_mod")
  api <- tempfile(fileext = ".duckdb")
  res <- build_api_db(dbpath, api, fixture_enroll_lookup(), fixture_district_dim(),
                      data_release = "test-release")
  expect_equal(res, api)
  acon <- DBI::dbConnect(duckdb::duckdb(), dbdir = api, read_only = TRUE)
  on.exit(DBI::dbDisconnect(acon, shutdown = TRUE))
  tbls <- DBI::dbListTables(acon)
  expect_true(all(c("arrest_summary", "state_summary", "district_dim", "meta") %in% tbls))
  rel <- DBI::dbGetQuery(acon, "SELECT data_release FROM meta")$data_release
  expect_equal(rel, "test-release")
})

test_that("duckdb_mem_limit_gb returns a positive integer", {
  expect_true(duckdb_mem_limit_gb() >= 8)
})
```

- [ ] **Step 3: Run — expect failure (functions undefined)**

Run: `./scripts/run-tests.sh build_api_artifacts`
Expected: FAIL — `could not find function "build_draws_parquet"`.

- [ ] **Step 4: Implement the wrappers**

Create `R/build_api_artifacts.R`:

```r
# Retained-driver wrappers around the heavy draws-DB reads. Folds the proven
# logic from tmp/build_api_artifacts.R + tmp/export_parquet_chunked.R into the
# committed pipeline. CRITICAL: keep `drv` alive for the connection's lifetime —
# an anonymous dbConnect(duckdb::duckdb(), ...) can be GC'd mid-job, shutting the
# database under the connection -> "Invalid connection".

#' Pick a DuckDB memory_limit (GB) as a fraction of physical RAM (Linux).
#' Falls back to 8 GB when /proc/meminfo is unavailable.
duckdb_mem_limit_gb <- function(fraction = 0.7) {
  mt <- tryCatch(grep("MemTotal", readLines("/proc/meminfo"), value = TRUE),
                 error = function(e) character(0))
  if (!length(mt)) return(8L)
  kb <- as.numeric(gsub("\\D", "", mt))
  max(8L, as.integer(floor((kb / 1024 / 1024) * fraction)))
}

#' Open a retained read connection to a DuckDB file, with bounded resources.
#' Returns list(drv, con); caller MUST call close_draws_con() when done.
open_draws_con <- function(db_path, read_only = TRUE,
                           memory_limit = NULL, threads = NULL, temp_dir = NULL) {
  drv <- duckdb::duckdb(dbdir = db_path, read_only = read_only)
  con <- DBI::dbConnect(drv)
  stopifnot(DBI::dbIsValid(con))
  if (!is.null(temp_dir)) {
    dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
    DBI::dbExecute(con, sprintf("PRAGMA temp_directory='%s'", temp_dir))
  }
  if (!is.null(memory_limit)) {
    DBI::dbExecute(con, sprintf("SET memory_limit='%s'", memory_limit))
  }
  if (!is.null(threads)) {
    DBI::dbExecute(con, sprintf("SET threads=%d", as.integer(threads)))
  }
  list(drv = drv, con = con)
}

#' Disconnect and shut down a retained connection from open_draws_con().
close_draws_con <- function(h) {
  DBI::dbDisconnect(h$con, shutdown = TRUE)
  duckdb::duckdb_shutdown(h$drv)
  invisible(NULL)
}

#' Build the summary API DuckDB from the big draws DB (retained driver).
#'
#' @param draws_db_path read-only source DuckDB holding predicted_draws.
#' @param api_path output API DuckDB (overwritten if present).
#' @param enroll_lookup,district_dim see build_arrest_summary().
#' @param data_release provenance string written to meta.
#' @param memory_limit,threads,temp_dir DuckDB resource bounds (NULL = defaults).
build_api_db <- function(draws_db_path, api_path, enroll_lookup, district_dim,
                         data_release,
                         memory_limit = NULL, threads = NULL, temp_dir = NULL) {
  dir.create(dirname(api_path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(api_path)) file.remove(api_path)

  h <- open_draws_con(draws_db_path, read_only = TRUE,
                      memory_limit = memory_limit, threads = threads,
                      temp_dir = temp_dir)
  on.exit(close_draws_con(h), add = TRUE)

  build_arrest_summary(h$con, enroll_lookup, district_dim, api_path)
  build_state_summary(h$con, enroll_lookup, api_path)

  # district_dim as its own lookup table (own short-lived connection on api_path)
  acon <- DBI::dbConnect(duckdb::duckdb(), dbdir = api_path, read_only = FALSE)
  DBI::dbWriteTable(acon, "district_dim", district_dim, overwrite = TRUE)
  DBI::dbDisconnect(acon, shutdown = TRUE)

  write_api_meta(api_path, data_release = data_release)
  invisible(api_path)
}

#' Export Hive-partitioned parquet from the big draws DB (retained driver).
build_draws_parquet <- function(draws_db_path, out_dir,
                                memory_limit = NULL, threads = NULL,
                                temp_dir = NULL) {
  h <- open_draws_con(draws_db_path, read_only = TRUE,
                      memory_limit = memory_limit, threads = threads,
                      temp_dir = temp_dir)
  on.exit(close_draws_con(h), add = TRUE)
  export_draws_parquet(h$con, out_dir)  # pragmas already set on the connection
  invisible(out_dir)
}
```

- [ ] **Step 5: Run — expect pass**

Run: `./scripts/run-tests.sh build_api_artifacts`
Expected: PASS (all three tests). `setup.R` already sources `build_api_artifacts.R` (added in Task 2).

- [ ] **Step 6: Commit**

```bash
git add R/build_api_artifacts.R tests/testthat/helper-fixtures.R tests/testthat/test-build_api_artifacts.R
git commit -m "feat(repro): retained-driver build_api_db/build_draws_parquet wrappers"
```

---

## Task 6: Retained-driver fix in `process_all_targets()`

**Files:**
- Modify: `R/postprocess.R` (lines ~176-181)

- [ ] **Step 1: Replace the anonymous-driver connection**

In `process_all_targets()`, replace:

```r
  # Connect to DuckDB
  con <- dbConnect(duckdb(), dbdir = db_path, read_only = FALSE)
  on.exit(dbDisconnect(con))
```

with:

```r
  # Connect to DuckDB. Retain the driver in `drv` for the function's lifetime —
  # an anonymous dbConnect(duckdb(), ...) can be GC'd during the long
  # draws-streaming loop, yielding "Invalid connection". See R/build_api_artifacts.R.
  drv <- duckdb::duckdb(dbdir = db_path, read_only = FALSE)
  con <- DBI::dbConnect(drv)
  on.exit({
    DBI::dbDisconnect(con, shutdown = TRUE)
    duckdb::duckdb_shutdown(drv)
  })
```

- [ ] **Step 2: Verify the file still parses/sources cleanly**

Run: `Rscript -e 'source("R/postprocess.R"); cat("ok: process_all_targets is", class(process_all_targets), "\n")'`
Expected: `ok: process_all_targets is function`

(No unit test: this target writes the 69 GB DB from `tar_read` model objects; it is exercised by the §H heavy run and was validated at launch. The change is a mechanical connection-lifecycle fix.)

- [ ] **Step 3: Commit**

```bash
git add R/postprocess.R
git commit -m "fix(repro): retain DuckDB driver in process_all_targets (posterior_db)"
```

---

## Task 7: Env-var `DEV_MODE` + machine-sizing knobs & comments in `_targets.R`

**Files:**
- Modify: `_targets.R` (lines ~13-46 and the `DEV_MODE` line ~30)

- [ ] **Step 1: Make compute knobs env-overridable with a sizing comment block**

Replace the block from `CPU_CAPACITY <- parallel::detectCores(logical = FALSE)` through `DEV_MODE <- FALSE` (lines ~15-30) with:

```r
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
  v <- suppressWarnings(as.integer(Sys.getenv("CRDC_NTHREADS", "4"))); if (is.na(v)) 4L else v
}
NCHAINS <- {
  v <- suppressWarnings(as.integer(Sys.getenv("CRDC_NCHAINS", "4"))); if (is.na(v)) 4L else v
}
# Number of chains that can run in parallel given the core budget.
N_PAR_CHAINS <- CPU_CAPACITY %/% NTHREADS

# DEV_MODE greatly reduces runtime to confirm the pipeline works end-to-end before
# committing to the full multi-day run. Toggle WITHOUT editing this file:
#   CRDC_DEV_MODE=true Rscript -e 'targets::tar_make(...)'   (see scripts/smoke-pipeline.sh)
DEV_MODE <- isTRUE(as.logical(Sys.getenv("CRDC_DEV_MODE", "FALSE")))
```

(The existing `enroll_cap`, `NITER`, `ITER_MULTIPLIER`, and the `N_PAR_CHAINS > NCHAINS` normalization below stay as-is — they already derive from these.)

- [ ] **Step 2: Verify `_targets.R` still sources and the toggle works**

Run:
```bash
Rscript -e 'Sys.setenv(CRDC_DEV_MODE="true"); source("_targets.R"); cat("DEV_MODE=", DEV_MODE, " enroll_cap=", enroll_cap, " NITER=", NITER, "\n")'
```
Expected: `DEV_MODE= TRUE enroll_cap= 5000 NITER= 500` (sourcing requires tarchetypes/crew/etc. installed — they are on this box).

- [ ] **Step 3: Verify default (no env) stays FALSE**

Run: `Rscript -e 'source("_targets.R"); cat("DEV_MODE=", DEV_MODE, "\n")'`
Expected: `DEV_MODE= FALSE`.

- [ ] **Step 4: Commit**

```bash
git add _targets.R
git commit -m "feat(repro): env-overridable DEV_MODE/cores/threads + sizing guidance"
```

---

## Task 8: Point `api_db` / `draws_parquet` targets at the hardened wrappers

**Files:**
- Modify: `_targets.R` — `tar_source` list (line ~108) and the `api_db` (lines ~590-611) + `draws_parquet` (lines ~612-625) target bodies

- [ ] **Step 1: Source the new R file**

In `_targets.R`, add to the `tar_source(...)` block (after `tar_source("R/export_parquet.R")`):

```r
tar_source("R/build_api_artifacts.R")
```

- [ ] **Step 2: Replace the `api_db` target body**

Replace the `api_db` target (the `tar_target(api_db, { ... }, format = "file")` block) with:

```r
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
```

- [ ] **Step 3: Replace the `draws_parquet` target body**

Replace the `draws_parquet` target block with:

```r
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
```

- [ ] **Step 4: Validate the pipeline graph still parses (no fitting)**

Run: `Rscript -e 'library(tarchetypes); targets::tar_validate()'`
Expected: completes with no error (empty output). This confirms the new functions resolve and the DAG is intact.

- [ ] **Step 5: Commit**

```bash
git add _targets.R
git commit -m "refactor(repro): api_db/draws_parquet use hardened retained-driver builders"
```

---

## Task 9: One-command DEV_MODE smoke script

**Files:**
- Create: `scripts/smoke-pipeline.sh`

- [ ] **Step 1: Write the smoke script**

Create `scripts/smoke-pipeline.sh`:

```bash
#!/usr/bin/env bash
# DEV_MODE smoke: prove the toolchain + dependency graph end-to-end on a small
# build (reduced iterations + high enrollment cap) WITHOUT the multi-day run.
# Builds nat_m1_mod and its upstream data-prep targets. Requires CmdStan (run
# setup.R first). NEVER run this in CI — it fits a model.
set -euo pipefail
cd "$(dirname "$0")/.."

export CRDC_DEV_MODE=true
echo "== DEV_MODE smoke: building nat_m1_mod (+ upstream) with reduced iters/enroll cap =="
echo "   (expect a few minutes once CmdStan is set up; this proves the pipeline runs)"
Rscript -e 'targets::tar_make(names = "nat_m1_mod")'
echo "== Smoke build complete. Inspect with: Rscript -e 'targets::tar_read(nat_m1_mod)' =="
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/smoke-pipeline.sh && bash -n scripts/smoke-pipeline.sh && echo "syntax ok"`
Expected: `syntax ok`.

(Do **not** execute the smoke here — it fits a model and needs CmdStan. It is documented for the stranger and for local verification.)

- [ ] **Step 3: Commit**

```bash
git add scripts/smoke-pipeline.sh
git commit -m "feat(repro): one-command DEV_MODE smoke script"
```

---

## Task 10: HEAVY VERIFICATION — rebuild api_db + draws_parquet from the real 69 GB DB

> **GATED:** Do not start this task without explicit user confirmation. It reads the live `export/db/crdc_arrests.duckdb` (69 GB, 1.14 B rows), runs ~20 min, and uses bounded memory. Its purpose is to prove the *committed* pipeline path (Tasks 4-8) builds within 63 GB.

**Files:** none (verification only)

- [ ] **Step 1: Confirm the source DB exists**

Run: `ls -lh export/db/crdc_arrests.duckdb`
Expected: ~69 GB file present. If absent, this verification cannot run — record that and skip to Task 11, noting the heavy path is unverified.

- [ ] **Step 2: Ask the user to confirm kicking off the ~20-min build.** Wait for explicit yes.

- [ ] **Step 3: Build only the two artifact targets (and any missing upstream lookups), bounded**

Run (background-capable; ~20 min):
```bash
Rscript -e 'targets::tar_make(names = c("api_db", "draws_parquet"))' 2>&1 | tee tmp/heavy_verify.log
```
Expected: both targets complete; no "Invalid connection"; no OOM/crash. Peak RSS should stay well under 63 GB (memory_limit ≈ 70% of RAM + spill to `tmp/duckdb_spill`).

- [ ] **Step 4: Validate outputs**

Run:
```bash
Rscript -e '
  acon <- DBI::dbConnect(duckdb::duckdb(), dbdir="export/api/crdc_api.duckdb", read_only=TRUE)
  print(DBI::dbListTables(acon))
  cat("arrest_summary rows:", DBI::dbGetQuery(acon,"SELECT COUNT(*) n FROM arrest_summary")$n, "\n")
  DBI::dbDisconnect(acon, shutdown=TRUE)
  pq <- list.files("export/parquet", pattern="\\.parquet$", recursive=TRUE)
  cat("parquet shards:", length(pq), "\n")'
```
Expected: tables `arrest_summary, state_summary, district_dim, meta` present; non-zero row counts; many parquet shards.

- [ ] **Step 5: Record the result** in `tmp/heavy_verify.log` (already tee'd). No commit (outputs are gitignored under `/export`).

---

## Task 11: REPRODUCIBILITY.md + README fixes

**Files:**
- Create: `REPRODUCIBILITY.md`
- Modify: `README.md`

- [ ] **Step 1: Write `REPRODUCIBILITY.md`**

Create `REPRODUCIBILITY.md`:

```markdown
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
```

- [ ] **Step 2: Fix README prerequisites (R version, CmdStan, drop stantargets)**

In `README.md`, change the prerequisites table row `| **R** | 4.4.x | Tested on R 4.4.3 (Linux) |` to:

```markdown
| **R** | 4.6.0 | Pinned via `renv.lock`; see [REPRODUCIBILITY.md](REPRODUCIBILITY.md) |
```

Change the CmdStan row to name 2.37.0:

```markdown
| **CmdStan** | 2.37.0 | Required for `cmdstanr` backend (installed via `setup.R`) |
```

In the `install.packages(c(...))` block, remove `"stantargets"` (unused legacy) so the line reads:

```r
install.packages(c(
  "targets", "tarchetypes",
  "tibble", "dplyr", "tidyr", "qs2", "quarto",
  "brms", "cmdstanr", "crew", "future.callr",
  "educationdata"
), repos = "https://cloud.r-project.org")
```

- [ ] **Step 3: Add a reproducibility pointer near "Usage"**

In `README.md`, immediately under the `## Usage` heading, add:

```markdown
> **New here?** Start with [REPRODUCIBILITY.md](REPRODUCIBILITY.md) — it covers
> `setup.R`, the multi-day compute reality, and how to size the run to your
> hardware (the MCMC-parallelism × RAM tradeoff). Use `scripts/smoke-pipeline.sh`
> (DEV_MODE) to validate your setup in minutes before the full run.
```

- [ ] **Step 4: Commit**

```bash
git add REPRODUCIBILITY.md README.md
git commit -m "docs(repro): REPRODUCIBILITY.md + README toolchain/sizing fixes"
```

---

## Task 12: Parse-only CI validation job

**Files:**
- Modify: `.gitea/workflows/test.yml`

- [ ] **Step 1: Append a `pipeline-validate` job**

Add this job to `.gitea/workflows/test.yml` (sibling of `r-tests`, same shell-checkout pattern — the runner has no node and advertises `ubuntu-latest`):

```yaml
  pipeline-validate:
    runs-on: ubuntu-latest
    container: rocker/r-ver:4.6.0
    steps:
      - name: Checkout (shell, no node)
        env:
          REPO_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          apt-get update -qq && apt-get install -y --no-install-recommends git ca-certificates
          host="${GITHUB_SERVER_URL#https://}"; host="${host:-gitea.civilytics.org}"
          tmpd="$(mktemp -d)"
          git clone --depth 1 --branch "${GITHUB_REF_NAME:-main}" \
            "https://oauth2:${REPO_TOKEN}@${host}/${GITHUB_REPOSITORY:-jared/crdc-arrests}.git" "$tmpd"
          cp -a "$tmpd/." . && rm -rf "$tmpd"
      - name: Install source-time deps (NO model packages)
        run: |
          apt-get update && apt-get install -y --no-install-recommends \
            libcurl4-openssl-dev libssl-dev libz-dev
          install2.r --error targets tarchetypes tibble dplyr tidyr \
            future future.callr crew DBI duckdb
      - name: Validate pipeline graph (parses, loads, NO fitting)
        run: Rscript -e 'library(tarchetypes); targets::tar_validate()'
```

- [ ] **Step 2: Lint the YAML locally**

Run: `Rscript -e 'cat(if (requireNamespace("yaml", quietly=TRUE)) {yaml::read_yaml(".gitea/workflows/test.yml"); "yaml ok"} else "yaml pkg absent; skip", "\n")'`
Expected: `yaml ok` (or a skip note). If `yaml` is absent, instead eyeball indentation against the existing `r-tests` job.

- [ ] **Step 3: Locally simulate the validate step against the current library**

Run: `Rscript -e 'library(tarchetypes); targets::tar_validate(); cat("tar_validate clean\n")'`
Expected: `tar_validate clean` (proves `_targets.R` sources and the graph is valid with only source-time packages loaded). If it errors on a missing package loaded at source time, add that package to the `install2.r` line in Step 1 and re-run.

- [ ] **Step 4: Commit**

```bash
git add .gitea/workflows/test.yml
git commit -m "ci(repro): parse-only tar_validate job (no model fitting)"
```

---

## Task 13: renv environment capture (hydrate — no recompile)

> Run this near the end: it flips the project to an renv-managed library. We
> populate that library by **hydrating** already-installed packages (symlink/copy,
> no brms/Stan recompile), then snapshot. A `_packages.R` file makes renv discover
> packages that appear only as strings (e.g. `cmdstanr`, `qs2` in
> `tar_option_set(packages=)`).

**Files:**
- Create: `_packages.R`
- Create (by renv): `renv.lock`, `.Rprofile`, `renv/activate.R`, `renv/settings.json`
- Modify: `.gitignore`

- [ ] **Step 1: Ensure the two missing runtime packages are installed**

Run: `Rscript -e 'for (p in c("cmdstanr","qs2")) cat(p, requireNamespace(p, quietly=TRUE), "\n")'`
Expected: both `TRUE`. If `cmdstanr FALSE`, install it (pure-R, light):
```bash
Rscript -e 'install.packages("cmdstanr", repos=c("https://stan-dev.r-universe.dev", getOption("repos")))'
```
Re-run the check until both are `TRUE`.

- [ ] **Step 2: Create `_packages.R` for renv discovery**

Create `_packages.R` at the repo root:

```r
# Dependency declarations for renv discovery ONLY (not executed by the pipeline).
# _targets.R loads several packages via tar_option_set(packages=) as bare strings,
# and uses cmdstanr only as backend="cmdstanr" — renv's static scan misses those.
# Listing them here ensures renv.lock captures the full runtime closure.
library(targets)
library(tarchetypes)
library(tibble)
library(dplyr)
library(tidyr)
library(knitr)
library(qs2)
library(quarto)
library(brms)
library(cmdstanr)
library(crew)
library(future.callr)
library(educationdata)
library(DBI)
library(duckdb)
library(posterior)
```

- [ ] **Step 3: Initialize renv (bare) and hydrate from the existing library**

Run:
```bash
Rscript -e 'renv::init(bare = TRUE, restart = FALSE)'
Rscript -e 'renv::hydrate()'   # copies/symlinks already-installed pkgs into renv/library (no recompile)
```
Expected: renv creates `.Rprofile`, `renv/activate.R`, `renv/settings.json`, and populates `renv/library/` from the system/user library.

- [ ] **Step 4: Snapshot to produce `renv.lock`**

Run: `Rscript -e 'renv::snapshot(prompt = FALSE)'`
Expected: writes `renv.lock`.

- [ ] **Step 5: Verify the lock captured the string-only deps and R 4.6.0**

Run:
```bash
Rscript -e '
  lf <- jsonlite::read_json("renv.lock")
  cat("R:", lf$R$Version, "\n")
  pk <- names(lf$Packages)
  need <- c("cmdstanr","qs2","brms","targets","tarchetypes","duckdb","educationdata","crew")
  miss <- setdiff(need, pk)
  if (length(miss)) stop("renv.lock MISSING: ", paste(miss, collapse=", "))
  cat("all required packages present (", length(pk), "total)\n")'
```
Expected: `R: 4.6.0` and `all required packages present`. If any are missing, add a `library()` for them to `_packages.R` and re-run Steps 4-5.

- [ ] **Step 6: Verify the box still works under the renv library**

Run: `Rscript -e 'library(tarchetypes); targets::tar_validate(); cat("renv project loads + validates\n")'`
Expected: `renv project loads + validates` (hydrate populated `renv/library`, so the pipeline still sources).

- [ ] **Step 7: Update `.gitignore` (ignore the library, track the lock)**

Ensure `.gitignore` contains (renv::init usually adds the first block; add any missing lines):

```gitignore
# renv
renv/library/
renv/local/
renv/cellar/
renv/staging/
```

Confirm `renv.lock`, `.Rprofile`, `renv/activate.R`, `renv/settings.json` are **not** ignored:

Run: `git check-ignore -v renv.lock .Rprofile renv/activate.R || echo "tracked (good)"`
Expected: `tracked (good)` (no output from check-ignore means they are not ignored).

- [ ] **Step 8: Commit**

```bash
git add _packages.R renv.lock .Rprofile renv/activate.R renv/settings.json .gitignore
git commit -m "feat(repro): renv.lock + .Rprofile via hydrate (R 4.6.0; cmdstanr/qs2 captured)"
```

---

## Task 14: setup.R bootstrap script

**Files:**
- Create: `setup.R`

- [ ] **Step 1: Write `setup.R`**

Create `setup.R` at the repo root:

```r
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
```

- [ ] **Step 2: Syntax-check it (no execution — restore/install are heavy)**

Run: `Rscript -e 'invisible(parse("setup.R")); cat("setup.R parses\n")'`
Expected: `setup.R parses`.

- [ ] **Step 3: Commit**

```bash
git add setup.R
git commit -m "feat(repro): setup.R bootstrap (renv::restore + CmdStan 2.37.0 + checks)"
```

---

## Task 15: Prune superseded `tmp/` scripts

**Files:**
- Delete: superseded `tmp/*.R` + their `*.log` (now folded into `R/`); **keep** `tmp/data/` and `tmp/duckdb_spill/`

- [ ] **Step 1: Confirm nothing under tmp/ is tracked**

Run: `git ls-files tmp/ | wc -l`
Expected: `0` (`/tmp` is gitignored). These deletions are local cleanup only.

- [ ] **Step 2: Remove the superseded reference scripts and logs**

Run:
```bash
rm -f tmp/build_api_artifacts.R tmp/build_api_artifacts.log \
      tmp/export_parquet_chunked.R tmp/export_parquet_chunked.log \
      tmp/validate_api_artifacts.R tmp/health_poll.log
ls tmp/
```
Expected: `tmp/` retains `data/` and `duckdb_spill/` (and any still-relevant files like `build_pages.R`/`hf_dataset_card.md` — leave those; they belong to subsystem 1/3, out of scope here).

- [ ] **Step 3: No commit** (nothing tracked). Proceed to Task 16.

---

## Task 16: Full suite green + branch wrap-up

**Files:** none (verification + handoff)

- [ ] **Step 1: Run the entire test suite**

Run: `./scripts/run-tests.sh`
Expected: `All tests passed.` (data-layer suite incl. download-paths, export_parquet, build_api_artifacts; plus the API suite).

- [ ] **Step 2: Final pipeline validate under renv**

Run: `Rscript -e 'library(tarchetypes); targets::tar_validate(); cat("OK\n")'`
Expected: `OK`.

- [ ] **Step 3: Review the full diff against main**

Run: `git --no-pager diff --stat main...HEAD`
Expected: changes across `R/`, `_targets.R`, `tests/`, `setup.R`, `REPRODUCIBILITY.md`, `README.md`, `DOWNLOAD_GUIDE.md`, `.gitea/workflows/test.yml`, `renv.lock`, `.Rprofile`, `_packages.R`, `.gitignore`.

- [ ] **Step 4: Hand off for review/merge** using `superpowers:finishing-a-development-branch`. Do **not** push without user confirmation (remotes dual-push to public GitHub; prefix git/gh with `GITHUB_TOKEN= GH_TOKEN=` if a stale token shadows auth).

---

## Self-Review (completed during planning)

**Spec coverage:** §A → Tasks 13, 14; §B → Tasks 2, 3; §C → Tasks 4, 5, 6, 8; §D → Tasks 7, 9; §E → Tasks 7 (code), 11 (docs); §F → Task 12; §G → Tasks 1, 15; §H → Tasks 5/4 (fixture tests), 10 (heavy run), 16 (full suite). All spec sections map to tasks.

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every command has expected output.

**Type/name consistency:** `crdc_expected_paths(year, dest_dir)` returns `list(enrollment_path, le_path)` — used identically in Tasks 2/3. `build_api_db(draws_db_path, api_path, enroll_lookup, district_dim, data_release, memory_limit, threads, temp_dir)` and `build_draws_parquet(draws_db_path, out_dir, memory_limit, threads, temp_dir)` and `duckdb_mem_limit_gb()` / `open_draws_con()` / `close_draws_con()` are defined in Task 5 and called consistently in Task 8 and tests. `export_draws_parquet(draws_con, out_dir, memory_limit, threads, temp_dir)` signature consistent across Tasks 4/5. Table names `arrest_summary`/`state_summary`/`district_dim`/`meta` match `R/summarize_draws.R`. Env vars `CRDC_DEV_MODE`/`CRDC_CORES`/`CRDC_NTHREADS`/`CRDC_NCHAINS` consistent across Tasks 7, 9, 11.
