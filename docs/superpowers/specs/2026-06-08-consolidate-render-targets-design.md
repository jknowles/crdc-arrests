# Design: Consolidate Subsystem-3 Render Targets (5 → 3)

**Date:** 2026-06-08
**Status:** Approved design — pending implementation plan
**Branch:** `feature/render-finetune`
**Predecessor:** Render-target deduplication (commit `07a21d9`), which made
`white_paper.qmd` the canonical home for all shared content and removed
duplicates from the other targets.

## Background

Subsystem 3 (Artifact reproduction) currently has five standalone `.qmd` render
targets plus two per-wave templates. Each reads published artifacts via
`crdc_path()`, renders standalone (`quarto render`), and is also a
`cue = "never"` `tar_render` target in `_targets.R`. There is no
`_quarto.yml`/website; each emits its own HTML, deployed via the Gitea `pages`
branch.

After the dedup, the five targets are:

| Target | Role |
|---|---|
| `white_paper.qmd` | The paper (canonical, standalone deliverable) |
| `results.qmd` | Technical/diagnostic supplement |
| `applied_examples.qmd` | Extra worked prediction-interval examples |
| `combined_eda.qmd` | Three-year exploratory analysis |
| `social_media_posts.qmd` | Branded social-media figures/tables |

The goal is to give users **fewer render targets to navigate**, each with a
clear purpose.

## Goal

Merge the three researcher-facing supplements (`results.qmd`,
`applied_examples.qmd`, `combined_eda.qmd`) into a single
**`supplement.qmd`** ("Supplementary Materials"), leaving three targets:

1. `white_paper.qmd` — the paper (**unchanged**)
2. `supplement.qmd` — Supplementary Materials (**new, merged**)
3. `social_media_posts.qmd` — branded social graphics (**unchanged**)

`social_media_posts.qmd` stays separate: it is a different output format
(300-DPI branded PNGs, logo compositing) and audience (comms/public).

## Decisions (from brainstorming)

- **Grouping:** 3 docs — paper / supplement / social. (Not 2: social stays
  separate. Not 4: EDA folds into the supplement.)
- **Internal structure:** narrative companion ordering — data → method → use.
- **Naming:** `supplement.qmd`, title "Supplementary Materials".
- **Transparency constraint:** keep pipeline code transparent — no new
  helper/wrapper functions, and inline the analytical/labeling code so a reader
  sees every transformation in the document. **Boundary:** inline the model
  analysis (labeling helpers, palettes, all dplyr/ggplot); keep the *documented*
  artifact-access layer sourced from `R/`.

## Target structure: `supplement.qmd`

YAML: `format: html` with `embed-resources: true`, `toc: true`, the Civilytics
theme (mirroring the other docs), `execute: echo:false/warning:false/
message:false`, and `knitr.opts_chunk.fig.path: export/figures/supplement-`.

Four top-level parts (narrative: data → sample → models → use):

