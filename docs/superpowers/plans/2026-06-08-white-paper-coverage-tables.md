# White Paper Coverage/Precision Tables (Tables 3–6) Implementation Plan — INLINE

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline; user preference) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 4 static, hand-ported coverage/precision tables (Tables 3–6) in `white_paper.qmd` with **inline, artifact-backed code chunks** that reproduce the published values from `crdc_path()`-resolved artifacts.

**Architecture (REVISED per user feedback):** **No builder functions.** Each table is computed by **native `dplyr`/DuckDB code written directly in `white_paper.qmd` chunks**, so an end user reproducing the findings reads the computation in the document itself — they never have to source or understand a helper in `R/paper_figures.R`. This honors the Subsystem-3 spec's locked decision #3 (native readers, no data-access wrappers) and the user preference recorded in the `prefer-inline-repro-docs` memory. A shared per-observation frame (`cov_obs`) is built once in a visible setup chunk; each table chunk filters + aggregates + `knitr::kable()`s it inline. Some aggregation code repeats across Tables 3–5 — that repetition is intentional and accepted (legibility for reproducers over DRY).

**Tech Stack:** R 4.6.0 (renv), DuckDB 1.5.2 via `open_draws_view()`/`get_prediction_summary()`/`get_prediction_draws()`, `dplyr`, Quarto 1.9.37.

**Branch:** create `feature/wp-coverage-tables` off `main` before Task 2.

---

## Pinned metric definitions (from Task 1 reconciliation, 2026-06-08)

Verified against the published static values on the current clean artifacts
(`/tmp/reconcile_wp_tables.R`). The per-observation frame mirrors `results.qmd:558-633`
(Agresti-Coull frequentist interval + `get_prediction_summary` modeled interval,
joined, converted to the per-1,000 rate scale, `sd==0` constants replaced with the
Agresti-Coull sd). All four columns aggregate per `model_id`:

| Column | Formula | Reconciliation |
|--------|---------|----------------|
| **Coverage** | `100 * mean(ci_lo <= rate & ci_hi >= rate)` | 30/30 exact (±0.04) |
| **Arrest rate precision (median)** | `mean(1 / sd_rate^2)` — header "(median)" = median *fitted value*, aggregation is the **mean** | 30/30 exact |
| **% equal or better intervals** | `100 * mean(fit_w <= obs_w)` — **`<=`, prose-faithful** (white_paper.qmd:284: "equal to (no larger than) or better (narrower than)") | FULL/MOST/ARREST-Unified exact; ARREST-Stratified + ties corrected (intended) |
| **Median % narrowed** | `100 * median((obs_w - fit_w) / obs_w)` | 30/30 exact (±0.1) |

Row counts reproduce exactly: full 106,703 / arrest 4,729 / most 784 / no-arrest 797.

**Table 6** ("100 largest no-arrest districts") is different — modeled-arrest totals,
NOT coverage. Pinned:
- **Modeled arrests** = `median` of the per-draw summed predicted arrests across the
  100 districts (NOT "sum of median fitted", which gives 0 for one-year models — the
  prose phrasing is inaccurate and is corrected in Task 4). Reproduces 26/41/1701/…
- **95% expected range** = 2.5% / 97.5% quantiles of the per-draw summed totals.
  Reproduces exactly; the static "Stratified 4" upper bound (832) is a typo that the
  rebuilt value corrects (~898).

**Decisions locked:** labels use **Unified/Stratified** (paper terminology); the
"equal or better" metric uses **`<=`** (prose-faithful). The equal-or-better cells
change modestly vs the old static table (FULL +0.1..1.2; ARREST-Stratified e.g.
65.0→69.8; MOST +0..1.2); all qualitative prose claims still hold. Coverage /
precision / % narrowed are unchanged.

---

## Conventions for every task

