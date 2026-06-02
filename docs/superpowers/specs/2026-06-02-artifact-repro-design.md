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
read those artifacts with **native tooling**. Core reproduction needs only a
**~1.7 GB** download (staged data + the 1.4 GB draws parquet) cached on first use;
an **optional** ~2.9 GB of pooled-model fits adds `results.qmd`'s *live*
diagnostics (otherwise served from a published diagnostics table).

Three properties make this usable in practice:
- **Cached, not re-downloaded.** Big objects are cached locally on first access so
  repeated work avoids multi-gigabyte re-downloads; small objects are read
  directly with negligible lag.
- **Standalone-renderable.** Each `.qmd` renders with a plain `quarto render`,
  with **no** `_targets/` store and **no** `tar_make()` — and is *also* wired as a
  pipeline render target for integrated runs.
- **Stage-legible.** A provenance map documents exactly where each staged artifact
  sits in the pipeline, so users understand the difference between the data at
  each stage.

This subsystem touches **only** rendering and the new staged-intermediate
publishing. It does **not** change Subsystem 1 (API / HF data product / Pages
docs) or Subsystem 2 (pipeline) behavior, and it never refits a model.

## Locked decisions (from brainstorming — not relitigated)

1. **White paper = imported narrative.** The published civilytics.com report is
   brought into the repo as a new authored **`white_paper.qmd`** (narrative +
   embedded results). **The user supplies the report source**; we port it
   faithfully. (`results.qmd` remains the exhaustive results engine.)
2. **Push everything public via staged intermediates.** Rather than cut content
   the public product can't back, we *expand* the published surface: new pipeline
   targets materialize each doc input as portable parquet, published so a stranger
   reproduces any doc/stage without the compute. The expanded external surface is
   an accepted, intended cost.
3. **Native readers + one thin path-resolver.** Docs read with native DuckDB/SQL.
   The *only* shared helper is **`crdc_path()`**, a pure function that returns a
   **URI string** (and lazily caches big objects) — it resolves a path, it does
   **not** wrap the read. No `read_stage()`-style data-access wrappers.
4. **Caching = `crdc_path()` (thin resolver).** Big objects (draws parquet, pooled
   fits) cache to a local cache dir on first use; small objects resolve to their
   `hf://` URI for direct reads. (§A.2)
5. **Artifact home = same HF dataset, new path.** Staged intermediates publish to
   `civilytics/crdc-school-arrest-rates` under `stages/`, pinned to
   `data_release = civilytics-crdc-arrests-2025.1`.
6. **Scope = all six docs + the new paper** become reproducible render targets.
7. **Standalone + pipeline.** Docs render standalone (`quarto render`, no store) and
   are *also* `tar_render`/`tar_render_rep` targets (`cue = never`). No
   `tar_read()`/`tar_load()` of the store at render time. (§A.3, §D)
8. **Branding via the `civilytics` package.** Docs (especially `white_paper.qmd`
   and the social posts) use `civilytics::use_civilytics_theme()` /
   `use_civilytics_brand()` and `civilytics_load_fonts()`.
9. **Brms fits — hybrid.** Publish the **5 pooled fits** (`nat_m*`, ~2.9 GB) as
   `stages/models/pooled_m*.qs2` so `results.qmd` runs the *real*
   `calculate_model_stats()` / `rstan::check_hmc_diagnostics()` live; the 45
   **subgroup fits** (`sg_m*`, ~31 GB) are **not** shipped — their
   `calculate_model_stats()` output is precomputed into a derived parquet table.
10. **Rendered HTML = repo/release artifacts only.** No Gitea Pages deploy of the
    rendered docs in this subsystem.
11. **CI = parse/validate only.** No render, no fitting.
12. **Model registry = single source of truth.** Model ids + display labels +
    grouping (pooled vs student-group) live in one config (`R/model_registry.R` /
    `inst/models.yml`), referenced by both staging targets and docs. This isolates
    the one thing the future deep rename changes. (§I)
