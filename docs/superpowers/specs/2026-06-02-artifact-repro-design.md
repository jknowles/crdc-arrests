# Subsystem 3 — Artifact Reproduction (Design Spec)

**Date:** 2026-06-02
**Branch:** `feature/artifact-repro`
**Status:** draft — awaiting user review before writing-plans
**Roadmap:** [`ROADMAP.md`](./ROADMAP.md) §"Subsystem 3"
**Builds on:** [`2026-05-30-draws-api-design.md`](./2026-05-30-draws-api-design.md) (data product),
[`2026-06-01-pipeline-repro-design.md`](./2026-06-01-pipeline-repro-design.md) (env capture + hardened targets)

## Goal

Anyone — not just the build owner — can **deterministically rebuild the published
artifacts** (the white paper, results, applied examples, social posts, EDA, and
descriptive reports) **without** the ~7-day model run, the 18 GB `_targets/`
store, or the 69 GB draws DB. We achieve this by publishing the docs' inputs as a
small set of **staged intermediate artifacts** and re-pointing every `.qmd` to
read those artifacts with **native tooling**. Core reproduction then needs only a
**~1.7 GB** public download (staged data + the 1.4 GB draws parquet) and a Quarto
render; an **optional** ~2.9 GB of pooled-model fits adds `results.qmd`'s *live*
diagnostics (otherwise served from a published diagnostics table).

This subsystem touches **only** rendering and the new staged-intermediate
publishing. It does **not** change Subsystem 1 (API / HF data product / Pages
docs) or Subsystem 2 (pipeline) behavior, and it never refits a model.

## Locked decisions (from brainstorming — not relitigated)

1. **White paper = imported narrative.** The published civilytics.com report is
   brought into the repo as a new authored **`white_paper.qmd`** (narrative +
   embedded results). **The user supplies the report source**; we port it
   faithfully. (`results.qmd` remains the exhaustive results engine.)
2. **Push everything public via staged intermediates.** Rather than cut the
   content the public product can't back, we *expand* the published surface: new
   pipeline targets materialize each doc input as portable parquet, published so a
   stranger reproduces any doc/stage without the compute. The expanded external
   surface is an accepted, intended cost.
3. **Native readers, no resolver-function layer.** Docs read with native
   DuckDB/SQL over a single visible base URI; we re-point *connections* and swap
   `tar_read()` for inline `read_parquet()` queries. No `read_stage()`-style
   wrappers (they would obfuscate the reads and add maintenance).
4. **Artifact home = same HF dataset, new path.** Staged intermediates publish to
   `civilytics/crdc-school-arrest-rates` under `stages/`, pinned to
   `data_release = civilytics-crdc-arrests-2025.1`.
5. **Scope = all six docs + the new paper** become reproducible render targets.
6. **Branding via the `civilytics` package.** Docs (especially `white_paper.qmd`
   and the social posts) use `civilytics::use_civilytics_theme()` /
   `use_civilytics_brand()` (`_brand.yml` + `theme/` + LaTeX/Typst + the package's
   `examples/report.qmd`) and `civilytics_load_fonts()`.
7. **Brms fits — hybrid.** Publish the **5 pooled fits** (`nat_m*`, ~2.9 GB) as
   `stages/models/pooled_m*.qs2` so `results.qmd` runs the *real*
   `calculate_model_stats()` / `rstan::check_hmc_diagnostics()` live; the 45
   **subgroup fits** (`sg_m*`, ~31 GB) are **not** shipped — their
   `calculate_model_stats()` output is precomputed into a derived parquet table.
8. **Rendered HTML = repo/release artifacts only.** No Gitea Pages deploy of the
   rendered docs in this subsystem.
