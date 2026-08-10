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
| 13 | Routing | **Subdomain** `crdc-api.civilytics.org` (SWAG subdomain proxy-conf + Cloudflare DNS, orange-cloud) |
| 14 | Deploy mechanism | **Gitea Action → self-hosted runner → docker socket** (no SSH) on the docker host |
| 15 | Infra separation | Public repo is **generic**; all infra values live in **Gitea Actions secrets/vars**, never committed |
| 16 | Summary DB delivery | Published as a **versioned `data_release` artifact** on Hugging Face; image fetches the pinned version (not committed) |
| 17 | `data_release` tag | **`civilytics-crdc-arrests-2025.1`** (brand + CalVer; re-runs bump `.2`, `.3`) |
| 18 | HF dataset repo | **`civilytics/crdc-school-arrest-rates`** — holds both `summary.duckdb` and `parquet/` shards |
| 19 | Demographic enum | **RACE ∈ {AM, BL, HI, WH}, SEX ∈ {F, M}** (8 cells, no TOTAL); YEAR ∈ {15-16, 17-18, 21-22} — data-confirmed |
| 20 | Documentation | First-class deliverable: OpenAPI + `llms.txt` (machine), Gitea Pages site + **data dictionary** (human), README (repo) |

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

### 3.4 Materialization & publishing
`district_dim`, `arrest_summary`, `state_summary` → **`export/api/crdc_api.duckdb`**
(the only data file the container needs, est. 150–300 MB) with indices on the
query keys. The `data_release` tag (`civilytics-crdc-arrests-2025.1`) and pipeline
metadata are stored in a `meta` table.

This DB is **published as a versioned artifact** (tagged by `data_release` =
`civilytics-crdc-arrests-2025.1`) to the Hugging Face dataset repo
**`civilytics/crdc-school-arrest-rates`** (as `summary.duckdb`, alongside the
`parquet/` draw shards). The repo keeps `export/` gitignored; the **image fetches
the pinned `data_release` DB** at build (or first-run) rather than committing the
binary. This keeps the public repo binary-free and makes the image reproducible
by any forker. A `scripts/publish_db.R` (credentialed, manual) performs the upload.

### 3.5 `draws_parquet` — Tier-2 bulk export
`COPY predicted_draws TO 'export/parquet/' (FORMAT parquet,
PARTITION_BY (model_id, YEAR, LEA_STATE))`, **sorted within shard by
`(LEAID, RACE, SEX)`** for row-group pruning, target ~10–50 MB/shard
(~1,200–1,500 files). Do **not** partition by RACE/SEX (file explosion; weak
pruning value vs. sort-based row-group stats).

A separate, credentialed, **manual** publish step (`scripts/publish_hf.R`) pushes
shards to the Hugging Face dataset repo **`civilytics/crdc-school-arrest-rates`**
(under `parquet/`) with a dataset card. DuckDB-httpfs read instructions live in
the docs.

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
            "version": "v1", "data_release": "civilytics-crdc-arrests-2025.1",
            "citation": "Knowles & Miller 2025" }
}
```
**Defaults:** `model` → `nat_m2`/`sg_m2`, `interval` → `0.95`, `year` → `21-22`.
The `lower`/`upper` returned reflect the requested `interval` (50/80/95).

### 4.2 Input validation (fail-fast at boundary)
- `model` ∈ the 10 allowed ids (`nat_m1`…`nat_m5`, `sg_m1`…`sg_m5`); `interval` ∈ {50, 80, 95}
- `race` ∈ {AM, BL, HI, WH}; `sex` ∈ {F, M}; `year` ∈ {15-16, 17-18, 21-22} (data-confirmed enums)
- `leaid`/`state` format checks; `limit` capped (e.g. ≤ 1000), `page`/`offset` ≥ 0
- Invalid input → `400` with a clear, non-leaking message in the envelope.

### 4.3 National vs. subgroup model resolution
- For **national** models (`nat_m*`) `subgroup_id == model_id`; a demographic
  estimate comes from the single national fit's prediction for that `RACE×SEX`.
- For **subgroup** models (`sg_m*`) each `RACE×SEX` group is fit separately;
  `subgroup_id ∈ {AM_F, AM_M, BL_F, BL_M, HI_F, HI_M, WH_F, WH_M}`. A query for
  `race=BL, sex=M, model=sg_m2` resolves to `model_id=sg_m2_mod,
  subgroup_id=BL_M`. The API hides this mapping behind `race`/`sex` params; the
  data dictionary documents it.

### 4.4 Agent-friendliness
- Complete **OpenAPI** with param enums + descriptions + response schema + examples.
- Root `/` + `llms.txt`: plain-text API description with copy-paste **R (httr2)**,
  **Python (requests)**, and **DuckDB-over-HF** snippets.
- Stable versioned path, consistent envelope, explicit enums everywhere.
- (Future, out of scope: a thin MCP wrapper over the OpenAPI surface.)

### 4.5 Errors & security
- Structured envelope errors; never leak internals (404 unknown LEAID/state,
  400 bad params, 500 generic).
- Query timeout + `limit` caps guard against expensive/unbounded queries.
- Rate-limit + CORS at the proxy/edge layer (see §5).

### 4.6 File layout
```
api/
  plumber.R                 # assembly, OpenAPI metadata, filters (throttle/log/CORS)
  R/db.R R/validate.R R/envelope.R
  R/handlers_estimates.R R/handlers_states.R
  R/handlers_districts.R R/handlers_models.R R/handlers_draws.R
  Dockerfile  entrypoint.sh  llms.txt
  tests/testthat/
