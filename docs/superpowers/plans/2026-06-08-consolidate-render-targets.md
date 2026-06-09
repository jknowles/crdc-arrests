# Consolidate Subsystem-3 Render Targets (5 → 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge `results.qmd`, `applied_examples.qmd`, and `combined_eda.qmd` into one `supplement.qmd` (Supplementary Materials), leaving three render targets: `white_paper.qmd` (paper), `supplement.qmd`, `social_media_posts.qmd`.

**Architecture:** A single new `supplement.qmd` with one unified setup chunk and four narrative parts (EDA → sample construction → model diagnostics → applied examples). Content is copied verbatim from the three (already-working) source docs, with only the targeted transformations below. Per the transparency principle, analytical/labeling code is inlined in the doc; the documented artifact-access layer stays sourced from `R/`.

**Tech Stack:** Quarto + knitr (R), DuckDB (draws view), dplyr/ggplot2/patchwork/ggridges, tigris/sf (maps), `targets`/`tarchetypes` (render targets).

**Spec:** `docs/superpowers/specs/2026-06-08-consolidate-render-targets-design.md`

**Key facts established during planning (do not re-derive):**
- Across the three source files the ONLY duplicate chunk labels are `setup` and `cleanup`; every other label is already unique, so no mass relabeling is needed.
- The ONLY cross-file object collisions are `combined_data`, `dist_test`, and the setup-level `h`/`rdata`/`tydata`.
- The three source files remain present until Task 6, so body chunks can be copied from them by line range during Tasks 2–5.
- Render locally with `CRDC_ARTIFACTS=export` (draws live in `export/parquet`, Hive-partitioned by `model_id`).
- Reusable verification commands:
  - **Duplicate-label check:** `grep -hE '^#\| label:' supplement.qmd | sed 's/#| label: *//' | sort | uniq -d` → expect NO output.
  - **R syntax check:** `Rscript -e 'invisible(parse(text = knitr::purl("supplement.qmd", output = tempfile(fileext = ".R"), quiet = TRUE) |> readLines() |> paste(collapse = "\n")))'` → expect no error.
  - **Full render:** `CRDC_ARTIFACTS=export quarto render supplement.qmd` → exit 0, `Output created: supplement.html`.

---

## File Structure

- **Create:** `supplement.qmd` — the merged Supplementary Materials document (built across Tasks 1–5).
- **Modify:** `_targets.R` — swap three `tar_render` targets for one (Task 6).
- **Modify:** `scripts/render-artifacts.sh` — update the `DOCS` list (Task 6).
- **Modify:** `README.md` — update the Subsystem-3 file list (Task 6).
- **Delete:** `results.qmd`, `applied_examples.qmd`, `combined_eda.qmd` (Task 6).

---

## Task 1: Scaffold `supplement.qmd` (YAML + intro + unified setup)

**Files:**
- Create: `supplement.qmd`

- [ ] **Step 1: Create the file with YAML, intro, and the unified setup chunk**

Write `supplement.qmd` with exactly this content:

````markdown
---
title: "Supplementary Materials: Equity Analysis at a Large Scale (CRDC School Arrests)"
author:
  - name: "Jared E. Knowles"
    affiliation: "Civilytics Consulting"
  - name: "Hannah Miller"
    affiliation: "Civilytics Consulting"
format:
  html:
    theme: theme/civilytics.scss
    css: theme/extras.css
    toc: true
    toc-location: right
    toc-depth: 3
    embed-resources: true
execute:
  echo: false
  warning: false
  message: false
  error: false
knitr:
  opts_chunk:
    fig.path: export/figures/supplement-
---

This document collects the supplementary materials for the white paper *Equity
Analysis at a Large Scale: Using Small Area Estimation to Get the Most from the
CRDC School Arrest Data*. It has four parts: exploratory analysis of the combined
three-year CRDC data, the data-construction and sample-restriction details,
model performance and diagnostics, and additional applied prediction-interval
examples. The headline tables and figures, and the national descriptive totals
by race and sex, are reported in the paper itself (`white_paper.html`); this
companion holds the supporting detail. Like the paper, every section reads the
published artifacts via `crdc_path()` and renders standalone.