### Part 1 — Exploratory Data Analysis *(from `combined_eda.qmd`)*
Data structure/dimensions, by-year summary + trend plots, state choropleths
(arrest rate; NNH), race×sex distribution (**kept labeled "3-year pooled"** so it
is not confused with the paper's 2021-22 totals), group trends over waves, KS/CA
state trends, two LEA leaderboards (count and rate).

### Part 2 — Data Construction & Sample Restrictions *(from `results.qmd`)*
Sample continuity across waves (`match_test`), district concentration (size
categories, expected-vs-observed binomial, Lorenz figure, enrollment by arrest
status), and sample-restriction impacts (Section 504 data/enrollment,
missing-data/reserve-code patterns, grade-level, CCD matching, enrollment
thresholds, censored enrollment).

### Part 3 — Model Performance & Diagnostics *(from `results.qmd`)*
Observed-vs-modeled `plotdf` substrate, diagnostic cross-tabs, constant/
non-constant model summaries, large-district (`big100`) subgroup performance,
model computation + HMC diagnostics, and state-level performance. **Retains the
existing pointer notes** ("the full-sample / non-zero / high-arrest / zero-arrest
model summaries are Tables 3–6 in `white_paper.qmd`").

### Part 4 — Applied Examples *(from `applied_examples.qmd`)*
Baltimore City vs County cross-district comparison, Baltimore County temporal
trend, Broward female small-groups disparity, all-states arrest-rate overview.

## Merge mechanics

### Single setup chunk (`label: setup`, `include: false`)
- Libraries: union of all three docs (targets, brms, dplyr, tidyr, stringr,
  ggplot2, ggdist, marginaleffects, tidybayes, ggridges, patchwork, duckdb,
  knitr) plus the EDA map deps (tigris, sf).
- `source("R/funs.R"); source("R/crdc_path.R"); source("R/model_registry.R");
  source("R/paper_figures.R")` — required for the data-access layer.
- `cv_apply_branding()` once.
- `open_draws_view()` once → `h`/`con`.
- Load inputs once: `tydata`, `rdata`, `y2122` (+ `nat_totals`/`nat_arrest_rate`),
  the EDA `combined_data` frame, `tigris` state shapes, colour palettes.
- **Inline (transparency boundary):** define `add_model_time`, `add_model_form`,
  `add_model_cov`, `print_model_name`, and the `model_palette` / `group_palette`
  vectors *in this chunk* (copied from their current `R/paper_figures.R`
  definitions). These shadow the sourced versions so all labeling logic is
  visible in the document. (They remain in `R/paper_figures.R` for
  `white_paper.qmd`'s `wp_fig_*` builders — that file is out of scope here.)

### Kept sourced (documented artifact-access + atomic utilities)
`read_stage_df`, `open_draws_view`/`close_draws_view`, `crdc_path`,
`get_prediction_summary`, `get_prediction_draws`,
`get_state_prediction_summary`, `with_model_labels`, `crdc_pooled_ids`,
`crdc_model_registry`, `crdc_cached_path`, `match_test`, `crdc_lea_collapse`,
`incomplete_enrollments`, `crdc_sub`, `pretty_per`, `pretty_count`,
`crdc_race_recode`. Inlining their internals (e.g., raw DuckDB SQL behind
`get_prediction_summary`) would reduce readability, not improve it.

### Chunk-label namespacing
All chunk labels must be globally unique in one Quarto doc. Namespace by part:
`eda-*` (Part 1), `data-*` (Part 2), `perf-*` (Part 3), `ex-*` (Part 4). This
resolves the current `setup`/`cleanup` duplicate labels and the dozens of
others; one `setup` and one `cleanup` survive.

### Object-collision renames
- `combined_data`: Part 1 (EDA) keeps the name (core EDA frame). The transient
  `combined_data`/`combined_data2` in Part 2's grade-level and
  enrollment-threshold sections → local names (`gr_data` / `thr_data`).
- `dist_test`: appears in both Part 3 (observed-prep) and Part 4 (Baltimore
  prep). Scope/rename so a later section cannot clobber an earlier one.
- `h`/`rdata`/`tydata`: defined once in setup (no longer per-doc).

### Memory ordering
Parts 1–2 load large frames (combined model data, CRDC stage files, state
shapes); Parts 3–4 run the heavy draws queries. Keep/adapt the existing
`rm()`/`gc()` calls so big frames are freed before the draws queries, and so
nothing freed early is needed later. One final `cleanup` chunk:
`close_draws_view(h)`.

### Figures
Single `fig.path = export/figures/supplement-`.

## Repo wiring

- **`_targets.R`:**
  - Remove the `combined_eda` `tar_render` (~L221–228, output
    `crdc_combined_three_year_eda_report.html`).
  - Remove `results_report` (L713–714) and `applied_examples` (L715–716)
    `tar_render`s.
  - Add `tarchetypes::tar_render(supplement, "supplement.qmd",
    output_file = "supplement.html", cue = tar_cue(mode = "never"))` in the
    Subsystem-3 group.
  - Keep `white_paper`, `social_media_posts`, and both `*_template` targets.
- **`scripts/render-artifacts.sh`:** update `DOCS=(...)` to
  `white_paper.qmd supplement.qmd social_media_posts.qmd`; update the header
  comment.
- **`README.md`:** update the Subsystem-3 file list (5 → 3 + templates) and any
  prose referencing the removed docs.
- **Source deletions:** delete `results.qmd`, `applied_examples.qmd`,
  `combined_eda.qmd` once content is moved (git history preserves them).
- **Gitea `pages` deploy:** check for hard-coded links to the removed HTML
  filenames (`results.html`, `applied_examples.html`,
  `crdc_combined_three_year_eda_report.html`); update if present.

## Verification

1. `CRDC_ARTIFACTS=export quarto render supplement.qmd` → exit 0.
2. Confirm all four parts render, figures land under `export/figures/supplement-`,
   no duplicate-label errors, no missing-object errors, and the Table 3–6
   pointer notes are present.
3. Sanity-render `white_paper.qmd` and `social_media_posts.qmd` (unchanged) to
   confirm nothing regressed.
4. `git status` clean except intended source changes (HTML/figures gitignored).

## Risks

- **Object-collision/ordering** during the merge is the main risk; mitigated by
  the explicit renames above and namespaced labels.
- **Longest single render** (combines all three docs' queries); acceptable.
- **Helper duplication:** the inlined labeling helpers/palettes now exist both
  in `supplement.qmd` (inline, by design) and `R/paper_figures.R` (for the
  paper). This is the deliberate transparency-over-DRY tradeoff.

## Out of scope

- `white_paper.qmd` content (canonical; unchanged).
- `social_media_posts.qmd` content (unchanged).
- The two `*_template.qmd` per-wave report templates.
- Refactoring `R/paper_figures.R` or the `wp_fig_*` builders the paper uses.
- Any `_quarto.yml`/website/index (rejected in favor of file-merging).
