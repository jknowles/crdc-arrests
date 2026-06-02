---
license: odc-by
pretty_name: CRDC School Arrest Rates (Bayesian estimates)
language:
  - en
tags:
  - education
  - civil-rights
  - school-discipline
  - bayesian
  - duckdb
---

# CRDC School Arrest Rates — Bayesian Estimates

Model-based estimates of **school-based arrest rates** for U.S. school districts
(LEAs) and states, by race and sex, derived from the U.S. Department of Education
**Civil Rights Data Collection (CRDC)**. Estimates come from Bayesian hierarchical
binomial models (`brms` / Stan) that partially pool sparse counts, producing
stabilized rates with full posterior credible intervals.

**Data release:** `civilytics-crdc-arrests-2025.1`

## What's in this dataset

| File | Description |
|------|-------------|
| `summary.duckdb` | Compact DuckDB (~260 MB) with `arrest_summary` (LEA grain, ~2.27M rows), `state_summary` (draw-wise population aggregate), `district_dim` (names + geo), and a `meta` table. Powers the live API. |
| `parquet/` | The full raw posterior draws (500 per group) as Hive-partitioned Parquet, partitioned by `model_id / YEAR / LEA_STATE` and sorted within shard by `(LEAID, RACE, SEX)`. ~1,387 shards. For advanced/bulk use. |

## Coverage / code lists

- **RACE** ∈ {AM, BL, HI, WH} · **SEX** ∈ {F, M} (8 demographic cells, no TOTAL)
- **YEAR** ∈ {15-16, 17-18, 21-22}
- **Models:** 10 specifications (`nat_m1`–`nat_m5`, `sg_m1`–`sg_m5`); **default = `nat_m2` / `sg_m2`** (most-recent-year + referral-rate covariate).
- Estimates include count + rate point estimates and **HPD intervals at 50 / 80 / 95%**.
- State summaries are a **draw-wise population aggregate** (sum across LEAs within each posterior draw), distinct from the model's `(1|LEA_STATE)` random effect.

## Quick start (DuckDB)

```sql
INSTALL httpfs; LOAD httpfs;

-- Summary estimates: download/attach summary.duckdb, then query arrest_summary / state_summary.
-- Raw draws for one slice (TX, Black males, default model, 2021-22):
SELECT *
FROM read_parquet(
  'hf://datasets/civilytics/crdc-school-arrest-rates/parquet/model_id=nat_m2_mod/YEAR=21-22/LEA_STATE=TX/*.parquet'
)
WHERE RACE = 'BL' AND SEX = 'M'
LIMIT 20;
```

`summary.duckdb` direct URL:
`https://huggingface.co/datasets/civilytics/crdc-school-arrest-rates/resolve/main/summary.duckdb`

## Live API & documentation

- **API:** https://crdc-api.civilytics.org (OpenAPI/Swagger at `/api/v1/__docs__/`, machine guide at `/api/v1/llms.txt`)
- **Docs + data dictionary:** https://pages.civilytics.org/crdc-arrests

## Source data

U.S. Department of Education, Office for Civil Rights — Civil Rights Data Collection
(CRDC), 2015-16, 2017-18, 2021-22; joined to NCES Common Core of Data (CCD) district
directories for names/geography. Sample restrictions (e.g., enrollment ≥ 30) and data
business rules are documented in the data dictionary.

## Citation

> Knowles, J. E., & Miller, H. (2025). *CRDC School Arrest Rates: Bayesian Estimates.* Civilytics.

## License

Released under the **Open Data Commons Attribution License (ODC-BY 1.0)** — you may
share and adapt the data provided you attribute the source (the citation above).
Underlying CRDC data are U.S. federal government public records.
