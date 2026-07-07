# API Docs Discoverability + ShinyAppHost Portal Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the live CRDC arrest-rate API a branded, repeatable-to-publish docs site, an accurate launch record, and a discoverable link from the Civilytics public-apps landing page.

**Architecture:** Two repos. In `crdc-arrests`, a new `docs/api/site/` (pandoc template + vendored brand CSS/logo) renders `docs/api/*.md` into a self-contained, branded HTML site published to the `pages` branch by a new `scripts/publish_docs.R`; `docs/api/RUNBOOK.md` is rewritten from a stale TODO checklist into a launch record; `README.md` gains a link to the live docs site. In `ShinyAppHost`, the stdlib-only portal generator (`portal/generator/`) gains a small, JSON-config-driven "APIs & Data" section — independent of the existing `shiny-*` docker-label discovery — rendering a card for the CRDC API on `www.civilytics.org`.

**Tech Stack:** R (`Rscript`, `system2`/`system`), `pandoc` (already on `PATH`, v3.7), `git` (worktree), plain CSS (`--cv-*` custom properties, no build step), Python 3 stdlib (`json`, `dataclasses`, `html`) + `pytest` for the portal generator.

## Global Constraints

- The portal generator (`portal/generator/`) is stdlib-only — no new Python dependencies (no PyYAML, no requests). New config uses JSON, parsed with the stdlib `json` module. (Spec §4.1)
- The published docs site must stay **self-contained flat HTML** (no separate asset directory on the `pages` branch) — use `pandoc --standalone --embed-resources` so CSS and the logo SVG are base64-inlined. (Spec §2.2)
- Do not touch the Draws API's data layer, deployment mechanism, or `docker_reader.py`'s `shiny-*` label-discovery path — both are locked/working and out of scope. (Spec §7)
- `docs/api/site/civilytics-docs.css` must start from a byte-identical copy of ShinyAppHost's `portal/site/civilytics.css` (established per-repo-vendoring precedent — both repos already carry independent copies of `_brand.yml`). (Spec §2.1–2.2)
- Publish scripts (`publish_docs.R`) are manual, credentialed-if-needed CLI scripts run by a human — mirror the existing `publish_db.R`/`publish_hf.R` style (plain `message()`/`system()`, no new R package deps). No CI wiring. (Spec §2.3, §6)

---

## Part 1 — `crdc-arrests` repo

All paths in Tasks 1–4 are relative to `/home/jared/Nextcloud/Civilytics/Code/Civilytics/crdc-arrests`.

### Task 1: Branded pandoc template + CSS for the docs site

**Files:**
- Create: `docs/api/site/civilytics-docs.css`
- Create: `docs/api/site/civilytics-wordmark.svg`
- Create: `docs/api/site/template.html`
- Modify: `docs/api/index.md`