deploy/
  docker-compose.yml                 # generic; SWAG network + domain via ${VARS}
  swag/crdc-api.subdomain.conf.example  # templated proxy-conf (placeholders)
  .env.example                       # names of required vars, NO values
.gitea/workflows/deploy.yml          # generic; uses ${{ secrets.* }} / ${{ vars.* }}
scripts/publish_hf.R  scripts/publish_db.R
```

---

## 5. Deployment

**Live API — Option 1: self-host on SWAG, fronted by free Cloudflare,
deployed from this repo via a Gitea Action.** Routed at the **subdomain
`crdc-api.civilytics.org`**.

### 5.1 Image
- `api/Dockerfile` on `rocker/r-ver` pinned to the project R version; install
  plumber + DuckDB + minimal deps (**no brms/cmdstan** in the serving image).
- The `crdc_api.duckdb` is **fetched at build/first-run** from the pinned
  `data_release` artifact on Hugging Face — **not** committed (see §3.4).
- `entrypoint.sh` runs plumber on a fixed port, N workers; bind `0.0.0.0`,
  `EXPOSE` the port.

### 5.2 SWAG + Cloudflare wiring
- Container **joins SWAG's external docker network** so nginx resolves it by
  container name (`crdc-api`). Compose declares
  `networks: swag: { external: true, name: ${SWAG_NETWORK} }`.
- **SWAG subdomain proxy-conf** (`crdc-api.subdomain.conf`): `server_name` from
  the deploy var, `set $upstream_app crdc-api;` `proxy_pass` to the app port.
  A **templated `.example`** ships in the repo; the real conf is rendered from
  Gitea vars at deploy (or kept in the private infra repo).
- **Cloudflare (free):** DNS record for `crdc-api` (orange-cloud → edge cache);
  Cache Rule making the JSON cacheable; rate-limiting. Purge cache on each new
  `data_release`.
  **Superseded 2026-08-10:** this originally specified
  `Cache-Control: public, max-age=31536000, immutable`. Sending a one-year
  `immutable` TTL to *browsers* made any bad response unrecoverable — when CORS
  headers were added, every client that had already fetched a URL kept the
  headerless copy pinned for a year with no revalidation. The long TTL now lives
  only at the edge, which we can purge: `public, max-age=600, s-maxage=31536000`.
  See `CACHE_STATIC` in `api/plumber.R`.
- **Host-load mitigation:** indexed query over 2.27 M rows ≈ low-ms on a fraction
  of a core; pagination/`limit` caps + query timeout bound cost; edge cache
  absorbs popular traffic; Cloudflare/SWAG rate-limit blunts scrapers.

### 5.3 Deploy mechanism (open-source repo, private infra)
- **Self-hosted Gitea runner on the docker host with the docker socket** (the
  `gitea-docker-socket-deploy` pattern — no SSH).
- `.gitea/workflows/deploy.yml` (generic): on push to `main`/tag → build image →
  `docker compose up -d` with env injected from Gitea **secrets/variables**.
- **All infra specifics live in Gitea, never in the repo:** `SWAG_NETWORK`,
  `API_DOMAIN` (`crdc-api.civilytics.org`), `DEPLOY_*`, registry creds, any
  Cloudflare token. Committed files reference these by name only.
- `deploy/.env.example` documents the required variable *names* with no values.
  A forker supplies their own → working deploy without touching code.

### 5.4 Bulk + docs — Gitea Pages (`pages.civilytics.org/crdc-arrests`)
- Static landing page + human docs + rendered OpenAPI + `llms.txt`.
- Download links for `crdc_api.duckdb` and the HF Parquet dataset.
- DuckDB-httpfs query examples for the raw draws.

### 5.5 Portability fallback
The image is identical to what a free PaaS needs, so it redeploys to a
**Hugging Face Docker Space** or **Render** with zero code change if self-host
load ever becomes a problem.

---

## 6. Documentation (first-class deliverable)

Three surfaces, all in scope and verified in CI where possible:

**Machine-readable (for agents & programmatic clients):**
- **OpenAPI/Swagger** auto-generated by plumber at `/openapi.json` + `/__docs__/`,
  with param enums, descriptions, response schema, and examples.
- **`llms.txt`** at the API root: plain-text description + copy-paste **R (httr2)**,
  **Python (requests)**, and **DuckDB-over-HF** snippets.

**Human-readable (Gitea Pages, `pages.civilytics.org/crdc-arrests`):**
- Landing page (what this is, citation, AERA/NSF acknowledgement).
- Usage guide + endpoint reference (rendered from OpenAPI).
- **Data dictionary** (below).
- Download links: `summary.duckdb` + HF Parquet dataset; DuckDB-httpfs examples.

**Repo:** README section pointing to the API + docs; `deploy/.env.example`
documenting required deploy variables.

### 6.1 Data dictionary (content outline)
- **Column defs** for `arrest_summary` / `state_summary` (keys, `n_draws`,
  `stu_enroll`, `observed_arrests`, count + rate estimates, 50/80/95 HPD bounds).
- **Code lists:** RACE `{AM, BL, HI, WH}`, SEX `{F, M}`, YEAR `{15-16, 17-18,
  21-22}`, the 10 model ids + formulas (from `models.md`), default = `nat_m2`/`sg_m2`.
- **National vs. subgroup semantics** (§4.3) and `subgroup_id` mapping.
- **Interval interpretation:** HPD (smallest-width) at the chosen mass; rate vs.
  count; state = draw-wise population aggregate (§3.3), not the `(1|LEA_STATE)` effect.
- **Sample restrictions** (enroll ≥ 30, grade > 7, capped over-counts; from `models.md`).
- **Citation** + `data_release` provenance.

## 7. Testing (≥ 80% coverage, testthat 3e)

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

## 8. Explicitly Out of Scope (future specs)

- Artifact reproduction (white paper, social posts, EDA, applied examples).
- Full environment-capture / `renv` lockfile reproducibility polish.
- **Live** raw-draw *querying* via the API (v1 draws story = HF bulk + DuckDB-httpfs).
- State-level estimates from the `(1|LEA_STATE)` random effect (we ship the
  population aggregate instead).
- MCP server wrapper.

---

## 9. Resolved Items (locked)

- **RACE/SEX/YEAR enum** — data-confirmed: RACE `{AM, BL, HI, WH}`, SEX `{F, M}`,
  YEAR `{15-16, 17-18, 21-22}`; 8 demographic cells, **no TOTAL**.
- **`data_release` tag** — `civilytics-crdc-arrests-2025.1` (brand + CalVer).
- **HF dataset repo** — `civilytics/crdc-school-arrest-rates` (summary DB + Parquet).
- **Summary DB artifact host** — Hugging Face.
- **API domain** — `crdc-api.civilytics.org`; docs — `pages.civilytics.org/crdc-arrests`.

No open items remain.