```{r}
#| label: setup
#| include: false

# Libraries (union of the three merged source documents)
library(targets)
library(brms)
library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(ggdist)
library(marginaleffects)
library(tidybayes)
library(ggridges)
library(patchwork)
library(duckdb)
library(knitr)

options(scipen = 9)
options(width = 120)
if (!dir.exists("export/figures")) dir.create("export/figures", recursive = TRUE)

# --- Artifact-access layer (documented reproduction interface; kept sourced) ---
source("R/funs.R")
source("R/crdc_path.R"); source("R/model_registry.R"); source("R/paper_figures.R")
cv_apply_branding()                    # civilytics theme on all figures
h <- open_draws_view(); con <- h$con   # predicted_draws view over published parquet

# --- Inputs (loaded once for all sections) ---
tydata <- read_stage_df("stages/inputs/three_year_data.parquet")
rdata  <- read_stage_df("stages/inputs/recent_data.parquet")
y2122  <- read_stage_df("stages/crdc/full_crdc_data_y2122.parquet")

# National 2021-22 arrest rate used by the District Concentration analysis (Part 2)
nat_totals <- y2122 |>
  ungroup() |>
  filter(RACE == "TOTAL" & SEX == "TOTAL") |>
  summarize(
    all_lea_count = n_distinct(LEAID),
    lea_any_arr   = n_distinct(LEAID[ARRESTS > 0]),
    enrollment    = sum(stu_enroll),
    arrests       = sum(ARRESTS),
    referrals     = sum(REFERRALS))
nat_arrest_rate <- nat_totals$arrests / (nat_totals$enrollment / 1000)

# Combined three-year frame + canonical (most-recent-wave) LEA name (Part 1 EDA)
combined_data <- read_stage_df("stages/inputs/combined_model_data.parquet")
combined_data |>
  select(LEAID, LEA_NAME, YEAR) |>
  distinct_all() |>
  group_by(LEAID) |>
  mutate(last_name = ifelse(any(YEAR == "21-22"), LEA_NAME[YEAR == "21-22"],
                     ifelse(any(YEAR == "17-18"), LEA_NAME[YEAR == "17-18"],
                            LEA_NAME[YEAR == "15-16"]))) |>
  ungroup() |>
  select(LEAID, last_name) |>
  distinct_all() -> lea_names_canonical
combined_data <- left_join(combined_data |> select(-LEA_NAME),
                           lea_names_canonical |> rename(LEA_NAME = last_name),
                           by = join_by(LEAID))
rm(lea_names_canonical)

# State shapes for the EDA choropleths (Part 1)
state_map <- tigris::states(cb = TRUE, resolution = "20m") |> tigris::shift_geometry()

# --- Colour palettes (inlined for transparency) ---
color_fill_values  <- c("WH" = "#c92d0e", "BL" = "#020684", "AM" = "#ff8f43",
                        "TOTAL" = "#909090ff", "HI" = "#0791b6")
color_fill_values2 <- c("White" = "#c92d0e", "Black" = "#020684",
                        "Total" = "#909090ff", "Hispanic" = "#0791b6",
                        "Amer. Ind." = "#ff8f43")
model_palette <- c("Modeled" = "#000a9bff", "Frequentist" = "#858585bb")
group_palette <- c("WH" = "#09d2ecc2", "BL" = "#ab00a9f1", "HI" = "#00ab17f1")

# --- Model-labelling helpers (inlined for transparency; used by Parts 3-4) ---
add_model_time <- function(x) {
  y <- rep("One year", length(x))
  y[x %in% c("nat_m3_mod", "nat_m4_mod", "nat_m5_mod",
             "sg_m3_mod", "sg_m4_mod", "sg_m5_mod")] <- "Three year"
  y
}
add_model_form <- function(x) {
  y <- rep("Stratified", length(x)); y[startsWith(x, "nat")] <- "Unified"; y
}
add_model_cov <- function(x) {
  y <- rep("Baseline", length(x))
  y[x %in% c("sg_m2_mod", "nat_m4_mod", "nat_m5_mod",
             "nat_m2_mod", "sg_m4_mod", "sg_m5_mod")] <- "Covariate"
  y
}
print_model_name <- function(x, lbreak = FALSE) {
  y <- rep("Stratified", length(x)); y[startsWith(x, "nat")] <- "Unified"
  x <- gsub("_mod", "", x); x <- gsub("nat_m", "", x); x <- gsub("sg_m", "", x)
  if (lbreak) paste0(y, "\nModel:", x) else paste0(y, " Model:", x)
}

# --- Agresti-Coull frequentist interval (inlined; used by Part 4 examples) ---
agresti_coull <- function(numerator, denominator, confidence_level = 0.95) {
  adj_star <- qnorm(1 - (1 - confidence_level) / 2)
  if (numerator > 0) {
    num_star   <- numerator + adj_star
    denom_star <- denominator + (2 * adj_star)
    phat       <- num_star / denom_star
    phat_se    <- sqrt((phat / denom_star) * (1 - phat))
    ci_upper   <- (phat + (adj_star * phat_se)) * denom_star
    ci_lower   <- (phat - (adj_star * phat_se)) * denom_star
    sd         <- phat_se * denom_star
  } else {
    ci_upper <- denominator * (-log(1 - confidence_level) / denominator)
    ci_lower <- 0
    sd       <- mean(c(ci_upper, ci_lower)) / confidence_level
    phat_se  <- 0
    phat     <- mean(c(ci_upper, ci_lower))
  }
  c(ci_upper, ci_lower, sd, phat_se, phat)
}
```
````