**Interfaces:**
- Produces: `docs/api/site/template.html` (a pandoc HTML template consumed by Task 2's `scripts/publish_docs.R` via `--template=`), `docs/api/site/civilytics-docs.css` and `docs/api/site/civilytics-wordmark.svg` (sibling files the template references by relative path, inlined by `--embed-resources`).

- [ ] **Step 1: Vendor the logo asset**

```bash
cp assets/logo/civilytics-wordmark.svg docs/api/site/civilytics-wordmark.svg
```

- [ ] **Step 2: Write the vendored + extended brand CSS**

Create `docs/api/site/civilytics-docs.css`:

```css
/* Civilytics public-good brand — vendored verbatim from ShinyAppHost's
   portal/site/civilytics.css (both repos carry their own copy; no cross-repo
   import mechanism exists). Do not hand-edit the tokens below without also
   updating the ShinyAppHost copy if you want them to stay in sync. */
@import url('https://fonts.googleapis.com/css2?family=Libre+Franklin:wght@400;500;600;700;800;900&family=Source+Serif+4:opsz,wght@8..60,400;8..60,500;8..60,600&family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap');

:root {
  --cv-paper:    #FAF7F2;
  --cv-paper-2:  #F2EDE4;
  --cv-paper-3:  #E6DFD1;
  --cv-rule:     #D6CEBD;
  --cv-rule-strong: #B8AE97;
  --cv-ink:      #0E1A2B;
  --cv-ink-2:    #2B3A52;
  --cv-ink-3:    #5A6A82;
  --cv-ink-4:    #8C97AB;
  --cv-navy-600: #22406A;
  --cv-navy-700: #1A2E4A;
  --cv-accent:           #C25311;
  --cv-accent-text:      #A04400;
  --cv-accent-text-dark: #E07840;
  --cv-accent-hover:     #923D00;

  --cv-font-display: 'Libre Franklin', 'Franklin Gothic', 'Inter', system-ui, sans-serif;
  --cv-font-serif:   'Source Serif 4', Georgia, serif;
  --cv-font-sans:    'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
  --cv-font-mono:    'JetBrains Mono', 'SF Mono', Menlo, Consolas, monospace;

  --space-1:.5rem; --space-2:1rem; --space-3:1.5rem; --space-4:2rem;
  --space-5:3rem; --space-6:4rem; --space-7:6rem;

  --cv-radius-sm:4px; --cv-radius-md:6px; --cv-radius-lg:12px;
}

* { box-sizing: border-box; }

html { font-family: var(--cv-font-sans); -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility; }
body { margin:0; background: var(--cv-paper); color: var(--cv-ink); font-family: var(--cv-font-sans); }

h1, h2, h3, h4 {
  font-family: var(--cv-font-display); font-weight:800; letter-spacing:-0.025em;
  line-height:1.08; color: var(--cv-ink); text-wrap: pretty; margin: 0 0 .4em;
}
h1 { font-size: clamp(2.25rem, 4.2vw, 3.75rem); font-weight:900; letter-spacing:-0.035em; line-height:1.0; }
h2 { font-size: clamp(1.75rem, 2.8vw, 2.375rem); }
h3 { font-size: 1.5rem; font-weight:700; letter-spacing:-0.022em; color: var(--cv-ink-2); }

p, li { line-height:1.7; text-wrap: pretty; }
a { color: var(--cv-navy-600); text-decoration: underline; text-decoration-thickness:1px; text-underline-offset:2px; transition: color 120ms ease; }
a:hover { color: var(--cv-navy-700); text-decoration-thickness:2px; }
code, .mono { font-family: var(--cv-font-mono); font-feature-settings:"tnum" 1,"zero" 1; }
:focus-visible { outline: 2px solid var(--cv-accent); outline-offset: 2px; }

.cv-eyebrow {
  font-family: var(--cv-font-sans); font-size:.75rem; font-weight:600;
  text-transform:uppercase; letter-spacing:.08em; color: var(--cv-accent-text);
  display:inline-flex; align-items:center; gap:.5rem; margin-bottom:.75rem;
}
.cv-eyebrow::before { content:""; display:inline-block; width:24px; height:2px; background: var(--cv-accent); }

/* === docs-site additions (crdc-arrests API docs) === */
.cv-wrap { max-width: 60rem; margin: 0 auto; padding: 0 var(--space-3); }
.cv-header {
  display: flex; align-items: center; justify-content: space-between;
  padding: var(--space-3) 0; border-bottom: 1px solid var(--cv-rule);
}
.cv-header .cv-logo { height: 28px; display: block; }
.cv-docs-nav { display: flex; gap: var(--space-3); }
.cv-docs-nav a { font-size: 0.875rem; font-weight: 600; text-decoration: none; }
.cv-docs-nav a:hover { text-decoration: underline; }

.cv-hero { padding: var(--space-4) 0 var(--space-2); }

.cv-resources {
  display: grid; grid-template-columns: repeat(2, 1fr); gap: var(--space-2);
  margin-bottom: var(--space-5);
}
.res-card {
  display: flex; flex-direction: column; gap: 0.25rem;
  background: #fff; border: 1px solid var(--cv-rule);
  border-top: 3px solid var(--cv-accent); border-radius: var(--cv-radius-lg);
  padding: var(--space-2) var(--space-3); text-decoration: none;
}
.res-card:hover { border-color: var(--cv-ink-3); }
.res-title {
  font-family: var(--cv-font-display); font-weight: 700; font-size: 1rem;
  color: var(--cv-navy-600);
}
.res-desc { font-size: 0.8125rem; color: var(--cv-ink-3); }
@media (max-width: 680px) { .cv-resources { grid-template-columns: 1fr; } }

.cv-doc { padding-bottom: var(--space-7); }
.cv-doc table {
  width: 100%; border-collapse: collapse; margin: 1.5rem 0; font-size: 0.9rem;
}
.cv-doc th, .cv-doc td {
  border-bottom: 1px solid var(--cv-rule); padding: 0.5rem 0.75rem; text-align: left;
}
.cv-doc th { font-family: var(--cv-font-display); font-weight: 700; border-top: 1px solid var(--cv-ink); }
.cv-doc code {
  background: var(--cv-paper-2); padding: 0.1em 0.35em; border-radius: var(--cv-radius-sm);
  font-size: 0.875em;
}
.cv-doc pre { background: var(--cv-paper-2); padding: var(--space-2); border-radius: var(--cv-radius-md); overflow-x: auto; }
.cv-doc pre code { background: none; padding: 0; }
.cv-doc ul, .cv-doc ol { padding-left: 1.4em; }
.cv-doc li { margin: 0.35em 0; }

.cv-footer {
  border-top: 1px solid var(--cv-rule); padding: var(--space-4) 0;
  color: var(--cv-ink-3); font-size: 0.9rem; display: flex; flex-wrap: wrap;
  gap: var(--space-2); justify-content: space-between; align-items: center;
}
```

- [ ] **Step 3: Write the pandoc template**

Create `docs/api/site/template.html`:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$title$</title>
  <meta name="description" content="Bayesian small-area estimates of school-based arrest rates from the US DoE Civil Rights Data Collection — public API and bulk data." />
  <link rel="stylesheet" href="civilytics-docs.css" />
</head>
<body>
<div class="cv-wrap">
  <header class="cv-header">
    <a href="https://civilytics.com" aria-label="Civilytics">
      <img src="civilytics-wordmark.svg" alt="Civilytics" class="cv-logo" />
    </a>
    <nav class="cv-docs-nav">
      <a href="index.html">Overview</a>
      <a href="data-dictionary.html">Data dictionary</a>
    </nav>
  </header>

  <section class="cv-hero">
    <span class="cv-eyebrow">CRDC School Arrest Rate API</span>
  </section>

  <section class="cv-resources">
    <a class="res-card" href="https://crdc-api.civilytics.org/api/v1/">
      <span class="res-title">Live API</span>
      <span class="res-desc">/api/v1/ — JSON envelope, districts &amp; states</span>
    </a>
    <a class="res-card" href="https://crdc-api.civilytics.org/__docs__/">
      <span class="res-title">Swagger / OpenAPI</span>
      <span class="res-desc">Interactive docs + schema</span>
    </a>
    <a class="res-card" href="https://crdc-api.civilytics.org/api/v1/llms.txt">
      <span class="res-title">Agent guide</span>
      <span class="res-desc">llms.txt — copy-paste R / Python snippets</span>
    </a>
    <a class="res-card" href="https://huggingface.co/datasets/civilytics/crdc-school-arrest-rates">
      <span class="res-title">Bulk downloads</span>
      <span class="res-desc">Hugging Face — summary.duckdb + parquet/</span>
    </a>
  </section>

  <main class="cv-doc">
$body$
  </main>

  <footer class="cv-footer">
    <span>&copy; Civilytics — social science for the public good.</span>
    <span><a href="https://civilytics.com">civilytics.com</a></span>
  </footer>
</div>
</body>
</html>
```

- [ ] **Step 4: Trim the now-redundant link list out of `docs/api/index.md`**

The resource cards in the template (Step 3) now carry the primary links, so
simplify the markdown source instead of repeating them. Replace the full
contents of `docs/api/index.md` with:

```markdown
# CRDC School Arrest Rate Estimates — API & Data

Bayesian small-area estimates of school-based arrest rates (CRDC, 2015–16 /
2017–18 / 2021–22). Query without running the models.

Use the cards above to reach the live API, interactive Swagger docs, the
agent-facing `llms.txt` guide, or the bulk Hugging Face dataset. See
**Data dictionary** (top nav) for column definitions, code lists, and sample
restrictions.

Cite: Knowles & Miller 2025. Supported by AERA/NSF (NSF-DRL #1749275).
```

- [ ] **Step 5: Render locally and verify structure**

Run:
```bash
mkdir -p /tmp/crdc-docs-check
pandoc docs/api/index.md --standalone --embed-resources \
  --template=docs/api/site/template.html \
  --metadata title="CRDC School Arrest Rate API — Overview" \
  --resource-path=docs/api/site \
  -o /tmp/crdc-docs-check/index.html
grep -c 'data:image/svg+xml;base64' /tmp/crdc-docs-check/index.html
grep -o '<title>[^<]*</title>' /tmp/crdc-docs-check/index.html
grep -c 'res-card' /tmp/crdc-docs-check/index.html
```
Expected: first grep prints `1` (logo inlined), title line shows
`<title>CRDC School Arrest Rate API — Overview</title>`, third grep prints
`6` (2 lines from the embedded CSS rules `.res-card {` / `.res-card:hover {`
plus the 4 `<a class="res-card"` anchors in the body — verified by rendering
this exact template locally). Open
`/tmp/crdc-docs-check/index.html` in a browser and visually confirm the
header/hero/cards/footer render with the Civilytics palette (navy/ember on
paper background) and no broken image icon.

- [ ] **Step 6: Commit**

```bash
git add docs/api/site/ docs/api/index.md
git commit -m "feat(docs): brand the API docs site with the Civilytics theme"
```

---

### Task 2: `scripts/publish_docs.R` — repeatable branded publish

**Files:**
- Create: `scripts/publish_docs.R`

**Interfaces:**
- Consumes: `docs/api/site/template.html`, `docs/api/site/civilytics-docs.css`, `docs/api/site/civilytics-wordmark.svg`, `docs/api/index.md`, `docs/api/data-dictionary.md` (all from Task 1).
- Produces: commits `index.html` and `data-dictionary.html` to the `pages` branch and pushes to `origin`.

- [ ] **Step 1: Write the script**

Create `scripts/publish_docs.R`:

```r
#!/usr/bin/env Rscript
# Render docs/api/*.md through the branded template (docs/api/site/) and
# publish the result to the `pages` branch, served at
# https://pages.civilytics.org/crdc-arrests/. Requires `pandoc` and `git` on
# PATH. Pushes to `origin pages` (dual-push remote: GitHub + Gitea; Gitea Pages
# watches this branch via webhook). Mirrors the manual-CLI style of
# scripts/publish_db.R / scripts/publish_hf.R — run by hand after editing
# docs/api/*.md.
# Usage: Rscript scripts/publish_docs.R

site_dir <- "docs/api/site"
pages <- list(
  list(md = "docs/api/index.md", html = "index.html",
       title = "CRDC School Arrest Rate API — Overview"),
  list(md = "docs/api/data-dictionary.md", html = "data-dictionary.html",
       title = "CRDC School Arrest Rate API — Data Dictionary")
)

stopifnot(file.exists(file.path(site_dir, "template.html")))
stopifnot(nzchar(Sys.which("pandoc")))
stopifnot(nzchar(Sys.which("git")))

run <- function(cmd) {
  message("Running: ", cmd)
  status <- system(cmd)
  if (status != 0) stop("command failed (status ", status, "): ", cmd)
}

# 1. Render each markdown source through the branded template into a temp dir.
build_dir <- tempfile("crdc-docs-build-")
dir.create(build_dir)
for (pg in pages) {
  out <- file.path(build_dir, pg$html)
  run(sprintf(
    "pandoc %s --standalone --embed-resources --template=%s --resource-path=%s --metadata title=%s -o %s",
    shQuote(pg$md), shQuote(file.path(site_dir, "template.html")),
    shQuote(site_dir), shQuote(pg$title), shQuote(out)))
}

# 2. Materialize the `pages` branch in an isolated worktree (reset to match
#    origin/pages so a stale local `pages` ref can't cause a divergent push).
worktree_dir <- tempfile("crdc-pages-worktree-")
run("git fetch origin pages")
run(sprintf("git worktree add -B pages %s origin/pages", shQuote(worktree_dir)))
on.exit(run(sprintf("git worktree remove --force %s", shQuote(worktree_dir))), add = TRUE)

for (pg in pages) {
  file.copy(file.path(build_dir, pg$html), file.path(worktree_dir, pg$html),
            overwrite = TRUE)
}

# 3. Commit + push only if something actually changed.
old_wd <- getwd()
setwd(worktree_dir)
on.exit(setwd(old_wd), add = TRUE)
run("git add -A")
unchanged <- system("git diff --cached --quiet") == 0
if (unchanged) {
  message("No changes to publish — docs site already up to date.")
} else {
  run("git commit -m \"docs: republish CRDC arrests docs site\"")
  run("git push origin pages")
  message("Published. Check: https://pages.civilytics.org/crdc-arrests/")
}
```

- [ ] **Step 2: Dry-run the render stage only (no push)**

Run the render loop by hand to confirm both pages build before trusting the
full script with a push:

```bash
mkdir -p /tmp/crdc-docs-dryrun
pandoc docs/api/index.md --standalone --embed-resources \
  --template=docs/api/site/template.html --resource-path=docs/api/site \
  --metadata title="CRDC School Arrest Rate API — Overview" \
  -o /tmp/crdc-docs-dryrun/index.html
pandoc docs/api/data-dictionary.md --standalone --embed-resources \
  --template=docs/api/site/template.html --resource-path=docs/api/site \
  --metadata title="CRDC School Arrest Rate API — Data Dictionary" \
  -o /tmp/crdc-docs-dryrun/data-dictionary.html
grep -c '<table>' /tmp/crdc-docs-dryrun/data-dictionary.html
```
Expected: both files render without error; the data dictionary grep prints
`1` (the `arrest_summary` column table — `state_summary` is described in
prose, not a second table; verified by rendering this exact source locally).
Open both in a browser and confirm
the nav (Overview / Data dictionary) links between them correctly (they're
adjacent files in the same output dir here, matching how they'll sit on the
`pages` branch).

- [ ] **Step 3: Run the full script (this pushes to a public branch)**

This step updates the **live** `pages.civilytics.org/crdc-arrests/` site.
Confirm with the user before running it outside of a dry-run context.

```bash
Rscript scripts/publish_docs.R
```
Expected: prints each `pandoc` command, then either "No changes to publish"
or a successful `git push` ending with the "Published." message.

- [ ] **Step 4: Verify live**

```bash
curl -sS -o /dev/null -w "http_code=%{http_code}\n" https://pages.civilytics.org/crdc-arrests/
curl -sS https://pages.civilytics.org/crdc-arrests/ | grep -o '<title>[^<]*</title>'
```
Expected: `http_code=200` and the new branded title.

- [ ] **Step 5: Commit the script**

```bash
git add scripts/publish_docs.R
git commit -m "feat(docs): add scripts/publish_docs.R for repeatable branded docs publish"
```

---

### Task 3: Rewrite `docs/api/RUNBOOK.md` as a launch record

**Files:**
- Modify: `docs/api/RUNBOOK.md` (full replacement)

**Interfaces:** none (documentation only).

- [ ] **Step 1: Replace the file contents**

Replace the entire contents of `docs/api/RUNBOOK.md` with:

```markdown
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
- Deferred (Gitea issue #1, only if traffic grows): a dedicated proxied
  Cloudflare A record + Cache Rule + rate-limit for edge caching. Not needed
  at current traffic.

## E. Docs published to Gitea Pages
- [x] `docs/api/` (index.md + data-dictionary.md) published to
  `pages.civilytics.org/crdc-arrests` via `Rscript scripts/publish_docs.R`
  (branded, repeatable; see `docs/api/site/`) — superseding the original
  one-off manual `pandoc` invocation.
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
6. If `docs/api/*.md` changed (new `data_release`, schema changes):
   `Rscript scripts/publish_docs.R`.
```

- [ ] **Step 2: Verify no stale unchecked launch steps remain**

```bash
grep -n '^\s*- \[ \]' docs/api/RUNBOOK.md
```
Expected: no output (the file has zero unchecked boxes — every `[ ]` from the
original launch checklist is now `[x]`, and the "Re-launch" section
deliberately uses a plain numbered list, not checkboxes, since it's a
repeatable procedure, not a one-time launch task).

- [ ] **Step 3: Commit**

```bash
git add docs/api/RUNBOOK.md
git commit -m "docs(runbook): rewrite as a launch record; API/docs are live, not pending"
```

---

### Task 4: Cross-link the live docs site from `README.md`

**Files:**
- Modify: `README.md` (the "## API & Data Product" section)

**Interfaces:** none (documentation only).

- [ ] **Step 1: Replace the section**

Find the `## API & Data Product` section in `README.md` (currently reads):

```markdown
## API & Data Product

Model results are published so you don't have to re-run the pipeline:

- **API:** `https://crdc-api.civilytics.org/api/v1/` — district & state estimates
  (point + 50/80/95% credible intervals). See `api/llms.txt` and the OpenAPI spec
  at `/api/v1/openapi.json`.
- **Bulk draws:** partitioned Parquet on Hugging Face
  (`civilytics/crdc-school-arrest-rates`), queryable shard-by-shard with DuckDB.
- **Build it yourself:** the `api_db` and `draws_parquet` targets produce the
  summary DuckDB and Parquet from `tar_make()`. See `docs/api/data-dictionary.md`.
```

Replace it with:

```markdown
## API & Data Product

Model results are published so you don't have to re-run the pipeline:

- **API:** `https://crdc-api.civilytics.org/api/v1/` — district & state estimates
  (point + 50/80/95% credible intervals). See `api/llms.txt` and the OpenAPI spec
  at `/api/v1/openapi.json`.
- **Docs:** https://pages.civilytics.org/crdc-arrests/ — overview + data
  dictionary (or read them in-repo: [docs/api/index.md](docs/api/index.md),
  [docs/api/data-dictionary.md](docs/api/data-dictionary.md)).
- **Bulk draws:** partitioned Parquet on Hugging Face
  (`civilytics/crdc-school-arrest-rates`), queryable shard-by-shard with DuckDB.
- **Build it yourself:** the `api_db` and `draws_parquet` targets produce the
  summary DuckDB and Parquet from `tar_make()`.
```

- [ ] **Step 2: Verify**

```bash
grep -n "pages.civilytics.org/crdc-arrests" README.md
```
Expected: one match, inside the "API & Data Product" section.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): link the live branded docs site"
```

---

## Part 2 — `ShinyAppHost` repo

All paths in Tasks 5–11 are relative to
`/home/jared/Nextcloud/Civilytics/Code/Civilytics/ShinyAppHost`. Tests run
with `cd portal/generator && python3 -m pytest -q` (confirmed working;
12 tests currently pass before this plan's changes).

### Task 5: `render.py` — `ApiEntry` + `render_api_panels` + `render_page` apis param

**Files:**
- Modify: `portal/generator/render.py` (full file below)
- Modify: `portal/generator/tests/test_render.py` (append tests)

**Interfaces:**
- Produces: `ApiEntry(title: str, description: str, links: list[dict])` dataclass; `render_api_panels(apis: list[ApiEntry]) -> str`; `API_MARKER = "<!-- APIS -->"`; `render_page(template, apps, screenshots, apis=None)` — `apis` is optional and defaults to `None` (treated as empty list) so Task 5 alone doesn't break any existing caller.
- Consumes (Task 7): `render_page`'s new `apis` parameter, `API_MARKER`.

- [ ] **Step 1: Write the failing tests**

Append to `portal/generator/tests/test_render.py`:

```python
from render import ApiEntry, render_api_panels, render_page, MARKER, API_MARKER

def test_render_api_panels_empty_list_returns_empty_string():
    assert render_api_panels([]) == ""

def test_render_api_panels_escapes_and_links():
    apis = [ApiEntry(title="CRDC <API>", description="d & d",
                      links=[{"label": "Live API", "url": "https://crdc-api.civilytics.org"}])]
    html = render_api_panels(apis)
    assert "CRDC &lt;API&gt;" in html
    assert "d &amp; d" in html
    assert 'href="https://crdc-api.civilytics.org"' in html
    assert ">Live API<" in html

def test_render_page_replaces_apis_marker():
    template = f"<main>{MARKER}{API_MARKER}</main>"
    apis = [ApiEntry(title="X", description="d", links=[{"label": "L", "url": "https://x"}])]
    html = render_page(template, [], set(), apis)
    assert API_MARKER not in html
    assert "X" in html

def test_render_page_apis_marker_untouched_when_absent_and_no_apis():
    template = "<main>no marker here</main>"
    html = render_page(template, [], set())
    assert html == template
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd portal/generator && python3 -m pytest -q`
Expected: `FAIL` — `ImportError: cannot import name 'ApiEntry' from 'render'`
(or similar) for the 4 new tests; the 12 pre-existing tests still pass.

- [ ] **Step 3: Implement**

Replace the full contents of `portal/generator/render.py` with:

```python
"""Render the portal app directory (category panels) from container labels,
plus a small static "APIs & Data" section from a committed JSON config.
Pure functions, stdlib only — unit-tested offline."""
from dataclasses import dataclass
import html as _html

CATEGORY_ORDER = [
    "Criminal Justice & Policing",
    "Prison Gerrymandering",
    "Education",
    "Methods & Tools",
]
CATCH_ALL = "More tools"

@dataclass(frozen=True)
class App:
    slug: str
    title: str
    description: str
    category: str

@dataclass(frozen=True)
class ApiEntry:
    title: str
    description: str
    links: list  # [{"label": str, "url": str}, ...], order preserved

def group_apps(apps):
    """Return [(category, [apps])] in CATEGORY_ORDER, empties dropped,
    unknown categories collected into a trailing CATCH_ALL panel,
    apps sorted alphabetically by title within each panel."""
    known = {c: [] for c in CATEGORY_ORDER}
    extra = []
    for a in apps:
        (known[a.category] if a.category in known else extra).append(a)
    groups = [(c, known[c]) for c in CATEGORY_ORDER if known[c]]
    if extra:
        groups.append((CATCH_ALL, extra))
    return [(c, sorted(items, key=lambda x: x.title.lower())) for c, items in groups]

MARKER = "<!-- APPS -->"
API_MARKER = "<!-- APIS -->"

def _row(app, has_shot):
    slug = _html.escape(app.slug)
    title = _html.escape(app.title or app.slug)
    desc = _html.escape(app.description or "")
    url = f"https://{slug}.civilytics.org"
    if has_shot:
        shot = (f'<img class="shot" src="assets/screenshots/{slug}.png" '
                f'alt="" loading="lazy">')
    else:
        shot = '<span class="shot shot--missing" aria-hidden="true">no screenshot</span>'
    return (f'<a class="p-row" href="{url}">{shot}'
            f'<span class="meta"><span class="p-title">{title}</span>'
            f'<span class="p-desc">{desc}</span></span></a>')

def _panel(category, apps, screenshots):
    rows = "".join(_row(a, a.slug in screenshots) for a in apps)
    return (f'<div class="p-panel"><div class="p-head">'
            f'<h2>{_html.escape(category)}</h2>'
            f'<span class="p-count">{len(apps)}</span></div>{rows}</div>')

def render_panels(apps, screenshots):
    groups = group_apps(apps)
    body = "".join(_panel(c, items, screenshots) for c, items in groups)
    return f'<div class="p-panels">{body}</div>'

def _api_link(link):
    label = _html.escape(link["label"])
    url = _html.escape(link["url"])
    return f'<a class="api-link" href="{url}">{label}</a>'

def _api_row(api):
    title = _html.escape(api.title)
    desc = _html.escape(api.description or "")
    links = "".join(_api_link(l) for l in api.links)
    return (f'<div class="api-row"><div class="api-meta">'
            f'<span class="api-title">{title}</span>'
            f'<span class="api-desc">{desc}</span></div>'
            f'<div class="api-links">{links}</div></div>')

def render_api_panels(apis):
    """apis: list[ApiEntry]. Returns '' when empty so the marker collapses to
    nothing rather than an empty panel shell."""
    if not apis:
        return ""
    rows = "".join(_api_row(a) for a in apis)
    return f'<div class="p-panel api-panel">{rows}</div>'

def render_page(template, apps, screenshots, apis=None):
    html = template.replace(MARKER, render_panels(apps, screenshots))
    return html.replace(API_MARKER, render_api_panels(apis or []))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd portal/generator && python3 -m pytest -q`
Expected: `16 passed`.

- [ ] **Step 5: Commit**

```bash
git add portal/generator/render.py portal/generator/tests/test_render.py
git commit -m "feat(portal): add ApiEntry + render_api_panels; render_page gains optional apis param"
```

---

### Task 6: `apis_reader.py` — load the static APIs config

**Files:**
- Create: `portal/generator/apis_reader.py`
- Create: `portal/generator/tests/test_apis_reader.py`

**Interfaces:**
- Consumes: `ApiEntry` from `render.py` (Task 5).
- Produces: `load_apis(path: str) -> list[ApiEntry]` — returns `[]` if `path` doesn't exist (so `build.py`, Task 7, doesn't need its own existence check).

- [ ] **Step 1: Write the failing tests**

Create `portal/generator/tests/test_apis_reader.py`:

```python
import json
from apis_reader import load_apis

def test_load_apis_parses_json(tmp_path):
    p = tmp_path / "apis.json"
    p.write_text(json.dumps([
        {"title": "CRDC API", "description": "d",
         "links": [{"label": "Live API", "url": "https://x"}]}
    ]))
    apis = load_apis(str(p))
    assert len(apis) == 1
    assert apis[0].title == "CRDC API"
    assert apis[0].description == "d"
    assert apis[0].links[0]["label"] == "Live API"

def test_load_apis_missing_file_returns_empty(tmp_path):
    assert load_apis(str(tmp_path / "nope.json")) == []

def test_load_apis_defaults_missing_description():
    import tempfile, os
    fd, path = tempfile.mkstemp(suffix=".json")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump([{"title": "X", "links": []}], f)
        apis = load_apis(path)
        assert apis[0].description == ""
    finally:
        os.remove(path)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd portal/generator && python3 -m pytest -q`
Expected: `FAIL` — `ModuleNotFoundError: No module named 'apis_reader'` for
the 3 new tests; the 16 from Task 5 still pass.

- [ ] **Step 3: Implement**

Create `portal/generator/apis_reader.py`:

```python
"""Read the static "APIs & Data" directory config (portal/site/apis.json).
Stdlib only (json) — mirrors docker_reader.py's App-shaped output, but
sourced from a committed file rather than container discovery, since these
are external resources (an API + a data download), not shiny-* containers."""
import json
from render import ApiEntry

def load_apis(path):
    try:
        with open(path, encoding="utf-8") as f:
            raw = json.load(f)
    except FileNotFoundError:
        return []
    return [ApiEntry(title=e["title"], description=e.get("description", ""),
                      links=e.get("links", [])) for e in raw]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd portal/generator && python3 -m pytest -q`
Expected: `19 passed`.

- [ ] **Step 5: Commit**

```bash
git add portal/generator/apis_reader.py portal/generator/tests/test_apis_reader.py
git commit -m "feat(portal): add apis_reader.load_apis for the APIs & Data config"
```

---

### Task 7: Wire `apis_reader` into `build.py`

**Files:**
- Modify: `portal/generator/build.py` (full file below)
- Modify: `portal/generator/tests/test_build.py` (append test)

**Interfaces:**
- Consumes: `load_apis` (Task 6), `render_page(..., apis=...)` (Task 5).
- Produces: `build.APIS_PATH` (module-level, monkeypatchable in tests, mirroring the existing `build.SITE_DIR`/`build.TEMPLATE` pattern).

- [ ] **Step 1: Write the failing test**

Append to `portal/generator/tests/test_build.py`:

```python
def test_generate_once_includes_apis_section(tmp_path, monkeypatch):
    site = tmp_path / "site"; site.mkdir()
    (site / "index.template.html").write_text("<main><!-- APPS --><!-- APIS --></main>")
    apis_path = site / "apis.json"
    apis_path.write_text(
        '[{"title": "CRDC API", "description": "d", '
        '"links": [{"label": "Live API", "url": "https://x"}]}]'
    )
    monkeypatch.setattr(build, "fetch_apps", lambda *a, **k: [])
    monkeypatch.setattr(build, "SITE_DIR", str(site))
    monkeypatch.setattr(build, "TEMPLATE", str(site / "index.template.html"))
    monkeypatch.setattr(build, "APIS_PATH", str(apis_path))
    build.generate_once()
    out = (site / "index.html").read_text()
    assert "CRDC API" in out
    assert "<!-- APIS -->" not in out
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd portal/generator && python3 -m pytest -q`
Expected: `FAIL` — `AttributeError: module 'build' has no attribute 'APIS_PATH'`
(or the assertion fails because the apis section isn't rendered); the other
19 tests still pass.

- [ ] **Step 3: Implement**

Replace the full contents of `portal/generator/build.py` with:

```python
"""Portal directory generator: read labels -> render -> write index.html.
Runs once at container start and then every INTERVAL_S as a self-heal timer."""
import os, time
from docker_reader import fetch_apps
from apis_reader import load_apis
from render import render_page

DOCKER_PROXY = os.environ.get("DOCKER_PROXY", "http://sablier-socket-proxy:2375")
SITE_DIR = os.environ.get("SITE_DIR", "/usr/share/nginx/html")
TEMPLATE = os.environ.get("TEMPLATE", "/usr/share/nginx/html/index.template.html")
APIS_PATH = os.environ.get("APIS_PATH", os.path.join(SITE_DIR, "apis.json"))
INTERVAL_S = int(os.environ.get("INTERVAL_S", "300"))

def screenshots_present(site_dir):
    d = os.path.join(site_dir, "assets", "screenshots")
    if not os.path.isdir(d):
        return set()
    return {f[:-4] for f in os.listdir(d) if f.endswith(".png")}

def generate_once():
    with open(TEMPLATE, encoding="utf-8") as f:
        template = f.read()
    apps = fetch_apps(DOCKER_PROXY)
    apis = load_apis(APIS_PATH)
    html = render_page(template, apps, screenshots_present(SITE_DIR), apis)
    tmp = os.path.join(SITE_DIR, "index.html.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(html)
    os.replace(tmp, os.path.join(SITE_DIR, "index.html"))

def main():
    while True:
        try:
            generate_once()
        except Exception as e:
            print(f"portal-gen error: {e!r}", flush=True)
        time.sleep(INTERVAL_S)

if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd portal/generator && python3 -m pytest -q`
Expected: `20 passed`.

- [ ] **Step 5: Commit**

```bash
git add portal/generator/build.py portal/generator/tests/test_build.py
git commit -m "feat(portal): wire apis_reader into build.generate_once"
```

---

### Task 8: `portal/site/apis.json` — the CRDC API entry

**Files:**
- Create: `portal/site/apis.json`

**Interfaces:**
- Consumes: nothing (static data file).
- Produces: the JSON list `load_apis` (Task 6) parses at container start/self-heal tick.

- [ ] **Step 1: Create the file**

```json
[
  {
    "title": "CRDC School Arrest Rate API",
    "description": "Bayesian small-area estimates of school-based arrest rates (CRDC 2015-16 / 2017-18 / 2021-22).",
    "links": [
      {"label": "Live API", "url": "https://crdc-api.civilytics.org/api/v1/"},
      {"label": "Docs", "url": "https://pages.civilytics.org/crdc-arrests/"},
      {"label": "Data (Hugging Face)", "url": "https://huggingface.co/datasets/civilytics/crdc-school-arrest-rates"}
    ]
  }
]
```

- [ ] **Step 2: Verify it parses and round-trips through `load_apis`**

```bash
cd portal/generator
python3 -c "
from apis_reader import load_apis
apis = load_apis('../site/apis.json')
assert len(apis) == 1
assert apis[0].title == 'CRDC School Arrest Rate API'
assert len(apis[0].links) == 3
print('OK:', apis)
"
```
Expected: prints `OK: [ApiEntry(title='CRDC School Arrest Rate API', ...)]`
with no traceback.

- [ ] **Step 3: Commit**

```bash
git add portal/site/apis.json
git commit -m "feat(portal): add the CRDC School Arrest Rate API to apis.json"
```

---

### Task 9: `index.template.html` — "APIs & Data" section + CSS

**Files:**
- Modify: `portal/site/index.template.html`

**Interfaces:**
- Consumes: `API_MARKER = "<!-- APIS -->"` (Task 5) — must appear exactly once in the template for `render_page` to substitute it.

- [ ] **Step 1: Add the new section markup**

In `portal/site/index.template.html`, find the existing directory section:

```html
                <section class="cv-directory">
                    <span class="cv-section-label">Live apps</span>
                    <p class="cv-directory-note">
                        Note that apps may have a small startup delay on first
                        use. Please be patient.
                    </p>
                    <!-- APPS -->
                </section>
```

Add a new section immediately after it (still inside `<main>`, before
`</main>`):

```html
                <section class="cv-directory">
                    <span class="cv-section-label">Live apps</span>
                    <p class="cv-directory-note">
                        Note that apps may have a small startup delay on first
                        use. Please be patient.
                    </p>
                    <!-- APPS -->
                </section>

                <section class="cv-directory cv-directory--apis">
                    <span class="cv-section-label">APIs &amp; Data</span>
                    <p class="cv-directory-note">
                        Programmatic access to the same public datasets — for
                        developers, researchers, and AI agents.
                    </p>
                    <!-- APIS -->
                </section>
```

- [ ] **Step 2: Add the CSS for the new section**

In the same file's `<style>` block, find the closing rule for `.p-desc`:

```css
            .p-desc {
                margin: 0.15rem 0 0;
                font-size: 0.8125rem;
                line-height: 1.4;
                color: var(--cv-ink-3);
            }
```

Add this new block immediately after it (still before the `@media` query):

```css
            .p-desc {
                margin: 0.15rem 0 0;
                font-size: 0.8125rem;
                line-height: 1.4;
                color: var(--cv-ink-3);
            }
            .api-panel {
                background: #fff;
                border: 1px solid var(--cv-rule);
                border-top: 3px solid var(--cv-accent);
                border-radius: var(--cv-radius-lg);
                padding: var(--space-3);
            }
            .api-row {
                display: flex;
                flex-wrap: wrap;
                align-items: center;
                justify-content: space-between;
                gap: var(--space-2);
                padding: var(--space-2) 0;
                border-bottom: 1px solid var(--cv-paper-2);
            }
            .api-row:last-child {
                border-bottom: none;
            }
            .api-meta {
                display: flex;
                flex-direction: column;
                max-width: 42ch;
            }
            .api-title {
                font-family: var(--cv-font-display);
                font-weight: 600;
                font-size: 1rem;
                color: var(--cv-navy-600);
            }
            .api-desc {
                margin: 0.15rem 0 0;
                font-size: 0.8125rem;
                color: var(--cv-ink-3);
            }
            .api-links {
                display: flex;
                flex-wrap: wrap;
                gap: var(--space-1);
            }
            .api-link {
                font-size: 0.8125rem;
                font-weight: 600;
                padding: 0.35rem 0.75rem;
                border-radius: var(--cv-radius-sm);
                border: 1px solid var(--cv-rule-strong);
                text-decoration: none;
                color: var(--cv-ink);
                white-space: nowrap;
            }
            .api-link:hover {
                background: var(--cv-paper-2);
                border-color: var(--cv-ink-3);
            }
```

- [ ] **Step 3: Verify the marker count and render locally**

```bash
grep -c '<!-- APIS -->' portal/site/index.template.html
```
Expected: `1`.

Then render it with the real `apis.json` and an empty app list to eyeball the
output:

```bash
cd portal/generator
python3 -c "
from render import render_page
from apis_reader import load_apis
tmpl = open('../site/index.template.html', encoding='utf-8').read()
apis = load_apis('../site/apis.json')
html = render_page(tmpl, [], set(), apis)
open('/tmp/portal-preview.html', 'w', encoding='utf-8').write(html)
assert '<!-- APIS -->' not in html
assert 'CRDC School Arrest Rate API' in html
print('OK — wrote /tmp/portal-preview.html')
"
```
Open `/tmp/portal-preview.html` in a browser and confirm the "APIs & Data"
section renders below "Live apps" with the CRDC card showing its three link
chips (Live API / Docs / Data (Hugging Face)), styled consistently with the
existing panels (navy title, ember top border, paper background).

- [ ] **Step 4: Commit**

```bash
git add portal/site/index.template.html
git commit -m "feat(portal): add APIs & Data section to the landing page template"
```

---

### Task 10: Dockerfile — ship `apis_reader.py` in the image

**Files:**
- Modify: `portal/Dockerfile:9`

**Interfaces:** none (build config only).

- [ ] **Step 1: Add the new module to the COPY line**

In `portal/Dockerfile`, change:

```dockerfile
COPY generator/render.py generator/docker_reader.py generator/build.py ./
```

to:

```dockerfile
COPY generator/render.py generator/docker_reader.py generator/build.py generator/apis_reader.py ./
```

- [ ] **Step 2: Build the image locally and verify it starts**

```bash
docker build -t civilytics-portal:apis-test portal/
docker run --rm -d --name portal-apis-test \
  -e DOCKER_PROXY=http://127.0.0.1:1 \
  civilytics-portal:apis-test
sleep 2
docker logs portal-apis-test
docker exec portal-apis-test cat /usr/share/nginx/html/index.html | grep -c "CRDC School Arrest Rate API"
docker stop portal-apis-test
```
Expected: the container starts (the `DOCKER_PROXY` pointing nowhere will
make `fetch_apps` fail/log an error inside the self-heal loop, but the
*initial* `generate_once()` in `entrypoint.sh` should still complete because
`apis.json` is read independently of the docker proxy — if the initial
render fails because `fetch_apps` raises before `apis` is computed, that's
pre-existing behavior unrelated to this change, not a regression to chase
here). The `grep -c` prints `1` if the container reached a successful render
with the APIs section baked in; if the container's initial render needs a
live docker proxy to succeed at all, skip the container run and instead
confirm via the Task 9 Step 3 local render preview, which already proves the
template + apis.json + code path work end-to-end without Docker.

- [ ] **Step 3: Commit**

```bash
git add portal/Dockerfile
git commit -m "chore(portal): ship apis_reader.py in the portal image"
```

---

### Task 11: Push and verify the live portal (requires explicit confirmation)

**Files:** none (deploy step).

**Interfaces:** none.

- [ ] **Step 1: Push to trigger the existing deploy workflow**

This pushes to `main` on the `ShinyAppHost` Gitea repo, which
`.gitea/workflows/portal-deploy.yml` watches to rebuild and redeploy the
**live** `civilytics-portal` container serving `www.civilytics.org`. Confirm
with the user before running this — it changes a publicly visible page.

```bash
git push origin main
```

- [ ] **Step 2: Watch the Actions run and verify live**

Use the `gitea-tea-operations` skill to check the triggered Actions run for
`Civilytics/ShinyAppHost` (or the Gitea web UI). Once green:

```bash
curl -sS https://www.civilytics.org/ | grep -c "CRDC School Arrest Rate API"
```
Expected: `1`.

---

## Final cross-repo verification

- [ ] **Step 1: Confirm the full chain from the landing page to the data**

```bash
curl -sS https://www.civilytics.org/ | grep -A2 "CRDC School Arrest Rate API"
curl -sS -o /dev/null -w "%{http_code}\n" https://crdc-api.civilytics.org/api/v1/health
curl -sS -o /dev/null -w "%{http_code}\n" https://pages.civilytics.org/crdc-arrests/
```
Expected: the grep shows the card's description text; both `curl` status
checks print `200`.

- [ ] **Step 2: Update the crdc-arrests spec status**

In `crdc-arrests`, mark the spec as implemented:

```bash
cd /home/jared/Nextcloud/Civilytics/Code/Civilytics/crdc-arrests
```

Edit `docs/superpowers/specs/2026-07-07-api-docs-portal-integration-design.md`,
changing the header line `**Status:** Draft for review` to
`**Status:** Implemented 2026-07-07`, then:

```bash
git add docs/superpowers/specs/2026-07-07-api-docs-portal-integration-design.md
git commit -m "docs(spec): mark API docs + portal integration spec as implemented"
```
