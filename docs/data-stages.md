# CRDC Arrests — Data Stages & Artifact Provenance

This map explains the **stages** of the pipeline and the **published artifacts**
emitted at each stage, so you can reproduce any document/figure without the
~7-day model run. It complements the API
[data dictionary](api/data-dictionary.md) (which documents the API summary
tables + draws).

All published artifacts live on the Hugging Face dataset
**`civilytics/crdc-school-arrest-rates`**, pinned to `data_release =
civilytics-crdc-arrests-2025.1`. Documents read them via `crdc_path()` (see
[`REPRODUCIBILITY.md`](../REPRODUCIBILITY.md)): set `CRDC_ARTIFACTS=export` to
read locally (owner), or leave the default `hf://…` (new user; big objects cache
on first use).

## Pipeline stages → artifacts

```mermaid
flowchart TD
  CSV["CRDC + CCD source CSVs<br/>(tmp/data/)"] --> PROC["enrollment / referral processing<br/>(R/funs.R)"]
  PROC --> MD["model_data_{y2122,y1718,y1516}<br/>schenrollraw_, lerefs_, popcounts_,<br/>full_crdc_data_, ccd_sch_geo_, ccd_dist_geo_"]
  MD --> COMB["combined_model_data<br/>combined_sch_data"]
  COMB --> RESTR["recent_data / three_year_data<br/>(restrict_model_data: enroll cap)"]
  RESTR --> FITS["brms fits:<br/>unified_m1..m5 + stratified_m1..m5"]
  FITS --> DRAWS["posterior_db -> predicted_draws<br/>(69 GB DuckDB, owner-only)"]
  DRAWS --> PARQUET["parquet/ shards (1.4 GB)"]
  DRAWS --> SUMM["summary.duckdb<br/>(arrest_summary / state_summary / district_dim)"]

  %% published staged intermediates (Subsystem 3)
  RESTR -.publish.-> SI["stages/inputs/*.parquet"]
  COMB  -.publish.-> SI
  MD    -.publish.-> SC["stages/crdc/*.parquet"]
  FITS  -.publish.-> SD["stages/diagnostics/{model_stats,hmc_diagnostics}.parquet"]
  FITS  -.publish (unified only).-> SM["stages/models/unified_m*.qs2 (2.9 GB)"]
  DRAWS -.already public.-> PARQUET
  DRAWS -.already public.-> SUMM

  classDef owner fill:#f2ede4,stroke:#923d00;
  classDef pub fill:#e6f0ea,stroke:#1f6f70;
  class DRAWS owner;
  class SI,SC,SD,SM,PARQUET,SUMM pub;
```

Solid arrows are the compute pipeline (owner-side; the `_targets/` store + 69 GB
draws DB never ship). Dashed arrows are the **published** artifacts a new user
downloads.

## Artifact catalog

### `stages/inputs/` — model-input frames (~65 MB)

| Artifact | Source target | Grain | Consumed by |
|---|---|---|---|
| `three_year_data.parquet` | `three_year_data$data` | LEA × YEAR × RACE × SEX (3-yr restricted) | supplement, social |
| `recent_data.parquet` | `recent_data$data` | LEA × RACE × SEX (2021-22 restricted) | supplement, social |
| `combined_model_data.parquet` | `combined_model_data` | school × YEAR (3-yr combined) | supplement, social |
| `combined_sch_data.parquet` | `combined_sch_data` | school (CCD, 3-yr) | social |

### `stages/crdc/` — raw/intermediate CRDC (~202 MB)

| Artifact (×3 years where suffixed) | Source target | Consumed by |
|---|---|---|
| `full_crdc_data_{y2122,y1718,y1516}.parquet` | `full_crdc_data_*` | supplement, social |
| `model_data_{…}.parquet` | `model_data_*` | supplement, annual/model descriptives |
| `popcounts_{…}.parquet` | `popcounts_*` | supplement |
| `schenrollraw_{…}.parquet` | `schenrollraw_*` | supplement |
| `lerefs_{…}.parquet` | `lerefs_*` | supplement |
| `ccd_sch_geo_{…}.parquet` | `ccd_sch_geo_*` | supplement |
| `ccd_dist_geo_{…}.parquet` | `ccd_dist_geo_*` | annual/model descriptives |

### `stages/diagnostics/` — model diagnostics (small)

| Artifact | Source | Notes | Consumed by |
|---|---|---|---|
| `model_stats.parquet` | `calculate_model_stats()` over all 10 models | per-model convergence/runtime stats; `model_id` + registry `model_label` ("Unified (m#)" / "Stratified (m#)"); stratified models contribute their per-group rows | supplement (model-stats tables) |
| `hmc_diagnostics.parquet` | unified fits' sampler diagnostics | divergences / max-treedepth / E-BFMI per unified model | supplement (HMC fallback) |

### `stages/models/` — unified fits (~2.9 GB, optional)

| Artifact | Source target | Notes |
|---|---|---|
| `unified_m{1..5}.qs2` | `unified_m{1..5}_mod` | the 5 unified brms fits; let `supplement.qmd` run **live** `check_hmc_diagnostics()`. Stratified fits (`stratified_*`, ~31 GB) are **not** shipped — their stats come from `model_stats.parquet`. |

### Already public (Subsystem 1)

| Artifact | Notes |
|---|---|
| `parquet/` shards (1.4 GB) | raw posterior draws, partitioned `model_id/YEAR/LEA_STATE`; the docs' `predicted_draws` view reads these |
| `summary.duckdb` (~247 MB) | API summary tables (`arrest_summary`, `state_summary`, `district_dim`, `meta`) |

## Naming note (unified vs stratified)

The published `model_id` keys are `unified_*` (one model fit to the whole
dataset, all student groups together) and `stratified_*` (one model per student
group). Subsystem-3 artifacts display these as "Unified (m#)" / "Stratified (m#)"
via the model registry (`R/model_registry.R`), the single source of truth for the
model vocabulary, so the keys, the data contract, and the white-paper prose all
agree.

## Reproduction download sizes

- **Core** (all docs; diagnostics from the table): `stages/` data (<300 MB) +
  `parquet/` (1.4 GB) ≈ **~1.7 GB**.
- **+ live unified diagnostics**: add `stages/models/` (~2.9 GB) ≈ **~4.6 GB**.

Versus the owner-side cost this avoids: the 18 GB `_targets/` store, the 69 GB
draws DB, and the ~7-day model run.