- [ ] **Step 2: Static syntax + label check**

Run: `grep -hE '^#\| label:' supplement.qmd | sed 's/#| label: *//' | sort | uniq -d`
Expected: no output (only `setup` exists so far).

Run: `Rscript -e 'invisible(parse(text = paste(readLines(knitr::purl("supplement.qmd", output = tempfile(fileext = ".R"), quiet = TRUE)), collapse = "\n")))'`
Expected: no error.

- [ ] **Step 3: Render the scaffold to confirm the setup chunk executes**

Run: `CRDC_ARTIFACTS=export quarto render supplement.qmd`
Expected: exit 0, `Output created: supplement.html`. (This proves all sources, the draws view, the data loads, and the inline helpers/palettes work before any sections are added.)

- [ ] **Step 4: Commit**

```bash
git add supplement.qmd
git commit -m "feat(reports): scaffold supplement.qmd (unified setup) for 5->3 merge"
```

---

## Task 2: Part 1 — Exploratory Data Analysis (from `combined_eda.qmd`)

**Files:**
- Modify: `supplement.qmd` (append)
- Source (copy from): `combined_eda.qmd` lines 71–493 (everything after its setup chunk)

- [ ] **Step 1: Append the Part 1 header and the EDA body**

Append to `supplement.qmd`:

```markdown
# Part 1 — Exploratory Data Analysis

This part explores the combined three-year CRDC data (2015-16, 2017-18,
2021-22). Counts and rates here are pooled across all three waves unless stated
otherwise, and so differ from the single-wave 2021-22 figures in the paper.
```

Then copy `combined_eda.qmd` **lines 71–493 verbatim** (from `## Basic Data Structure` through the end, including the `badcells` chunk) and paste them below that header. Do NOT copy combined_eda's setup chunk (lines 1–69) — it is already folded into the unified setup.

- [ ] **Step 2: Append an end-of-Part-1 memory-free chunk**

After the pasted EDA content, append:

````markdown
```{r}
#| label: eda-free-memory
#| include: false
# The combined three-year frame and state shapes are only used by Part 1; free
# them before the heavier draws queries in Parts 3-4.
rm(combined_data, state_map); gc()
```
````