13. **"Pooled" rename = presentation-only now.** Use "Pooled" consistently in all
    Subsystem-3 artifacts (paper, results, figures, labels, the diagnostics
    table's `model_label`, and the `stages/models/pooled_m*.qs2` filenames) via the
    registry. Underlying `model_id` / target names stay `nat_*` so the launched
    API, HF dataset, and release keep working with no refit. A **deep rename +
    re-run** is a separate, **concurrent** effort on another machine (§I, Future
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
  draws parquet ≈ **~1.7 GB**; with the optional pooled fits ≈ **~4.6 GB** (vs.
  18 GB store + 69 GB DB + 7-day run).
- **Native readers verified in the pinned env:** DuckDB 1.5.2 + `httpfs` loads
  (native `read_parquet('hf://datasets/…')`); `qs2` present (serialized fits
  readable); Quarto CLI 1.9.37 (`_brand.yml` support). `arrow`/`hfhub` are **not**
  required — DuckDB reads the parquet and base-R `download.file()` over HF
  `…/resolve/<rev>/…` URLs fetches whole files with zero new deps.

---

## A. Render-input contract

### A.1 Native reads via `crdc_path()`

All data access is native DuckDB/SQL; the only shared helper is **`crdc_path(rel)`**,
which returns a **URI string** for a logical artifact path (and caches big objects —
§A.2). Two read patterns only:

1. **Draws (re-point the connection, not the queries).** Replace the old
   `dbConnect(duckdb(), "export/db/crdc_arrests.duckdb", read_only=TRUE)` with a
   connection exposing a `predicted_draws` **view over the published parquet**, so
   every existing `get_prediction_summary(con, …)` / `get_state_prediction_summary(con)`
   call works unchanged:

   ```r
   drv <- duckdb::duckdb(); con <- DBI::dbConnect(drv)            # retain driver
   DBI::dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
   DBI::dbExecute(con, sprintf(
     "CREATE VIEW predicted_draws AS
        SELECT * FROM read_parquet('%s/**/*.parquet', hive_partitioning=true)",
     crdc_path("parquet")))                                       # local mirror if cached, else hf://
   # ... existing queries unchanged ...
   DBI::dbDisconnect(con, shutdown=TRUE); duckdb::duckdb_shutdown(drv)
   ```

2. **Tabular stage artifacts.** Replace `tar_read("three_year_data")$data` etc.
   with an inline native read:

   ```r
   tydata <- DBI::dbGetQuery(con, sprintf(
     "SELECT * FROM read_parquet('%s')", crdc_path("stages/inputs/three_year_data.parquet")))
   ```

   Pooled fits when used: `qs2::qs_read(crdc_path("stages/models/pooled_m2.qs2"))`.

**Driver-retention rule** applies to every DuckDB connection (anonymous driver GC
→ "Invalid connection"). The reads remain visible and native; `crdc_path()`
returns a string and does not perform the read.

### A.2 `crdc_path()` — resolution + caching

- **Signature:** `crdc_path(rel)` → a string usable by `read_parquet()`,
  `qs2::qs_read()`, or `download.file()`.
- **Base:** `Sys.getenv("CRDC_ARTIFACTS", "hf://datasets/civilytics/crdc-school-arrest-rates@civilytics-crdc-arrests-2025.1")`.
  - If the base is a **local directory** (owner/dev): return `file.path(base, rel)`
    directly — no network, no cache (e.g. `CRDC_ARTIFACTS=export`).
  - If the base is **remote**: small objects return the remote URI for a direct
    read; **big objects are cached** (see below).
- **Big vs small (deterministic prefix rule, no HEAD request):** *big* = `parquet/`
  (draws tree) and `stages/models/` (qs2 fits); *small* = everything else
  (`stages/inputs/`, `stages/crdc/`, `stages/diagnostics/`).
- **Cache location:** `Sys.getenv("CRDC_CACHE", tools::R_user_dir("crdc-arrests", "cache"))`;
  any repo-local cache dir is gitignored.
- **Caching behavior (lazy, first-use):** single big files (`stages/models/*.qs2`)
  fetched via `download.file()` to the cache; the draws **tree** is mirrored on
  first use via a one-time DuckDB `COPY (… read_parquet('hf://…/**')) TO
  '<cache>/parquet' (FORMAT parquet, PARTITION_BY (model_id, YEAR, LEA_STATE))`
  (DuckDB-only, no new dep), after which `crdc_path("parquet")` returns the local
  mirror. Subsequent runs read the cache; no re-download.
- **Pure-ish + testable:** caching is the only side effect, behind an existing-file
  check; unit-testable with a synthetic remote/local fixture.

### A.3 Standalone-renderable (no store at render time)

Each in-scope `.qmd` **must** render via `quarto render <doc>.qmd` on a clean
checkout with no `_targets/` store and no `tar_make()` — it reads only
`crdc_path()`-resolved artifacts. **No `targets::tar_read()`/`tar_load()` of the
store may remain in any doc.** (The staging targets that *build* the artifacts do
read the store — that is the owner/pipeline side, separate from the docs.)

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
                                            labels from the model registry)
               hmc_diagnostics.parquet    (pooled divergence / max-treedepth /
                                            E-BFMI per chain)
  models/      pooled_m1.qs2 … pooled_m5.qs2   (the 5 nat_* brms fits, ~2.9 GB)
parquet/       (unchanged — Subsystem 1 draws shards)            [BIG — cached]
summary.duckdb (unchanged — Subsystem 1 API summary tables)
```

**Materializer contract.** Each staging target's output **must contain exactly
what the in-scope docs read** from the corresponding store target. `three_year_data`
/ `recent_data` are *lists*; docs use `$data`, but the implementation audits each
doc and, if any non-`$data` element is consumed (e.g. restriction metadata),
publishes it as a small companion file under `stages/inputs/`.

**Diagnostics targets** read the model targets from the store (owner-side only):
`model_stats` writes `calculate_model_stats()` output for each model with a human
`model_label` drawn from the **model registry**; `hmc_diagnostics` extracts
structured pooled-model sampler diagnostics (`rstan::get_num_divergent`,
`get_num_max_treedepth`, `get_bfmi`, …). `results.qmd` shows pooled diagnostics
live from the shipped `pooled_m*.qs2` when present, falling back to this table.

**Publishing.** Reuse the Subsystem-1 HF publish mechanism (the path already used
for `parquet/` + `summary.duckdb`), pinned to `civilytics-crdc-arrests-2025.1`.
Implementation confirms the exact tool (huggingface CLI / existing script).

## C. Stage provenance documentation

A user-facing deliverable that **connects each staged artifact to its place in the
pipeline**, so the difference between stages is legible:

- **`docs/data-stages.md`** — a "stage map": for each `stages/` artifact, its source
  target(s), pipeline stage (raw CRDC → enrollment/referral processing →
  `model_data` → combined → restricted model inputs → fits → draws → summaries),
  grain, key columns, approximate size, and which docs consume it. Cross-links the
  Subsystem-1 `docs/api/data-dictionary.md`.
- A **diagram** (Mermaid or the existing ASCII DAG style) showing source CSV →
  intermediate targets → staged artifacts → published draws/summary, marking which
  nodes are published and which are owner-only (the store/DB/fits).

## D. Re-point each doc + new `white_paper.qmd`

| Doc | Change |
|-----|--------|
| `results.qmd` | Connection→view re-point via `crdc_path("parquet")`; `tar_read()`→`read_parquet`; pooled diagnostics live from `pooled_m*.qs2`; subgroup stats from `model_stats.parquet`; labels from the registry. |
| `applied_examples.qmd` | Connection→view re-point; `tar_read(three_year_data/recent_data)`→`read_parquet`; registry labels in model-name maps. |
| `social_media_posts.qmd` | Connection→view re-point; `tar_read()`→`read_parquet`; keep `civilytics` theme/logo + `magick`/`ragg` table images; registry labels. |
| `combined_eda.qmd` | `tar_read()`→`read_parquet`; keep `tigris` maps + `civilytics` theme. |
| `annual_descriptives_template.qmd` | parameterized `read_parquet(crdc_path(sprintf("stages/crdc/model_data_%s.parquet", suffix)))` etc. |
| `model_descriptives_template.qmd` | Same parameterized re-point; give it a **distinct** `fig.path` (currently collides with `appliedexample-`). |
| **`white_paper.qmd`** (new) | Authored from the user-supplied report source; themed via `use_civilytics_theme()`; figures/tables wired to the artifacts (patterns above). |

No analytical/plotting logic changes — figures stay visually identical; only the
data source and model labels change.

**Render targets** in `_targets.R`, all `cue = tar_cue(mode = "never")`: reinstate
`combined_eda` (`tar_render`) and `annual_report` (`tar_render_rep` ×3 years); add
`model_descriptives` (`tar_render_rep` ×3), and `white_paper` / `results` /
`applied_examples` / `social_media_posts` (`tar_render`); plus the staging targets
(`stage_inputs_*`, `stage_crdc_*`, `model_stats`, `hmc_diagnostics`, `pooled_fits`,
`publish_stages`). Render targets depend on the staging targets for graph
correctness; `cue = never` keeps both out of routine `tar_make()`.

**Sequencing note.** `white_paper.qmd` *authoring* is gated on the user-supplied
report source. The themed scaffold (brand files, format YAML, artifact-wired
result/figure chunks) can be built first; the prose is ported once provided.

## E. One-command render + caching primer + determinism

- **`scripts/render-artifacts.sh`** — one command: prime the cache (build staging
  targets locally if the store is present, else `crdc_path()` lazily fetches from
  HF), then render the in-scope docs (`quarto render` or `tar_make(names = …)`).
- **Cache primer (optional):** `scripts/cache-artifacts.sh` (or `crdc_path()` on
  first use) mirrors the big objects (draws parquet, pooled fits) into the cache so
  later renders avoid re-downloads. Small objects read directly from `hf://`.
- **Stranger flow (documented):** zero-setup (`CRDC_ARTIFACTS=hf://…`, range-reads
  + lazy cache) or pre-mirror then render. Fonts: `civilytics_load_fonts()`
  downloads Google fonts on first use — document the network need / caching.
- **Determinism statement** (REPRODUCIBILITY.md): global seed `11213`; figures are
  **statistically reproducible, not bit-for-bit** (threaded Stan), inheriting
  Subsystem 2's stance; figure dims/dpi pinned per the docs' YAML.

## F. renv render-deps

Install only the genuinely-needed render-only deps, **narrow the `.renvignore`
`*.qmd` exclusions** from Subsystem 2 for the in-scope docs, and **re-snapshot**
`renv.lock`:

- Required: `quarto`, `ggdist`, `tidybayes`, `ggridges`, `marginaleffects`,
  `patchwork`, `flextable`, `gdtools`, `systemfonts`, `DT`, `tigris`, `sf`,
  `magick`, `ragg`, `sysfonts`, `showtext`, and `civilytics` (already in lib at
  v0.2.0; pin from its Gitea source).
- **System libs** (confirm with the user before any `apt`): `libmagick++-dev`
  (magick), and the GDAL/GEOS/PROJ stack for `sf`/`tigris` if not already present.
- Validate the final list by rendering each in-scope doc and resolving missing
  symbols; drop anything not actually used.

## G. CI — parse/validate only

Extend the existing parse-only job in `.gitea/workflows/test.yml`:

- `tar_validate()` must still load with the new render + staging targets (install
  only the packages required to *source* `_targets.R`, incl. `tarchetypes`).
- **Static read-contract check** (`Rscript`, no render): for each in-scope `.qmd`,
  parse out every `crdc_path("…")` / `read_parquet` / `predicted_draws`-view
  reference and assert each resolves to a path a staging target writes (or the
  unchanged `parquet/` draws). Also assert **no `tar_read`/`tar_load` of the store
  remains** in any doc (the standalone-render guarantee).
- **No `quarto render`, no model fitting**, consistent with the no-node
  `ubuntu-latest` runner and Subsystem 2's stance.

## H. Tests / verification

- **Unit tests** (synthetic fixtures): staging materializers produce the expected
  parquet shape/columns; list-target (`three_year_data`/`recent_data`) handling
  captures all consumed components; the `predicted_draws`-view-over-parquet round
  trips `get_prediction_summary()` against a tiny synthetic parquet set; the
  diagnostics target emits registry-driven `model_label` values.
- **`crdc_path()` tests:** local-base passthrough; remote small→URI; remote
  big→cache-then-local; cache hit avoids re-fetch; `CRDC_CACHE` honored.
- **Read-contract test** (the §G check) + a **standalone-render assertion** (no
  `tar_read` of the store in any doc).
- **Local render smoke** (owner, gated): render `white_paper.qmd` + `results.qmd`
  against local `export/stages/` before merge. Confirm with the user before any
  long render.
- Run the suite with `./scripts/run-tests.sh`.

## I. Concurrent deep-rename interface

The deep rename + re-run happens **on another machine, concurrently**, on its own
branch (e.g. `feature/pooled-rename`). This subsystem makes that merge cheap:

- **Model registry (§12)** is the single place ids appear. Now: ids = `nat_*` /
  `sg_*`, labels = "Pooled (m#)" / "Student-group (m#)". After the rename: flip ids
  to `pooled_*` in the registry only.
- **What the other machine commits to git** is *code* (renamed target names in
  `_targets.R`, renamed `model_id` in `R/`, updated `docs/data-stages.md` /
  data dictionary, a bumped `data_release` e.g. `…-2025.2`). The heavy outputs
  (store, 69 GB DB, republished HF `parquet/` + `summary.duckdb`, the release) go
  to **HF/release, not git** — so it can push freely while work proceeds here.
- **Integration path when it lands:** (1) flip registry ids `nat_*`→`pooled_*`;
  (2) bump the `CRDC_BASE` release pin; (3) re-run staging + `publish_stages` so
  `stages/` carries `pooled_*` keys/labels; (4) re-render.
- **Guardrail:** do **not** merge the rename branch to `main` until its re-run has
  actually republished under the new release, or the docs would reference
  `pooled_*` data that isn't published yet.
- **Plan checkpoint:** the implementation plan includes an explicit step that
  **cues the user to start the re-run/rename on the other machine** (after the
  registry exists so both branches share the abstraction).

---

## Out of scope

- Refitting any model in this subsystem's pipeline/CI/renders (the renders never fit).
- Changing Subsystem 1 (API / HF data product / Pages-for-docs) or Subsystem 2
  (pipeline) behavior.
- Gitea Pages deploy of the rendered HTML (committed/release artifacts only).
- FIPS→state cosmetic (geo-match is already 1.0).
- The **deep `pooled_*` rename re-run** itself (runs concurrently on another
  machine; this subsystem only provides the registry + integration path — §I).

## Future work (separately specced / concurrent)

- **Deep rename + re-run** (the other machine): rename target names + published
  `model_id` `nat_*`→`pooled_*`, re-run the ~7-day pipeline, republish API / HF /
  release under a new `data_release`. Breaking change to launched Subsystem 1; its
  own effort, integrated here via §I.
- Optional `pooled_*` **non-breaking aliases** in the Subsystem-1 API /
  data dictionary (keeping `nat_*` stored) as an interim step.

## Files touched (summary)

| File | Change |
|------|--------|
| `white_paper.qmd` | new (imported narrative; civilytics theme; artifact-wired) |
| `results.qmd`, `applied_examples.qmd`, `social_media_posts.qmd`, `combined_eda.qmd` | re-point reads via `crdc_path()`; registry labels; remove store `tar_read` |
| `annual_descriptives_template.qmd`, `model_descriptives_template.qmd` | parameterized re-point; fix `model_descriptives` `fig.path` collision |
| `R/crdc_path.R` | new — path-resolver + caching (returns URI string) |
| `R/model_registry.R` / `inst/models.yml` | new — model ids + labels + grouping (single source of truth) |
| `R/stage_artifacts.R` | new — staging materializers (inputs, crdc, diagnostics, pooled fits) |
| `R/publish_stages.R` | new — HF upload of `export/stages/` (reuses S1 publish path) |
| `_targets.R` | reinstate `combined_eda` + `annual_report`; add render targets (`cue=never`) + staging/diagnostics/pooled-fits/publish targets |
| `_brand.yml`, `theme/`, `latex/`, `typst/`, logos | new — via `civilytics::use_civilytics_theme()` |
| `docs/data-stages.md` | new — stage→pipeline provenance map + diagram |
| `scripts/render-artifacts.sh`, `scripts/cache-artifacts.sh` | new — one-command render + cache primer |
| `REPRODUCIBILITY.md`, `README.md` | add artifact-reproduction section + determinism + render deps + cache |
| `.renvignore`, `.gitignore` | narrow `*.qmd` exclusions; ignore the local cache dir |
| `renv.lock` | re-snapshot with render deps |
| `.gitea/workflows/test.yml` | extend parse-only job with the read-contract + no-store check |
| `tests/testthat/test-stage_artifacts.R`, `test-crdc_path.R`, `test-read-contract.R` | new |

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