- Owner-side render/compute uses `CRDC_ARTIFACTS=export` (local clean parquet + `export/stages/`).
- `Rscript` only (allowlisted); retained-driver DuckDB (`open_draws_view()`/`close_draws_view()`).
- Full suite: `./scripts/run-tests.sh`. Read-contract: `Rscript -e 'source("R/check_read_contract.R"); check_read_contract(<doc>)'`.
- Commit after each task (`feat:`/`refactor:`/`docs:`). gpg signing on; on "signing failed: Timeout" STOP and ask the user to re-unlock.
- **Gates — STOP and ask before:** the Task 5 Quarto render (minutes); any `git push`.

---

## Task 1: Reconciliation — DONE (2026-06-08)

Completed during planning. `/tmp/reconcile_wp_tables.R` confirmed every definition in
the table above against the published values on the current clean artifacts. No code
was committed (investigation only). The pinned formulas above are the output. **No
action remains** — proceed to Task 2.

---

## Task 2: Inline per-observation comparison frame in `white_paper.qmd`

**Files:** Modify `white_paper.qmd` (remove the TODO at `:267-272`; add a chunk before "## Results" at `:274`)

- [ ] **Step 1: Create the branch**

```bash
git checkout -b feature/wp-coverage-tables
```

- [ ] **Step 2: Delete the TODO comment** (`white_paper.qmd:267-272`).

- [ ] **Step 3: Add the `cov_obs` data chunk** immediately before `## Results` (`:274`).
  The setup chunk (`:30`) already provides `con` (via `open_draws_view()`) and `rdata`.

````markdown
```{r}
#| label: wp-coverage-data
#| include: false

# Frequentist (Agresti-Coull) interval per district-student group, 2021-22.
obsv_data <- rdata |>
  dplyr::filter(YEAR == "21-22", stu_enroll > 0) |>
  dplyr::mutate(
    phat = (2 + ARRESTS) / (4 + stu_enroll),
    phat_se = sqrt(phat * (1 - phat) / (4 + stu_enroll)),
    obsv_sd = phat_se * (4 + stu_enroll),
    obs_upper = (phat + 1.96 * phat_se) * (4 + stu_enroll),
    obs_lower = (phat - 1.96 * phat_se) * (4 + stu_enroll),
    obs_upper = ifelse(ARRESTS == 0, 3, obs_upper),         # rule of three
    obs_lower = ifelse(ARRESTS == 0, 0, pmax(obs_lower, 0)))

# Modeled (Bayesian) median + 95% interval per group, all 10 models, 2021-22.
modeled <- get_prediction_summary(con, confidence_level = 0.95,
             central_tendency = "median", YEAR = "21-22") |>
  dplyr::select(model_id, LEAID, LEA_STATE, YEAR, RACE, SEX,
                fitted_value, sd, ci_lower, ci_upper)

# Join + per-1,000 rate scale + per-observation performance flags.
cov_obs <- dplyr::inner_join(modeled,
    obsv_data |> dplyr::select(LEAID, LEA_STATE, RACE, SEX, ARRESTS, stu_enroll,
                               obsv_sd, obs_lower, obs_upper),
    by = dplyr::join_by(LEAID, LEA_STATE, RACE, SEX)) |>
  dplyr::mutate(sd = ifelse(sd == 0, {                       # constant fit -> AC sd
      phat <- (fitted_value + 2) / (stu_enroll + 4)
      sqrt(phat * (1 - phat) / (4 + stu_enroll)) * (4 + stu_enroll)
    }, sd)) |>
  dplyr::mutate(
    per1k = stu_enroll / 1000,
    fit_w = (ci_upper - ci_lower) / per1k,
    obs_w = (obs_upper - obs_lower) / per1k,
    rate  = ARRESTS / per1k,
    lo = ci_lower / per1k, hi = ci_upper / per1k,
    fit_precision = 1 / (sd / per1k)^2,
    covered      = as.integer(lo <= rate & hi >= rate),
    equal_better = as.integer(fit_w <= obs_w),               # prose-faithful (<=)
    pct_narrowed = (obs_w - fit_w) / obs_w)

# Sample row-count (same per model) for the table footnotes.
n_full   <- sum(cov_obs$model_id == cov_obs$model_id[1])
bigarr_ids <- rdata |> dplyr::filter(YEAR == "21-22") |> dplyr::group_by(LEAID) |>
  dplyr::summarize(ta = sum(ARRESTS), .groups = "drop") |>
  dplyr::arrange(dplyr::desc(ta)) |> dplyr::slice_head(n = 100) |> dplyr::pull(LEAID)
```
````

