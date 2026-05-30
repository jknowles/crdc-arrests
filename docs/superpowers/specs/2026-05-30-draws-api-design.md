# Draws API — Design Spec

**Date:** 2026-05-30
**Branch:** `feature/draws-api`
**Author:** Jared Knowles (Civilytics) w/ Claude
**Status:** Draft for review

---

## 1. Purpose & Context

The CRDC arrest-rate project fits 10 Bayesian hierarchical models (`brms`) and
streams 500 posterior prediction draws per group into a **69 GB DuckDB**
(`export/db/crdc_arrests.duckdb`, table `predicted_draws`, 1.14 B rows / 2.27 M
groups). Running the models requires ~64 GB RAM and multi-day compute.

**Goal:** let people — and AI coding agents — query the model results *without*
re-running the models, via a public, reproducible, two-tier data product:

- **Tier 1 (live API):** summarized estimates (point + credible intervals) for
  districts and states, served from a small precomputed DuckDB.
- **Tier 2 (bulk):** the full raw posterior draws, published as partitioned
  Parquet on Hugging Face, queryable by shard with DuckDB.

This spec covers **only the Draws API subsystem**. Two sibling subsystems —
(a) end-to-end pipeline reproducibility polish and (b) artifact reproduction
(white paper, social posts, EDA) — are **out of scope** here and get their own
spec → plan → implementation cycles.

### Decisions locked during brainstorming

| # | Decision | Choice |
|---|----------|--------|
| 1 | Sequencing | Draws API first; pipeline-polish + artifacts are later specs |
| 2 | Tiers | Two-tier; **build both tiers now** |
| 3 | Default payload | Summaries by default, raw draws via bulk (tier 2) |
| 4 | API stack | **R + plumber**, made agent-friendly via OpenAPI + JSON envelope + `llms.txt` |
| 5 | Raw-draw access | Bulk Parquet on **Hugging Face**; DuckDB-httpfs reads shards |
| 6 | Lookup | Names + geo + codes (district/state names, lat/lon from CCD) |
| 7 | Models exposed | All 10, with a documented default |
| 8 | Default model | **`nat_m2` / `sg_m2`** (most-recent-year + referral_rate) |
| 9 | State estimates | Include a **state-level summary** (draw-wise population aggregate) |
| 10 | Live hosting | **SWAG self-host + free Cloudflare CDN caching + rate-limit** |
| 11 | Docs/bulk | Static docs + downloadable DuckDB/Parquet on **Gitea Pages** (`pages.civilytics.org/crdc-arrests`) |
| 12 | Portability | Container identical to a free-PaaS image (HF Space/Render) — redeployable with zero code change |

---

## 2. Architecture Overview

```
                 targets pipeline (reproducible, from source)
                                  │  (existing: models + posterior_db → predicted_draws DuckDB, 69 GB)
   ┌──────────────────────────────┼───────────────────────────────────────┐
   ▼                ▼              ▼                       ▼
district_dim   arrest_summary  state_summary          draws_parquet
(names+geo)    (LEA grain,     (state grain,          (raw draws →
               2.27M rows)     draw-wise agg)          partitioned Parquet)
   └──────┬─────────┴───────────────┘                       │
          ▼                                                  ▼
  export/api/crdc_api.duckdb  (~150–300 MB)        export/parquet/… shards
          │                                                  │
          ▼                                          push to Hugging Face
  ┌─────────────────────────┐                       (dataset repo + card)
  │ plumber API (Docker)     │                               │
  │ /estimates /states       │                       DuckDB-httpfs by shard
  │ /districts /models /draws│                       (advanced/bulk users)
  │ OpenAPI + JSON envelope  │
  └─────────────────────────┘
     SWAG reverse proxy ── Cloudflare (free) edge cache + rate-limit
                                  │
        Gitea Pages: static docs + landing + OpenAPI + download links
```

**Key property exploited everywhere:** the API is **read-only over static data
that changes only when the pipeline re-runs**. Responses are *immutable per
`data_release`*, enabling aggressive edge caching and trivial portability.

---

## 3. Data Layer (new pipeline targets)

All targets are added to `_targets.R`, downstream of the existing model and
`posterior_db` targets, so `tar_make()` reproduces the entire data product.

### 3.1 `district_dim` — lookup / dimension table
Combine the per-year `ccd_dist_geo_*` directory targets (mirroring the existing
`combined_sch_data`) into one LEA-level table:

`LEAID, lea_name, LEA_STATE, state_name, lat, lon, enrollment, urbanicity`

Powers name/geo lookup and is joined into summaries for human-readable output.

### 3.2 `arrest_summary` — Tier-1 LEA summary (~2.27 M rows)
Computed in DuckDB SQL over `predicted_draws` (handles 1.14 B rows well). One row
per `LEAID × YEAR × RACE × SEX × model_id`:

- Keys + `n_draws`, `stu_enroll` (joined from model data — **not present in
  `predicted_draws`**, must be joined back), observed `ARRESTS` (reference)
