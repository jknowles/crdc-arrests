# Draws API — Launch Record

Status: **launched and live**, confirmed 2026-07-07. This document records
what was done; see "Re-launch / re-deploy" at the bottom for the steps to
repeat after a model re-run or a `data_release` bump.

Locked decisions: HF dataset **public** (container fetches `summary.duckdb`
with no auth); `data_release` = `civilytics-crdc-arrests-2025.1`; API at
`crdc-api.civilytics.org`; docs at `pages.civilytics.org/crdc-arrests`;
default model `unified_m2`. Remotes: `origin` dual-pushes to GitHub
(canonical) + Gitea (deploy).

## A. Code landed
- [x] `feature/draws-api` merged to `main` (GitHub and Gitea in sync).

## B. Data artifacts built
- [x] `export/api/crdc_api.duckdb` (summary) and `export/parquet/` (shards)
  built via `tar_make(names = c("api_db", "draws_parquet"))` from the 69 GB
  source DB.
- [x] Validated: `arrest_summary`/`state_summary` row counts, geo-match ~1.0,
  ordered intervals, DB size in the expected 150–300 MB range.

## C. Published to Hugging Face (public)
- [x] `civilytics/crdc-school-arrest-rates` dataset created, **public**.
- [x] `summary.duckdb` published via `Rscript scripts/publish_db.R`.
- [x] `parquet/` shards published via `Rscript scripts/publish_hf.R`.
- [x] Dataset card confirmed (citation, license, schema link, DuckDB-over-HF
  usage snippet).

## D. Deployed (Gitea Action → SWAG)
- [x] Gitea Actions enabled; `.gitea/workflows/deploy.yml` builds the image,
  sets `DATA_URL` from the public HF `summary.duckdb`, deploys via docker
  compose on the docker-socket runner.
- [x] SWAG proxy-conf (`crdc-api.subdomain.conf`) live; `crdc-api.civilytics.org`
  resolves via the existing DNS-only `*.civilytics.org` wildcard.
- [x] `curl https://crdc-api.civilytics.org/api/v1/health` → 200, confirmed
  2026-07-07.
- [x] Cloudflare edge caching (Gitea issue #1), live 2026-08-09: dedicated
  proxied `crdc-api` A record (overrides the DNS-only wildcard for just this
  host); zone SSL/TLS mode confirmed Full (strict); Cache Rule
  `crdc-api.civilytics.org/api/*` → respect origin `Cache-Control`.
  `/health` stays uncached via `no-store`.
- [x] Error responses fixed to carry `Cache-Control: no-store` instead of the
  immutable success header (Gitea issue #4) — required before the Cache Rule
  above was safe to enable, since Cloudflare honours origin directives and
  would otherwise pin 404s/500s at the edge for a year.

## E. Docs published to Gitea Pages
- [x] `docs/api/` (index.md + data-dictionary.md) rendered through the branded
  template in `docs/api/site/` and published to
  `civilytics.org/crdc-arrests` (branded, repeatable) — superseding the
  original one-off manual `pandoc` invocation. The publish step itself is
  Civilytics site-deployment tooling and is not part of this repo.
- [x] Landing page links resolve: API base, Swagger, llms.txt, HF dataset,
  data dictionary. Confirmed 2026-07-07
  (`https://pages.civilytics.org/crdc-arrests/` → 200).

## F. End-to-end verification (confirmed 2026-07-07)
- [x] `GET /api/v1/health` → `{"status":"ok"}`.
- [x] `GET /api/v1/` → success envelope with `data_release`, `docs`,
  `openapi`, `llms` links.
- [x] `GET /api/v1/llms.txt` → agent guide with R/Python/DuckDB snippets.
- [x] `https://huggingface.co/datasets/civilytics/crdc-school-arrest-rates` →
  public, 200.
- [x] `https://pages.civilytics.org/crdc-arrests/` → 200.

## Post-launch
- [x] GitHub repo is public (`https://github.com/jknowles/crdc-arrests` → 200).
- [x] Release tag `civilytics-crdc-arrests-2025.1` exists.

---

## Re-launch / re-deploy (future `data_release` bump)

If the models are re-run and a new `data_release` is cut:

1. Rebuild artifacts: `tar_make(names = c("api_db", "draws_parquet"))`.
2. Bump the `data_release` tag (`civilytics-crdc-arrests-2025.1` → `.2`,
   `.3`, ...) wherever it's defined (`R/build_api_artifacts.R`) and in
   `scripts/publish_db.R`.
3. Re-publish: `Rscript scripts/publish_db.R`, then
   `Rscript scripts/publish_hf.R export/parquet`.
4. Update `DATA_URL` in Gitea Actions variables/secrets if the HF path
   changed.
5. Push to `main` → Gitea Action redeploys `crdc-api`; re-run the step F
   checks.
6. If `docs/api/*.md` changed (new `data_release`, schema changes): re-publish
   the docs site.