- [ ] **Step 4: Smoke-test the chunk in isolation** (no full render):

```bash
CRDC_ARTIFACTS=export Rscript -e '
suppressMessages({library(dplyr); library(duckdb)
  source("R/funs.R"); source("R/crdc_path.R"); source("R/paper_figures.R")})
h <- open_draws_view(); con <- h$con
rdata <- read_stage_df("stages/inputs/recent_data.parquet")
# paste the obsv_data/modeled/cov_obs block here, then:
cat("cov_obs rows:", nrow(cov_obs), "| models:", dplyr::n_distinct(cov_obs$model_id), "\n")
close_draws_view(h)'
```
Expected: ~1,067,030 rows (≈106,703 × 10 models), 10 models.

- [ ] **Step 5: Commit**

```bash
git add white_paper.qmd
git commit -m "feat(white-paper): inline per-observation coverage frame (cov_obs)"
```

---

## Task 3: Wire Tables 3–5 (inline aggregation chunks)

**Files:** Modify `white_paper.qmd` (replace static blocks at `:290-314`, `:326-350`, `:362-386`)

Each table is its own self-contained chunk. Labels derived inline
(`startsWith(model_id, "nat")` → Unified) so no helper is needed.

- [ ] **Step 1: Replace the Table 3 static block** (`:290-314`) with:

````markdown
```{r}
#| label: tbl-coverage-full
#| tbl-cap: "Table 3: Model results for full sample"
cov_obs |>
  dplyr::group_by(model_id) |>
  dplyr::summarize(
    Coverage = 100 * mean(covered),
    precision = mean(fit_precision),
    equal_better = 100 * mean(equal_better),
    narrowed = 100 * median(pct_narrowed), .groups = "drop") |>
  dplyr::mutate(
    form = ifelse(startsWith(model_id, "nat"), "Unified", "Stratified"),
    num  = as.integer(sub("_mod$", "", sub("^(nat|sg)_m", "", model_id)))) |>
  dplyr::arrange(factor(form, levels = c("Unified", "Stratified")), num) |>
  dplyr::transmute(
    Models = paste(form, num),
    Coverage = sprintf("%.1f%%", Coverage),
    `Arrest rate precision (median)` = sprintf("%.2f", precision),
    `% equal or better intervals` = sprintf("%.1f%%", equal_better),
    `Median % narrowed` = sprintf("%.1f%%", narrowed)) |>
  knitr::kable()
```
````

- [ ] **Step 2: Update the Table 3 footnote** (`:316`) to use the computed count:
  `` Number of rows of data = `r format(n_full, big.mark=",")`. Observed precision = 0.384 … ``

- [ ] **Step 3: Replace the Table 4 static block** (`:326-350`) — same chunk as Step 1
  but pipe `cov_obs |> dplyr::filter(ARRESTS > 0)` into the `group_by`, label
  `tbl-coverage-arrest`, caption "Table 4: Model results for sample of
  district-student groups with an observed arrest".

- [ ] **Step 4: Update the Table 4 footnote** (`:352`):
  `` Number of rows of data = `r format(sum(cov_obs$ARRESTS[cov_obs$model_id==cov_obs$model_id[1]] > 0), big.mark=",")`. … `` (expected 4,729).

- [ ] **Step 5: Replace the Table 5 static block** (`:362-386`) — same chunk piping
  `cov_obs |> dplyr::filter(LEAID %in% bigarr_ids)`, label `tbl-coverage-most`,
  caption "Table 5: Model results for 100 districts with most total arrests".