- **Count** estimates: `count_median`, `count_mean`, `count_sd`
- **Rate** estimates (`pred / stu_enroll` per draw): `rate_median`, `rate_mean`
- **HPD intervals at 50 / 80 / 95%** for both count and rate
  (`{count,rate}_lower_{50,80,95}`, `{count,rate}_upper_{50,80,95}`), reusing the
  smallest-window HPD logic in `R/db_views_experimental.R`
- Joined `lea_name`, `state_name`, `lat`, `lon` from `district_dim`

### 3.3 `state_summary` — Tier-1 state summary (small)
**Draw-wise population aggregate** (statistically correct — preserves per-draw
covariance): within each posterior draw, `SUM(pred)` and `SUM(stu_enroll)` across
LEAs in the state, compute `rate = sum(pred)/sum(enroll)` per draw, *then*
summarize across draws. Grain: `LEA_STATE × RACE × SEX × YEAR × model_id`.
Same estimate/interval columns as `arrest_summary`. Computed from
`predicted_draws` (not from the LEA summary).

> Note: this is a **population aggregate**, distinct from the model's
> `(1|LEA_STATE)` random-effect estimate. Documented as such in the API.

### 3.4 Materialization
`district_dim`, `arrest_summary`, `state_summary` → **`export/api/crdc_api.duckdb`**
(the only data file the container needs, est. 150–300 MB) with indices on the
query keys. A `data_release` tag (e.g. `2025-crdc-3yr`) and pipeline metadata are
stored in a `meta` table.

### 3.5 `draws_parquet` — Tier-2 bulk export
`COPY predicted_draws TO 'export/parquet/' (FORMAT parquet,
PARTITION_BY (model_id, YEAR, LEA_STATE))`, **sorted within shard by
`(LEAID, RACE, SEX)`** for row-group pruning, target ~10–50 MB/shard
(~1,200–1,500 files). Do **not** partition by RACE/SEX (file explosion; weak
pruning value vs. sort-based row-group stats).

A separate, credentialed, **manual** publish step (`scripts/publish_hf.R`) pushes
shards to a Hugging Face dataset repo with a dataset card. DuckDB-httpfs read
instructions live in the docs.

### 3.6 Code organization (refactor, not duplicate)
Split the existing `R/postprocess.R` + `R/db_views_experimental.R` into focused
files (per coding-style: small, single-purpose):
- `R/summarize_draws.R` — `arrest_summary` + `state_summary` SQL materialization
  (reuses existing HPD SQL)
- `R/export_parquet.R` — partitioned Parquet export
- `R/district_dim.R` — `combined_dist_geo` / `district_dim` assembly

---

## 4. API Surface (plumber)

**Versioned base path `/api/v1`.** One read-only DuckDB connection per worker
process to `crdc_api.duckdb`.

| Method / path | Purpose | Key params |
|---|---|---|
| `GET /health` | Liveness probe | — |
| `GET /` | API metadata: version, `data_release`, citation, doc links | — |
| `GET /openapi.json` + `/__docs__/` | OpenAPI spec + Swagger UI (auto) | — |
| `GET /models` | List all 10 models (formula, sample, `is_default`) | — |
| `GET /districts` | Name/geo lookup → LEAID | `q`, `state`, `limit`, `offset` |
| `GET /estimates` | **Core** LEA summaries (count + rate + interval) | `leaid`, `state`, `race`, `sex`, `year`, `model`, `interval`, `page`, `limit` |
| `GET /estimates/{leaid}` | All demographics for one district | `model`, `year`, `interval` |
| `GET /states` | State-level summaries | `state`, `race`, `sex`, `year`, `model`, `interval`, `page`, `limit` |
| `GET /states/{state}` | All demographics for one state | `model`, `year`, `interval` |
| `GET /draws` | Tier-2 locator: HF shard URL(s) + ready-to-run DuckDB SQL for the slice (does **not** stream draws) | same filters as `/estimates` |

### 4.1 JSON envelope (matches global API-response convention)
```json
{
  "status": "success",
  "data": [ {
    "leaid": "...", "lea_name": "...", "state": "TX", "lat": 0, "lon": 0,
    "race": "BL", "sex": "M", "year": "21-22", "model": "nat_m2_mod",
    "stu_enroll": 1234, "observed_arrests": 5,
    "rate_median": 0.0041, "rate_lower": 0.0019, "rate_upper": 0.0078,
    "count_median": 5.1, "count_lower": 2.3, "count_upper": 9.6
  } ],
  "error": null,
  "meta": { "total": 412, "page": 1, "limit": 100,
            "model": "nat_m2_mod", "interval": 0.95,
            "version": "v1", "data_release": "2025-crdc-3yr",
            "citation": "Knowles & Miller 2025" }
}
```
**Defaults:** `model` → `nat_m2`/`sg_m2`, `interval` → `0.95`, `year` → `21-22`.
The `lower`/`upper` returned reflect the requested `interval` (50/80/95).

