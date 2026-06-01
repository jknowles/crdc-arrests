# Draws API — Launch Runbook

Steps to take the Draws API from merged code → live public API + published data.
Locked decisions: HF dataset **public** (container fetches `summary.duckdb` with no
auth); `data_release` = `civilytics-crdc-arrests-2025.1`; API at
`crdc-api.civilytics.org`; docs at `pages.civilytics.org/crdc-arrests`;
default model `nat_m2`. Remotes: `origin` dual-pushes to GitHub (canonical) + Gitea
(deploy). Auth note: a stale `GITHUB_TOKEN` may shadow `gh`; if a git/gh command
fails auth, prefix `GITHUB_TOKEN= GH_TOKEN= …` (and restart VS Code to flush it).

Critical path: **B → C → D**. A unblocks D's trigger; E is independent.

---

## A. Land the code
- [ ] Review + merge **PR #1** (`feature/draws-api` → `reproducible_workflow`) on GitHub.
- [ ] Bring it to `main` (deploy triggers on `main`): open `reproducible_workflow → main` PR (or fast-forward), merge.
- [ ] Sync Gitea (web-merges don't auto-propagate): `git checkout main && git pull && git push origin main` (dual-push updates both).

## B. Build the data artifacts (real run, ~69 GB source)
Canonical (your env has `tarchetypes`):
- [ ] `Rscript -e 'targets::tar_make(names = c("api_db", "draws_parquet"))'`
  - Produces `export/api/crdc_api.duckdb` (summary) and `export/parquet/` (shards) from `export/db/crdc_arrests.duckdb`.
- [ ] Validate:
  ```r
  con <- DBI::dbConnect(duckdb::duckdb(), "export/api/crdc_api.duckdb", read_only=TRUE)
  DBI::dbGetQuery(con, "SELECT COUNT(*) FROM arrest_summary")     # ~2.27M
  DBI::dbGetQuery(con, "SELECT COUNT(*) FROM state_summary")
  DBI::dbGetQuery(con, "SELECT AVG(CASE WHEN lea_name IS NOT NULL THEN 1 ELSE 0 END) AS geo_match FROM arrest_summary")  # want ~1.0
  cat(round(file.size("export/api/crdc_api.duckdb")/1e6), "MB\n")  # expect ~150–300
  DBI::dbDisconnect(con, shutdown=TRUE)
  ```
  - [ ] `geo_match` near 1.0 (low → LEAID format mismatch; check the `build_arrest_summary` warning).
  - [ ] Spot-check a known district returns sane rate + ordered interval.
- [ ] Note `export/parquet/` total size + shard count (sanity for HF upload).

> Fallback if an env lacks `tarchetypes`: source `R/{district_dim,summarize_draws,export_parquet}.R`, `tar_read` the `recent_data`/`three_year_data`/`ccd_dist_geo_*` objects, build `enroll_lookup`/`district_dim`, then call `build_arrest_summary` + `build_state_summary` + `export_draws_parquet` directly (mirrors the `api_db`/`draws_parquet` target bodies in `_targets.R`).

## C. Publish to Hugging Face (public)
- [ ] Create the dataset (public): `huggingface-cli repo create civilytics/crdc-school-arrest-rates --repo-type dataset` (or via web; ensure **Public**).
- [ ] `export HF_TOKEN=…` (a write token).
- [ ] `Rscript scripts/publish_db.R` → uploads `summary.duckdb`; copy the printed **DATA_URL** (`https://huggingface.co/datasets/civilytics/crdc-school-arrest-rates/resolve/main/summary.duckdb`).
- [ ] `Rscript scripts/publish_hf.R export/parquet` → uploads `parquet/` shards.
- [ ] Write/confirm the dataset card (description, license, citation = Knowles & Miller 2025, schema link to the data dictionary, DuckDB-over-HF usage snippet).

## D. Deploy (Gitea Action → SWAG → Cloudflare)
**Gitea repo (`jared/aera-crdc2`):**
- [ ] Settings → **Actions: enabled**; confirm the self-hosted **docker-socket runner** is online.
- [ ] Set **variables**: `IMAGE_REF` (e.g. `crdc-api:latest` or your registry ref), `SWAG_NETWORK` (your SWAG docker network name), `API_DOMAIN=crdc-api.civilytics.org`.
- [ ] Set **`DATA_URL`** to the public HF `summary.duckdb` URL from step C. (Public → no token; otherwise add an HF token.)

**SWAG (reverse proxy):**
- [ ] Copy `deploy/swag/crdc-api.subdomain.conf.example` → SWAG `proxy-confs/crdc-api.subdomain.conf`; set `server_name` to `crdc-api.civilytics.org`; confirm upstream `crdc-api:8000` on `${SWAG_NETWORK}`.
- [ ] Reload SWAG (`docker exec swag nginx -s reload` or restart).

**Cloudflare (civilytics.org zone): DNS-only at launch — no change needed.**
- [x] `crdc-api.civilytics.org` resolves via the existing **DNS-only** `*.civilytics.org` wildcard (→ SWAG host `141.154.68.245`); SWAG terminates TLS with its `*.civilytics.org` wildcard cert. Cloudflare is not in the request path — same posture as the other self-hosted services.
- [ ] **Deferred → Gitea issue #1** (if traffic grows): add a *specific* **proxied** `crdc-api` A record (overrides the wildcard for just this name) + a Cache Rule on `/api/*` (respect origin `Cache-Control`; the API sets `immutable` per `data_release`, `no-store` on `/health`) + optional rate-limit, to enable edge caching of the immutable JSON. Prereq: zone SSL/TLS mode = Full/Full(strict).

**Trigger + verify:**
- [ ] Land the change on `main` (push or merge) → Gitea Action builds the image, fetches `DATA_URL`, `docker compose up -d`, runs the health check.
- [ ] `curl https://crdc-api.civilytics.org/api/v1/health` → `{"status":"ok"}`.

## E. Publish docs to Gitea Pages (independent)
- [ ] Publish `docs/api/` (index.md + data-dictionary.md) to `pages.civilytics.org/crdc-arrests` (per the Gitea Pages deploy flow).
- [ ] Confirm the landing page links resolve (API base, Swagger, llms.txt, HF dataset, data dictionary).

## F. End-to-end verification
- [ ] `curl "https://crdc-api.civilytics.org/api/v1/estimates?state=TX&race=BL&sex=M&model=nat_m2&interval=95&limit=1"` → success envelope with `rate_median`/bounds.
- [ ] `curl "https://crdc-api.civilytics.org/api/v1/states/CA?model=nat_m2"` → state aggregate.
- [ ] `curl "https://crdc-api.civilytics.org/api/v1/districts?q=Baltimore"` → name/geo lookup.
- [ ] Open `/api/v1/__docs__/` (Swagger) and `/api/v1/llms.txt`.
- [ ] Draws path: `/api/v1/draws?state=TX&race=BL&sex=M&model=nat_m2` returns an HF shard URL + DuckDB SQL; run that SQL in DuckDB (`INSTALL httpfs; LOAD httpfs; SELECT … read_parquet(...)`) and confirm rows.
- [ ] Confirm a repeat request is served from Cloudflare cache (response headers).

## Post-launch
- [ ] When ready, flip the GitHub repo to **public**.
- [ ] Tag a release matching `data_release` (`civilytics-crdc-arrests-2025.1`).
- [ ] (Optional) add the HPD-vs-median note to the data dictionary if you want to offer equal-tailed intervals later.