- [ ] **Step 3: Static syntax + duplicate-label check**

Run: `grep -hE '^#\| label:' supplement.qmd | sed 's/#| label: *//' | sort | uniq -d`
Expected: no output.

Run: `Rscript -e 'invisible(parse(text = paste(readLines(knitr::purl("supplement.qmd", output = tempfile(fileext = ".R"), quiet = TRUE)), collapse = "\n")))'`
Expected: no error.

- [ ] **Step 4: Commit**

```bash
git add supplement.qmd
git commit -m "feat(reports): supplement Part 1 (EDA) from combined_eda"
```

---

## Task 3: Part 2 — Data Construction & Sample Restrictions (from `results.qmd`)

**Files:**
- Modify: `supplement.qmd` (append)
- Source (copy from): `results.qmd` lines 96–453 (Sample Continuity through Censored enrollment)

- [ ] **Step 1: Append the Part 2 header and body**

Append to `supplement.qmd`:

```markdown
# Part 2 — Data Construction & Sample Restrictions

This part documents how the analytic sample is built from the raw CRDC and the
magnitude of each restriction the paper describes. The national descriptive
totals and rates by race and sex are reported in the paper (`white_paper.html`).
```

Then copy `results.qmd` **lines 96–453 verbatim** — from `# Sample Continuity Analysis for CRDC Waves` (L96) through the end of the `compute-incomplete-enrollments` chunk (L453, the line ```` ``` ```` that closes it). Do NOT copy `results.qmd` lines 87–94 (the `# Descriptive Statistics from Most Recent CRDC Wave` pointer note — its content is now in the supplement intro).

Then change every top-level header copied in from `#` (h1, e.g. `# Sample Continuity Analysis for CRDC Waves`) to `##` (h2), so they nest under "Part 2". The h1 headers to demote are: `# Sample Continuity Analysis for CRDC Waves`, `# District Concentration Analysis`, `# Sample Restriction Impact`. (Their existing `##` subsections become `###` — demote those one level too.)

- [ ] **Step 2: Apply the `combined_data` collision renames**

In the pasted Part 2 content, the grade-level and enrollment-threshold sections reload `combined_model_data.parquet` into `combined_data`, which would clobber nothing now (Part 1 freed it) but must not be confused with it. Rename within those two chunks only:

In the `compute-grade-restrictions` chunk, replace:
```r
combined_data <- read_stage_df("stages/inputs/combined_model_data.parquet") |> filter(YEAR == "21-22")
combined_data2 <- combined_data |> filter(highest_grade_offered >= 7)

grade_restriction_summary <- combined_data |>
```
with:
```r
gr_data <- read_stage_df("stages/inputs/combined_model_data.parquet") |> filter(YEAR == "21-22")
gr_data2 <- gr_data |> filter(highest_grade_offered >= 7)

grade_restriction_summary <- gr_data |>
```

In the `compute-enrollment-thresholds` chunk, replace:
```r
combined_data <- read_stage_df("stages/inputs/combined_model_data.parquet") |> filter(YEAR == "21-22")
combined_data <- crdc_lea_collapse(combined_data)

enrollment_threshold_summary <- combined_data |>
```
with:
```r
thr_data <- read_stage_df("stages/inputs/combined_model_data.parquet") |> filter(YEAR == "21-22")
thr_data <- crdc_lea_collapse(thr_data)

enrollment_threshold_summary <- thr_data |>
```

- [ ] **Step 3: Static syntax + duplicate-label check**

Run: `grep -hE '^#\| label:' supplement.qmd | sed 's/#| label: *//' | sort | uniq -d`
Expected: no output.

Run: `Rscript -e 'invisible(parse(text = paste(readLines(knitr::purl("supplement.qmd", output = tempfile(fileext = ".R"), quiet = TRUE)), collapse = "\n")))'`
Expected: no error.

- [ ] **Step 4: Commit**

```bash
git add supplement.qmd
git commit -m "feat(reports): supplement Part 2 (data construction) from results"
```

---

## Task 4: Part 3 — Model Performance & Diagnostics (from `results.qmd`)

**Files:**
- Modify: `supplement.qmd` (append)
- Source (copy from): `results.qmd` lines 455–870 (Model Predictions & Performance through State Performance display), EXCLUDING the final `cleanup` chunk (L871–876)

- [ ] **Step 1: Append the Part 3 header and body**

Append to `supplement.qmd`:

```markdown
# Part 3 — Model Performance & Diagnostics
```

Then copy `results.qmd` **lines 455–870 verbatim** — from `# Model Predictions and Performance` (L455) through the end of the `display-state-performance` chunk (the ```` ``` ```` closing it at ~L870). **Do NOT copy the final `cleanup` chunk** (`#| label: cleanup` with `close_draws_view(h)`, ~L871–876) — a single cleanup is added at the very end of the document in Task 5.

Then demote the copied h1 headers to h2 (and their `##` subsections to `###`): `# Model Predictions and Performance`, `# Model Performance Diagnostics`, `# Subgroup Analysis`, `# Model Computation Statistics`, `# State-Level Analysis`.

- [ ] **Step 2: Fix the pre-state-analysis `rm()` chunk for the renamed objects**

In the copied content there is an unlabeled `rm(...)` chunk at the start of the State-Level Analysis section (originally `results.qmd` ~L772–773). It references `combined_data` / `combined_data2`, which no longer exist under those names. Replace:
```r
rm(dist_ref_arr, dist_test, enrollment,
      obsv_data, combined_data, combined_data2, plotdf); gc()
```
with:
```r
rm(dist_ref_arr, dist_test, enrollment,
      obsv_data, gr_data, gr_data2, thr_data, plotdf); gc()
```

- [ ] **Step 3: Static syntax + duplicate-label check**

Run: `grep -hE '^#\| label:' supplement.qmd | sed 's/#| label: *//' | sort | uniq -d`
Expected: no output (the results `cleanup` was intentionally NOT copied).

Run: `Rscript -e 'invisible(parse(text = paste(readLines(knitr::purl("supplement.qmd", output = tempfile(fileext = ".R"), quiet = TRUE)), collapse = "\n")))'`
Expected: no error.

- [ ] **Step 4: Commit**

```bash
git add supplement.qmd
git commit -m "feat(reports): supplement Part 3 (model performance + diagnostics) from results"
```

---

## Task 5: Part 4 — Applied Examples (from `applied_examples.qmd`) + final cleanup

**Files:**
- Modify: `supplement.qmd` (append)
- Source (copy from): `applied_examples.qmd` lines 163–673 (Multicomparison through plotstates), EXCLUDING setup/get_data (L1–142) and the final `cleanup` chunk (L674–679)

- [ ] **Step 1: Append the Part 4 header and body**

Append to `supplement.qmd`:

```markdown
# Part 4 — Applied Examples

These are additional applied prediction-interval examples beyond the case
studies in the paper: a cross-district comparison, a single-district temporal
comparison, a small-groups demographic disparity, and a national overview.
```

Then copy `applied_examples.qmd` **lines 163–673 verbatim** — from `## Multicomparison` (L163) through the end of the `plotstates` chunk (the ```` ``` ```` closing it at ~L673). **Do NOT copy** applied_examples' setup chunk, intro, or `get_data` chunk (L1–142, unused here — its `bigarr`/`big100`/`big0` are not referenced by these sections), and **do NOT copy** its final `cleanup` chunk (L674–679).

Then change the copied `## Multicomparison` and `## State example` (h2) to `## Cross-district, temporal, and small-group comparisons` and `## State-level overview` respectively (cosmetic; keeps them as h2 under Part 4). The deeper headers need no change.

- [ ] **Step 2: Apply the `dist_test` collision rename in the Baltimore chunk**

The `baltimorecityandcountydifferences` data-prep reuses the name `dist_test`, which collides with Part 3's `dist_test`. Open the copied `baltimorecityandcountydifferences` chunk and rename every occurrence of `dist_test` within that chunk to `balt_dist_test`. (Search the chunk for `dist_test`; there are assignment(s) and reference(s) — rename all of them. Confirm no other Part 4 chunk references `dist_test`.)

Verify the rename is localized:
Run: `awk '/label: baltimorecityandcountydifferences/{f=1} f&&/^```$/{c++} f&&c==1{print NR": "$0} c==2{f=0}' supplement.qmd | grep -n dist_test`
Expected: only `balt_dist_test` occurrences (no bare `dist_test`).

- [ ] **Step 3: Append the single final cleanup chunk**

Append to the very end of `supplement.qmd`:

````markdown
```{r}
#| label: cleanup
#| include: false
close_draws_view(h)
```
````

- [ ] **Step 4: Static syntax + duplicate-label check**

Run: `grep -hE '^#\| label:' supplement.qmd | sed 's/#| label: *//' | sort | uniq -d`
Expected: no output.

Run: `Rscript -e 'invisible(parse(text = paste(readLines(knitr::purl("supplement.qmd", output = tempfile(fileext = ".R"), quiet = TRUE)), collapse = "\n")))'`
Expected: no error.

- [ ] **Step 5: Full render (definitive verification)**

Run: `CRDC_ARTIFACTS=export quarto render supplement.qmd`
Expected: exit 0, `Output created: supplement.html`.

Then confirm all four parts and the pointer notes are present:
Run: `grep -c 'Part 1 — Exploratory\|Part 2 — Data\|Part 3 — Model\|Part 4 — Applied' supplement.html`
Expected: `4`.
Run: `grep -o 'not duplicated here' supplement.html | wc -l`
Expected: `>= 3` (the Table 3–6 pointer notes carried over from results).

- [ ] **Step 6: Commit**

```bash
git add supplement.qmd
git commit -m "feat(reports): supplement Part 4 (applied examples) + final cleanup; full render passes"
```

---

## Task 6: Wire up the repo and remove the three source docs

**Files:**
- Modify: `_targets.R`
- Modify: `scripts/render-artifacts.sh`
- Modify: `README.md`
- Delete: `results.qmd`, `applied_examples.qmd`, `combined_eda.qmd`

- [ ] **Step 1: `_targets.R` — remove the `combined_eda` render target**

Delete this block (currently ~L221–228, including the leading comment):
```r
  # Render EDA document for combined data (cue=never).
  tarchetypes::tar_render(
    name = combined_eda,
    path = "combined_eda.qmd",
    output_file = "crdc_combined_three_year_eda_report.html",
    cue = tar_cue(mode = "never")
  ),
```
(Leave the surrounding `combined_sch_data` / `three_year_data` targets intact, and keep comma balance — the block above ends in a comma; removing it must not leave a dangling or missing comma between the targets that bracketed it.)

- [ ] **Step 2: `_targets.R` — swap `results_report` + `applied_examples` for `supplement`**

In the Subsystem-3 group (currently ~L711–718), replace:
```r
  tarchetypes::tar_render(results_report, "results.qmd",
    output_file = "results.html", cue = tar_cue(mode = "never")),
  tarchetypes::tar_render(applied_examples, "applied_examples.qmd",
    output_file = "applied_examples.html", cue = tar_cue(mode = "never")),
```
with:
```r
  tarchetypes::tar_render(supplement, "supplement.qmd",
    output_file = "supplement.html", cue = tar_cue(mode = "never")),
```
(Keep `white_paper` above it and `social_media_posts` below it unchanged.)

- [ ] **Step 3: Verify `_targets.R` parses and the manifest is consistent**

Run: `Rscript -e 'invisible(parse("_targets.R")); cat("parse OK\n")'`
Expected: `parse OK`.

Run: `grep -nE 'combined_eda|results_report|applied_examples|results\.qmd|applied_examples\.qmd|combined_eda\.qmd' _targets.R`
Expected: no output (all references gone).

Run: `grep -nE 'supplement' _targets.R`
Expected: the new `tar_render(supplement, ...)` line.

- [ ] **Step 4: `scripts/render-artifacts.sh` — update the DOCS list**

Replace:
```bash
  DOCS=("white_paper.qmd" "results.qmd" "applied_examples.qmd"
        "social_media_posts.qmd" "combined_eda.qmd")
```
with:
```bash
  DOCS=("white_paper.qmd" "supplement.qmd" "social_media_posts.qmd")
```
Also update the header comment (line ~2) from `(white paper, results, applied examples, ...)` to `(white paper, supplement, social-media posts)`.

- [ ] **Step 5: `README.md` — update the Subsystem-3 file list**

Replace the five-line block:
```text
white_paper.qmd         The report (ported from the Word source), rebuilt from artifacts
results.qmd             Results engine: stats, tables, figures for the paper
applied_examples.qmd    Prediction-interval case studies
social_media_posts.qmd  Branded social-media figures/tables
combined_eda.qmd        Three-year combined exploratory analysis
```
with:
```text
white_paper.qmd         The report (ported from the Word source), rebuilt from artifacts
supplement.qmd          Supplementary Materials: EDA, sample construction, model
                        diagnostics, and additional applied examples
social_media_posts.qmd  Branded social-media figures/tables
```

- [ ] **Step 6: Check the Gitea `pages` deploy for stale links**

Run: `git grep -nE 'results\.html|applied_examples\.html|crdc_combined_three_year_eda_report\.html' -- . ':!docs/superpowers'`
Expected: no output. If any hits exist (e.g., a pages index), update them to `supplement.html`.

- [ ] **Step 7: Delete the three merged source docs**

```bash
git rm results.qmd applied_examples.qmd combined_eda.qmd
```

- [ ] **Step 8: Final verification render of the surviving targets**

Run: `CRDC_ARTIFACTS=export quarto render supplement.qmd`
Expected: exit 0, `Output created: supplement.html`.

Run: `CRDC_ARTIFACTS=export quarto render social_media_posts.qmd`
Expected: exit 0 (sanity: it was edited during dedup but not re-rendered since).

Run: `git status --short`
Expected: only the intended source changes (`_targets.R`, `scripts/render-artifacts.sh`, `README.md`, deleted `results.qmd`/`applied_examples.qmd`/`combined_eda.qmd`); HTML/figures are gitignored.

- [ ] **Step 9: Commit**

```bash
git add _targets.R scripts/render-artifacts.sh README.md supplement.qmd
git commit -m "refactor(reports): consolidate 5 render targets to 3 (paper / supplement / social)

Replace results.qmd + applied_examples.qmd + combined_eda.qmd with a single
supplement.qmd (Supplementary Materials). Update _targets.R, render-artifacts.sh,
and README accordingly. Per docs/superpowers/specs/2026-06-08-consolidate-render-targets-design.md."
```

---

## Self-Review (completed during planning)

- **Spec coverage:** 3-target end state (Tasks 1–6); narrative order EDA→construction→diagnostics→examples (Tasks 2–5); unified setup + inline helpers/palettes + sourced data-access (Task 1); chunk-label dedup `setup`/`cleanup` (Tasks 1, 4, 5); collision renames `combined_data`→`gr_data`/`thr_data` (Task 3), `dist_test`→`balt_dist_test` (Task 5); memory ordering (Tasks 2, 4); single `fig.path` (Task 1); `_targets.R`/`render-artifacts.sh`/`README`/pages wiring + deletions (Task 6); verification renders (Tasks 1, 5, 6). All spec sections map to a task.
- **Placeholder scan:** none — every transformation specifies exact text or exact source line ranges to copy.
- **Type/name consistency:** `gr_data`/`gr_data2`/`thr_data` introduced in Task 3 are exactly the names freed in Task 4's `rm()`; `balt_dist_test` (Task 5) is localized; `supplement` target name used consistently in Task 6.