### 4.2 Input validation (fail-fast at boundary)
- `model` ∈ the 10 allowed ids; `interval` ∈ {50, 80, 95}
- `race` ∈ {WH, BL, AM, HI, …}; `sex` ∈ {M, F}; `year` ∈ {15-16, 17-18, 21-22}
- `leaid`/`state` format checks; `limit` capped (e.g. ≤ 1000), `page`/`offset` ≥ 0
- Invalid input → `400` with a clear, non-leaking message in the envelope.

### 4.3 Agent-friendliness
- Complete **OpenAPI** with param enums + descriptions + response schema + examples.
- Root `/` + `llms.txt`: plain-text API description with copy-paste **R (httr2)**,
  **Python (requests)**, and **DuckDB-over-HF** snippets.
- Stable versioned path, consistent envelope, explicit enums everywhere.
- (Future, out of scope: a thin MCP wrapper over the OpenAPI surface.)

### 4.4 Errors & security
- Structured envelope errors; never leak internals (404 unknown LEAID/state,
  400 bad params, 500 generic).
- Query timeout + `limit` caps guard against expensive/unbounded queries.
- Rate-limit + CORS at the proxy/edge layer (see §5).

### 4.5 File layout
```
api/
  plumber.R                 # assembly, OpenAPI metadata, filters (throttle/log/CORS)
  R/db.R R/validate.R R/envelope.R
  R/handlers_estimates.R R/handlers_states.R
  R/handlers_districts.R R/handlers_models.R R/handlers_draws.R
  Dockerfile  entrypoint.sh  docker-compose.yml  llms.txt
  tests/testthat/
```

---

## 5. Deployment

**Live API — Option 1: self-host on SWAG, fronted by free Cloudflare.**
- `api/Dockerfile` on `rocker/r-ver` pinned to the project R version; install
  plumber + DuckDB + minimal deps (**no brms/cmdstan** in the serving image).
  Copy in `crdc_api.duckdb` (~150–300 MB).
- `entrypoint.sh` runs plumber on a fixed port, N workers; bind `0.0.0.0`,
  `EXPOSE` the port.
- Deploy via existing Gitea Actions → Docker-socket flow; route through **SWAG**
  (public reverse proxy), **not** tsdproxy (tailnet-only).
- Put the public domain on **Cloudflare (free)**: immutable cache headers
  `Cache-Control: public, max-age=31536000, immutable` (versioned by
  `data_release`), a Cache Rule making the JSON edge-cacheable, plus
  rate-limiting. Origin CPU hit only on cache misses → negligible.
  Purge cache on each new `data_release`.
- **Host-load mitigation rationale:** indexed query over 2.27 M rows ≈ low-ms on
  a fraction of a core; pagination/`limit` caps + query timeout bound cost; edge
  cache absorbs popular traffic; SWAG/Cloudflare rate-limit blunts scrapers.

**Bulk + docs — Gitea Pages (`pages.civilytics.org/crdc-arrests`).**
- Static landing page + human docs + rendered OpenAPI + `llms.txt`.
- Download links for `crdc_api.duckdb` and the HF Parquet dataset.
- DuckDB-httpfs query examples for the raw draws.

**Portability fallback.** The container is identical to what a free PaaS needs,
so it redeploys to a **Hugging Face Docker Space** or **Render** with zero code
change if self-host load ever becomes a problem.

---

## 6. Testing (≥ 80% coverage, testthat 3e)

- **Unit:** validators, envelope builders, query construction (pure functions).
- **Integration:** spin up the API against a **tiny synthetic fixture DuckDB**
  (a few LEAs/states/demographics built in test setup); hit every endpoint with
  `httr2`; assert envelope shape, status codes, `400` on bad input, OpenAPI
  served, pagination correctness.
- **Data-contract:** assert `arrest_summary`/`state_summary` schemas; intervals
  ordered (`lower ≤ median ≤ upper`); rates ∈ [0, 1]; state summary equals a
  draw-wise aggregate on the fixture.
- Runs in **Gitea Actions CI** without the 69 GB DB (fixtures only).

---

## 7. Explicitly Out of Scope (future specs)

- Artifact reproduction (white paper, social posts, EDA, applied examples).
- Full environment-capture / `renv` lockfile reproducibility polish.
- **Live** raw-draw *querying* via the API (v1 draws story = HF bulk + DuckDB-httpfs).
- State-level estimates from the `(1|LEA_STATE)` random effect (we ship the
  population aggregate instead).
- MCP server wrapper.

---

## 8. Open Items for Spec Review

- Confirm the exact RACE enum exposed (`WH, BL, AM, HI` per `models.md`; confirm
  whether `TOTAL`/other categories appear for national vs. subgroup models).
- Confirm `data_release` tag string.
- Confirm Hugging Face dataset repo name / namespace.
- Confirm the public API domain (e.g. `api.civilytics.org/crdc` vs. a subdomain).