- [ ] **Step 6: Update the Table 5 footnote** (`:388`):
  `` Number of rows of data = `r format(sum(cov_obs$LEAID[cov_obs$model_id==cov_obs$model_id[1]] %in% bigarr_ids), big.mark=",")`. … `` (expected 784).

- [ ] **Step 7: Verify chunks compute the expected values** (compare to the pinned
  reconciliation): re-run `/tmp/reconcile_wp_tables.R` and confirm the `<=` column
  (`p_orEq`) and coverage/precision/narrowed match what the chunks produce. (The
  reconciliation already proved these formulas; this confirms the chunk transcription.)

- [ ] **Step 8: Commit**

```bash
git add white_paper.qmd
git commit -m "feat(white-paper): wire Tables 3-5 inline (coverage/precision, <= metric)"
```

---

## Task 4: Wire Table 6 (inline modeled-arrests) + fix prose

**Files:** Modify `white_paper.qmd` (replace static block at `:396-420`; fix prose at `:394`)

- [ ] **Step 1: Replace the Table 6 static block** (`:396-420`) with:

````markdown
```{r}
#| label: tbl-missing-arrests
#| tbl-cap: "Table 6: Model results for 100 districts with largest student enrollments but no arrests"
noarr_ids <- rdata |> dplyr::filter(YEAR == "21-22") |> dplyr::group_by(LEAID) |>
  dplyr::summarize(ta = sum(ARRESTS), te = sum(stu_enroll), .groups = "drop") |>
  dplyr::filter(ta == 0) |> dplyr::arrange(dplyr::desc(te)) |>
  dplyr::slice_head(n = 100) |> dplyr::pull(LEAID)

get_prediction_draws(con, LEAID = noarr_ids, YEAR = "21-22") |>
  dplyr::group_by(model_id, draw_id) |>
  dplyr::summarize(tot = sum(pred), .groups = "drop") |>          # per-draw total arrests
  dplyr::group_by(model_id) |>
  dplyr::summarize(
    modeled = median(tot),
    lo = quantile(tot, 0.025), hi = quantile(tot, 0.975), .groups = "drop") |>
  dplyr::mutate(
    form = ifelse(startsWith(model_id, "nat"), "Unified", "Stratified"),
    num  = as.integer(sub("_mod$", "", sub("^(nat|sg)_m", "", model_id)))) |>
  dplyr::arrange(factor(form, levels = c("Unified", "Stratified")), num) |>
  dplyr::transmute(
    Models = paste(form, num),
    `Modeled arrests` = round(modeled),
    `95% expected range` = sprintf("%d – %d", round(lo), round(hi))) |>
  knitr::kable()
```
````

- [ ] **Step 2: Fix the inaccurate prose** at `:394`. Change "total arrests predicted
  are the sum of the median fitted value for each district-student group" to "total
  arrests predicted are the **median across posterior draws of the summed predicted
  arrests** across each district-student group" (matches the actual, reproducing
  computation).

- [ ] **Step 3: Update the Table 6 footnote** (`:422`):
  `` Number of rows of data = `r format(length(noarr_ids), big.mark=",")` districts. `` 
  (Note: the static "797" counted district-student-groups, not districts; state the
  unit explicitly — districts = 100, groups = 797. Confirm and word accordingly.)

- [ ] **Step 4: Confirm read-contract still clean**

```bash
Rscript -e 'source("R/check_read_contract.R"); print(check_read_contract("white_paper.qmd"))'
```
Expected: `character(0)`.

- [ ] **Step 5: Commit**

```bash
git add white_paper.qmd
git commit -m "feat(white-paper): wire Table 6 inline (median-of-summed-draws); fix prose"
```

---

## Task 5: Align `results.qmd` "equal or better" to `<=` (cross-doc consistency)

**Files:** Modify `results.qmd:632`

So the standalone results doc and the paper agree on the metric without sharing code.

- [ ] **Step 1: Change the strict `<` to `<=`** at `results.qmd:632`:

```r
    narrower_interval = ifelse((ci_upper - ci_lower) <= (obs_upper - obs_lower), 1, 0)
```

- [ ] **Step 2: Confirm results.qmd read-contract clean**

```bash
Rscript -e 'source("R/check_read_contract.R"); print(check_read_contract("results.qmd"))'
```
Expected: `character(0)`.

- [ ] **Step 3: Commit**

```bash
git add results.qmd
git commit -m "refactor(results): align equal-or-better metric to <= (matches white_paper)"
```

> If on inspection `results.qmd`'s `per_narrower` is only used in exploratory
> diagnostics (not a published figure), this task is cosmetic; keep it for definition
> consistency but it carries no reproduction risk.

---

## Task 6: Verify — render, prose reconciliation, finish (RENDER GATE)

**Files:** none (verification) + any prose-number edits surfaced

- [ ] **Step 1: Full test suite** — `./scripts/run-tests.sh` → all pass (unchanged;
  no functions added).

- [ ] **Step 2: GATE — confirm with the user before rendering** (minutes). Then:

```bash
CRDC_ARTIFACTS=export quarto render white_paper.qmd
```
Expected: `white_paper.html`; Tables 3–6 populated from the chunks; no errors.

- [ ] **Step 3: Reconcile every prose-cited number against the rebuilt tables.** Walk
  the Results narrative (`:280-360`, `:392-426`) and confirm each cited figure still
  matches: coverage (72.2% Unified-3-arrest, 59.2%→75.3% etc.), precision (2.44–8.32),
  the Table 6 ranges (1,629–1,794; 751). Coverage/precision/narrowed are unchanged by
  design; the **equal-or-better** cells changed (now `<=`), and the prose only
  discusses those qualitatively — confirm the qualitative claims (lines 284, 358) still
  read true. Edit any number that no longer matches; surface to the user if a
  qualitative claim breaks.

- [ ] **Step 4: Update memory** — mark deferred item (ii) Tables 3-6 resolved in
  `draws-api-project-roadmap`; note the `<=` decision and any prose edits.

- [ ] **Step 5: Finish the branch** — REQUIRED SUB-SKILL:
  superpowers:finishing-a-development-branch (verify tests, present merge/PR options).

---

## Self-Review

**Spec coverage:** TODO `white_paper.qmd:267` → Tasks 2–4. Inline-not-builder
architecture (user feedback + `prefer-inline-repro-docs` memory + spec decision #3) →
Tasks 2–4 all chunk-based. Unified/Stratified labels (user) → inline `startsWith`.
Prose-faithful `<=` (user) → pinned definition + Task 5 alignment. Render-verify +
prose reconciliation (spec §H) → Task 6.

**Placeholder scan:** Task 3 Steps 3/5 say "same chunk as Step 1 but pipe X" — this is
a deliberate filter swap on an otherwise-identical, fully-shown chunk; the only change
is the `cov_obs |> dplyr::filter(...)` head and the label/caption. Acceptable (the full
chunk body is in Step 1). All other steps show complete code.

**Type consistency:** `cov_obs` columns (`covered`, `fit_precision`, `equal_better`,
`pct_narrowed`, `fit_w`, `obs_w`, `rate`, `lo`, `hi`) defined in Task 2 and consumed by
Tasks 3. Label derivation (`startsWith(model_id,"nat")` → Unified; `num` via `sub`)
identical across Tasks 3 and 4. `get_prediction_draws` returns `pred`/`draw_id`/
`model_id` (used in Task 4). No new functions introduced (the architecture goal).

**Risk register:** (1) equal-or-better numbers change vs published — accepted (user
decision, prose-faithful); Task 6 confirms qualitative claims hold. (2) Table 6 "797"
unit ambiguity (districts vs district-student-groups) → Task 4 Step 3 states the unit.
(3) inline duplication across Tables 3–5 → intentional per user (legibility > DRY).
(4) `feature/pooled-rename` later flips Unified/Stratified globally — these chunks
derive labels inline, a trivial future edit.