9. **CI = parse/validate only.** No render, no fitting.
10. **"Pooled" rename = presentation-only now.** Use "Pooled" consistently in all
    Subsystem-3 artifacts (paper, results, figures, labels, the diagnostics
    table's `model_label`, and the `stages/models/pooled_m*.qs2` filenames) via a
    documented label map. The underlying `model_id` / target names stay `nat_*`
    so the launched API, HF dataset, and release keep working with no refit. A
    **deep rename + re-run** (rename target names + published `model_id` to
    `pooled_*`) is a **future, separately-specced breaking change** (see Future
    work).

## Why this is feasible (the hard cases, resolved)

- **The brms-object dependency is isolated to `results.qmd`**, and only for
  `calculate_model_stats()` (10 models) and `rstan::check_hmc_diagnostics()` (5
  pooled models). `applied_examples.qmd` loads `marginaleffects` but pulls
  everything from the draws via `get_prediction_summary(con, …)` — no fit object
  needed. The other docs need raw/intermediate CRDC data but no models.
- **Sizes** (`tar_meta`): pooled fits ~2.9 GB total; subgroup fits ~31 GB (too
  big → derived table); all model-input targets ~65 MB; all raw/intermediate CRDC
  targets ~202 MB. New mandatory download **< 300 MB**; core set with the 1.4 GB
  draws parquet ≈ **~1.7 GB**; with the optional pooled fits for live diagnostics
  ≈ **~4.6 GB** (still vs. 18 GB store + 69 GB DB + 7-day run).
- **Native readers verified in the pinned env:** DuckDB 1.5.2 + `httpfs` loads
  (native `read_parquet('hf://datasets/…')`, the project's existing draws idiom);
  `qs2` present (serialized fits readable); Quarto CLI 1.9.37 (`_brand.yml`
  support). `arrow`/`hfhub` are **not** required — DuckDB reads the parquet and
  base-R `download.file()` over HF `…/resolve/<rev>/…` URLs fetches whole files
  (API DuckDB, qs2 fits) with zero new deps.

---

## A. Render-input contract — native readers, one base URI

Each in-scope `.qmd` declares one visible base near the top:

```r
CRDC_BASE <- Sys.getenv(
  "CRDC_ARTIFACTS",
  "hf://datasets/civilytics/crdc-school-arrest-rates"  # stranger default (range-read)
)
# Owner / fast full render:  export CRDC_ARTIFACTS=export   (reads local export/)
```

All data access is then native and visible in the chunk. Two patterns only:

1. **Draws (re-point the connection, not the queries).** Replace the old
   `con <- dbConnect(duckdb::duckdb(), "export/db/crdc_arrests.duckdb", read_only=TRUE)`
   with a connection that exposes a `predicted_draws` **view over the published
   parquet**, so every existing `get_prediction_summary(con, …)` /
   `get_state_prediction_summary(con)` call works unchanged:

   ```r
   drv <- duckdb::duckdb(); con <- DBI::dbConnect(drv)             # retain driver
   DBI::dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
   DBI::dbExecute(con, sprintf(
     "CREATE VIEW predicted_draws AS
        SELECT * FROM read_parquet('%s/parquet/**/*.parquet', hive_partitioning=true)",
     CRDC_BASE))
   # ... existing queries ...
   DBI::dbDisconnect(con, shutdown=TRUE); duckdb::duckdb_shutdown(drv)
   ```

2. **Tabular stage targets.** Replace `tar_read("three_year_data")$data` etc. with
   an inline native read:

   ```r
   tydata <- DBI::dbGetQuery(con, sprintf(
     "SELECT * FROM read_parquet('%s/stages/inputs/three_year_data.parquet')", CRDC_BASE))
   ```

**Driver-retention rule** applies to every DuckDB connection (anonymous driver GC
→ "Invalid connection"). No new data-access helper functions are introduced;
the only shared item is the `CRDC_BASE` string (and, optionally, a 1–2 line
inline connection-setup snippet copied per doc, kept visible).

## B. Staged-intermediate targets (the new public surface)

New `format = "file"` targets materialize each input the in-scope docs read,
writing portable parquet under `export/stages/`. A publish step uploads
`export/stages/` to HF under `stages/`, pinned to the `data_release`.

**Layout (HF dataset `civilytics/crdc-school-arrest-rates`):**

```
stages/
  inputs/      three_year_data.parquet, recent_data.parquet,
               combined_model_data.parquet, combined_sch_data.parquet      (~65 MB)
  crdc/        full_crdc_data_{y2122,y1718,y1516}.parquet,
               model_data_{…}.parquet, popcounts_{…}.parquet,
               schenrollraw_{…}.parquet, lerefs_{…}.parquet,
               ccd_sch_geo_{…}.parquet, ccd_dist_geo_{…}.parquet           (~202 MB)
  diagnostics/ model_stats.parquet        (calculate_model_stats() for ALL 10,
                                            with a `model_label` "Pooled (m#)" /
                                            "Student-group (m#)" column)
               hmc_diagnostics.parquet    (pooled divergence / max-treedepth /
                                            E-BFMI per chain)
  models/      pooled_m1.qs2 … pooled_m5.qs2   (the 5 nat_* brms fits, ~2.9 GB)
parquet/       (unchanged — Subsystem 1 draws shards)
summary.duckdb (unchanged — Subsystem 1 API summary tables)
```

**Materializer contract.** Each staging target's output **must contain exactly
what the in-scope docs read** from the corresponding store target. Notably
`three_year_data` / `recent_data` are *lists*; docs use `$data`, but the
implementation audits each doc and, if any non-`$data` element is consumed (e.g.
restriction metadata for sample-restriction tables), publishes it as a small
companion file (json/parquet) under `stages/inputs/`.

**Diagnostics targets:**
- `model_stats` target reads the 10 model targets from the store (owner-side
  only) and writes `calculate_model_stats()` output for each, with a human
  `model_label` using the **Pooled** terminology.
- `hmc_diagnostics` target extracts structured pooled-model sampler diagnostics
  (`rstan::get_num_divergent`, `get_num_max_treedepth`, `get_bfmi`, …) into a
  small table. `results.qmd` shows these live from the shipped `pooled_m*.qs2`
  when present, and falls back to this table otherwise.

**Publishing.** Reuse the Subsystem-1 HF publish mechanism (the path already used
for `parquet/` + `summary.duckdb`), pinned to `civilytics-crdc-arrests-2025.1`.
Implementation confirms the exact tool (huggingface CLI / existing script).

## C. Re-point each doc + new `white_paper.qmd`

| Doc | Change |
|-----|--------|
| `results.qmd` | Connection→view re-point; `tar_read()`→`read_parquet`; pooled diagnostics live from `pooled_m*.qs2`; subgroup stats from `model_stats.parquet`; apply Pooled labels. |
| `applied_examples.qmd` | Connection→view re-point; `tar_read(three_year_data/recent_data)`→`read_parquet`; Pooled labels in model-name maps. |
| `social_media_posts.qmd` | Connection→view re-point; `tar_read()`→`read_parquet`; keep `civilytics` theme/logo + `magick`/`ragg` table images; Pooled labels. |
| `combined_eda.qmd` | `tar_read()`→`read_parquet`; keep `tigris` maps + `civilytics` theme. |
| `annual_descriptives_template.qmd` | `tar_read_raw(paste0("model_data_", suffix))` etc. → parameterized `read_parquet('%s/stages/crdc/model_data_<suffix>.parquet')`. |
| `model_descriptives_template.qmd` | Same parameterized re-point; give it a **distinct** `fig.path` (currently collides with `appliedexample-`). |
| **`white_paper.qmd`** (new) | Authored from the user-supplied report source; themed via `use_civilytics_theme()`; figures/tables wired to the artifacts (same patterns above). |

No analytical/plotting logic changes — figures stay visually identical; only the
data source and model labels change.

**Sequencing note.** `white_paper.qmd` *authoring* is gated on the user-supplied
report source. The themed scaffold (brand files, format YAML, artifact-wired
result/figure chunks) can be built first; the narrative prose is ported in once
the source is provided.

## D. Render targets in `_targets.R`

Reinstate the commented targets and add the rest, all with
`cue = tar_cue(mode = "never")` so a normal `tar_make()` never triggers a
multi-hour render (renders are explicit):

- `combined_eda` — `tarchetypes::tar_render` (reinstated).
- `annual_report` — `tarchetypes::tar_render_rep` over the 3 years (reinstated).
- `model_descriptives` — `tar_render_rep` over the 3 years (new).
- `white_paper`, `results`, `applied_examples`, `social_media_posts` —
  `tar_render` (new).
- The staging targets from §B (`stage_inputs_*`, `stage_crdc_*`, `model_stats`,
  `hmc_diagnostics`, `pooled_fits`, and a `publish_stages` file target).

Render targets depend on the staging targets so the graph is correct, but
`cue = never` keeps them out of routine builds.

## E. Determinism + one-command render + stranger path

- **`scripts/render-artifacts.sh`** — one command: ensure `export/stages/` exists
  (build the staging targets locally, or `download.file` the bundle from HF if
  absent), then `quarto render` (or `tar_make(names = …)`) the in-scope docs.
- **Stranger flow (documented):** either set `CRDC_ARTIFACTS=hf://datasets/…`
  (zero-setup; DuckDB range-reads only the needed row groups) or `download.file`
  the `stages/` + `parquet/` bundle once and point `CRDC_ARTIFACTS` at the local
  copy (fast full render). Fonts: `civilytics_load_fonts()` downloads Google
  fonts on first use — document the network need / caching.
- **Determinism statement** (REPRODUCIBILITY.md addition): global seed `11213`;
  figures are **statistically reproducible, not bit-for-bit** (threaded Stan),
  inheriting Subsystem 2's stance; figure dims/dpi pinned per the docs' YAML.

## F. renv render-deps

The render-only deps were deliberately excluded in Subsystem 2 (via `.renvignore`
`*.qmd` + scratch dirs). This subsystem installs only the genuinely-needed ones,
**narrows the relevant `.renvignore` exclusions**, and **re-snapshots** `renv.lock`:

- Required: `quarto`, `ggdist`, `tidybayes`, `ggridges`, `marginaleffects`,
  `patchwork`, `flextable`, `gdtools`, `systemfonts`, `DT`, `tigris`, `sf`,
  `magick`, `ragg`, `sysfonts`, `showtext`, and `civilytics` (already in lib at
  v0.2.0; pin from its Gitea source).
- **System libs** (confirm with the user before any `apt`):
  `libmagick++-dev` (magick), and the GDAL/GEOS/PROJ stack for `sf`/`tigris` if
  not already present.
- Validate the final list by rendering each in-scope doc and resolving missing
  symbols; drop anything not actually used.

## G. CI — parse/validate only

Extend the existing parse-only job in `.gitea/workflows/test.yml`:

- `tar_validate()` must still load with the new render + staging targets (install
  only the packages required to *source* `_targets.R`, incl. `tarchetypes`).
- **Static read-contract check** (`Rscript`, no render): for each in-scope `.qmd`,
  parse out every `read_parquet('…/stages/…')` / `predicted_draws` view reference
  and assert each resolves to a path a staging target writes. Guards drift between
  what docs read and what the pipeline publishes.
- **No `quarto render`, no model fitting**, consistent with the no-node
  `ubuntu-latest` runner and Subsystem 2's stance.

## H. Tests / verification

- **Unit tests** (synthetic fixtures): the staging materializers produce the
  expected parquet shape/columns; `three_year_data`/`recent_data` list handling
  captures all consumed components; the `predicted_draws`-view-over-parquet round
  trips `get_prediction_summary()` against a tiny synthetic parquet set; the
  diagnostics target emits the expected `model_label` values.
- **Read-contract test** (the §G check, runnable locally + in CI).
- **Local render smoke** (owner, gated): render `white_paper.qmd` + `results.qmd`
  against local `export/stages/` to confirm the end-to-end path before merge.
  Confirm with the user before any long render.
- Run the suite with `./scripts/run-tests.sh`.

---

## Out of scope

- Refitting any model (renders never fit).
- Changing Subsystem 1 (API / HF data product / Pages-for-docs) or Subsystem 2
  (pipeline) behavior.
- Gitea Pages deploy of the rendered HTML (committed/release artifacts only).
- FIPS→state cosmetic (geo-match is already 1.0).
- **Deep `pooled_*` rename** of target names + published `model_id` (see below).

## Future work (separately specced)

- **Deep rename + re-run.** Rename pipeline target names and the published
  `model_id` from `nat_*` to `pooled_*` everywhere, re-run the ~7-day pipeline,
  and republish the API / HF dataset / release under the new identifiers. This is
  a breaking change to launched Subsystem 1 and gets its own spec; it may run
  later or concurrently with this subsystem's work.
- Optional `pooled_*` **non-breaking aliases** in the Subsystem-1 API /
  data dictionary (keeping `nat_*` stored) as an interim step.

## Files touched (summary)

| File | Change |
|------|--------|
| `white_paper.qmd` | new (imported narrative; civilytics theme; artifact-wired) |
| `results.qmd`, `applied_examples.qmd`, `social_media_posts.qmd`, `combined_eda.qmd` | re-point reads to `CRDC_BASE` artifacts; Pooled labels |
| `annual_descriptives_template.qmd`, `model_descriptives_template.qmd` | parameterized re-point; fix `model_descriptives` `fig.path` collision |
| `_targets.R` | reinstate `combined_eda` + `annual_report`; add render targets (`cue=never`) + staging/diagnostics/pooled-fits/publish targets |
| `R/stage_artifacts.R` | new — staging materializers (inputs, crdc, diagnostics, pooled fits) |
| `R/publish_stages.R` | new — HF upload of `export/stages/` (reuses S1 publish path) |
| `_brand.yml`, `theme/`, `latex/`, `typst/`, logos | new — via `civilytics::use_civilytics_theme()` |
| `scripts/render-artifacts.sh` | new — one-command render + stranger download path |
| `REPRODUCIBILITY.md`, `README.md` | add artifact-reproduction section + determinism + render deps |
| `.renvignore` | narrow `*.qmd` exclusions for in-scope docs |
| `renv.lock` | re-snapshot with render deps |
| `.gitea/workflows/test.yml` | extend parse-only job with the read-contract check |
| `tests/testthat/test-stage_artifacts.R`, `test-read-contract.R` | new |

## Conventions / gotchas honored

- R/Rscript for ad-hoc work (allowlisted); tests via `./scripts/run-tests.sh`;
  active renv project (render deps installed + snapshotted, not just present).
- Always retain DuckDB drivers (anonymous driver GC → "Invalid connection").
- `origin` dual-pushes GitHub `jknowles/crdc-arrests` (canonical, public) + Gitea
  `jared/crdc-arrests`; a stale `GITHUB_TOKEN` may need `GITHUB_TOKEN= GH_TOKEN=`
  prefix; use `gh` for PRs.
- Gitea runner has no node, advertises `ubuntu-latest` → shell `git clone`
  checkout in any CI step.
- gpg commit signing is on; the passphrase cache can expire during long renders —
  ask the user to re-unlock if a commit fails with "signing failed: Timeout".
- Confirm with the user before heavy compute (long renders), any push, or
  installing system libs (e.g. `libmagick++-dev`).
