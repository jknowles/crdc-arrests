# API Docs Discoverability + ShinyAppHost Portal Integration — Design Spec

**Date:** 2026-07-07
**Author:** Jared Knowles (Civilytics) w/ Claude
**Status:** Implemented 2026-07-07
**Repos touched:** `crdc-arrests` (this repo) and `ShinyAppHost`
(`/home/jared/Nextcloud/Civilytics/Code/Civilytics/ShinyAppHost`)

---

## 1. Purpose & Context

The Draws API (`docs/superpowers/specs/2026-05-30-draws-api-design.md`) shipped
and is live: `https://crdc-api.civilytics.org/api/v1/` returns a healthy
envelope, `https://pages.civilytics.org/crdc-arrests/` serves the docs site,
and the Hugging Face dataset (`civilytics/crdc-school-arrest-rates`) is public.
Verified live 2026-07-07.

Two problems remain:

1. **The API is hard to discover and its own docs undersell that it shipped.**
   `docs/api/RUNBOOK.md` still reads as an unchecked launch TODO list, when in
   fact every step is done and verified. The published docs site
   (`docs/api/index.md` / `data-dictionary.md` → pandoc → `pages` branch) is
   bare unstyled HTML, built by a one-off manual `pandoc` invocation with no
   script and no repeatable process — edit the markdown today and the live
   site silently goes stale.
2. **The API has no presence on `www.civilytics.org`.** That landing page
   (built by the `ShinyAppHost` repo's metadata-driven portal, "Project C")
   only discovers Docker containers named `shiny-*` carrying
   `civilytics.app.*` labels. `crdc-api` is a `plumber` container named
   `crdc-api` on the `swag` network — architecturally a different kind of
   thing (an API + downloadable data product, not a running app with a
   screenshot) — so it will never appear via that discovery path.

This spec covers both, plus the small cross-linking cleanup that falls out of
fixing them. It does **not** revisit the Draws API's data layer, deployment
mechanism, or the two-tier (live/bulk) architecture — those are locked in the
2026-05-30 spec and unchanged here.

### Decisions locked during brainstorming

| # | Decision | Choice |
|---|----------|--------|
| 1 | ShinyAppHost integration | New **generalized, hand-edited config mechanism** for API/data-product entries — not a one-off static HTML block, not shoehorned into the docker-label app-discovery path |
| 2 | Docs publish repeatability | Add a **script** (`scripts/publish_docs.R`), mirroring the existing `publish_db.R`/`publish_hf.R` pattern |
| 3 | Docs site visual design | **Match the Civilytics brand system** already shared by this repo's Quarto artifacts and the ShinyAppHost portal (same `_brand.yml` palette/fonts in both repos already) — reuse the portal's actual CSS + this repo's own vendored logo assets, not a new look |
| 4 | RUNBOOK.md | Rewrite as a **launch record** (done/verified), not a TODO checklist |

---

## 2. Component A — crdc-arrests docs site: brand + repeatable publish

### 2.1 Current state
- `docs/api/index.md`, `docs/api/data-dictionary.md`: plain markdown, decent
  content, no styling applied beyond pandoc's default inline `<style>` block.
- Published via a manual, undocumented `pandoc` invocation to the orphan
  `pages` branch (2 commits total: initial publish + a webhook-trigger no-op).
  No script, no CI.
- This repo already vendors the Civilytics brand: `_brand.yml` (byte-identical
  palette/fonts to ShinyAppHost's copy — navy/ember on paper, Libre Franklin +
  Inter), `assets/logo/*.svg`, and `theme/extras.css` (`.eyebrow` motif
  matching the portal's `.cv-eyebrow`). ShinyAppHost's `portal/site/civilytics.css`
  is plain CSS custom properties (not SCSS) — trivially reusable as-is.

### 2.2 Design
Add `docs/api/site/`:
- `template.html` — a pandoc HTML template (`$body$` placeholder) with the
  same chrome as the portal: header (wordmark linking to civilytics.com),
  eyebrow + hero, and card-style panels (reusing the portal's `.p-panel`/
  `.p-row` visual language) for the API's key resources — **Live API**,
  **Swagger/OpenAPI**, **Bulk downloads (Hugging Face)** — plus simple nav
  between the Overview and Data Dictionary pages.
- `civilytics-docs.css` — a vendored copy of the portal's `civilytics.css`
  (verbatim; both repos already carry independent copies of shared brand
  assets — there's no cross-repo import mechanism, so this follows existing
  precedent) plus doc-specific additions (code-block styling for the R/Python/
  DuckDB snippets already in `index.md`).

Render with `pandoc --standalone --embed-resources` so the published HTML
stays **fully self-contained** (CSS and the logo SVGs base64-embedded) —
preserving the current property of the `pages` branch being just flat HTML
files with no separate asset directory to keep in sync.

### 2.3 `scripts/publish_docs.R`
Mirrors `publish_db.R`/`publish_hf.R`: a manual, credentialed-if-needed R
script (plain `git`, no special auth beyond normal push access since `pages`
is a public branch on the existing dual-push `origin`):

1. Render `docs/api/index.md` → `index.html` and
   `docs/api/data-dictionary.md` → `data-dictionary.html` via
   `system2("pandoc", ...)` using `docs/api/site/template.html` +
   `docs/api/site/civilytics-docs.css`, into a local temp build dir.
2. Materialize the `pages` branch in a temp `git worktree`, copy the two
   rendered files in (overwrite), `git add -A`, commit
   (`docs: republish CRDC arrests docs site`), push to `origin pages`.
3. Print the live URL for a manual spot-check.

Run manually (`Rscript scripts/publish_docs.R`) whenever `docs/api/*.md`
changes — same operational model as the other publish scripts, documented in
the RUNBOOK.

---

## 3. Component B — `docs/api/RUNBOOK.md` cleanup

Rewrite from an unchecked TODO checklist to a **launch record**:
- Steps A–F: marked done, with the verification evidence already gathered
  (health check 200, pages site 200, HF dataset public) and a "confirmed live
  2026-07-07" note.
- Replace the old manual-pandoc description in step E with
  `Rscript scripts/publish_docs.R` (Component A).
- Keep a short trailing section for **future re-launch steps** (e.g. bumping
  `data_release`, re-publishing after a model re-run) — the only part of the
  old runbook that's still forward-looking.

---

## 4. Component C — ShinyAppHost: "APIs & Data" portal section

### 4.1 Constraint
The portal generator (`portal/generator/`) is deliberately **stdlib-only,
Python, unit-tested offline** (`docker_reader.py`, `render.py`, `build.py`;
container is `nginx:alpine` + bare `python3`, no pip packages). It must stay
that way. That rules out YAML for any new config the generator itself parses
(no PyYAML in the image) — the existing `app.yml` is only ever read by the
*deploy workflow* (shell/`yq` at container-label-stamping time), never by this
generator. The new config uses **JSON** (stdlib `json`, zero new deps).

### 4.2 Design
- New file `portal/site/apis.json` — a small, hand-edited, committed list:
  ```json
  [
    {
      "title": "CRDC School Arrest Rate API",
      "description": "Bayesian small-area estimates of school-based arrest rates (CRDC 2015-16 / 2017-18 / 2021-22).",
      "links": [
        {"label": "Live API", "url": "https://crdc-api.civilytics.org/api/v1/"},
        {"label": "Docs",     "url": "https://pages.civilytics.org/crdc-arrests/"},
        {"label": "Data (Hugging Face)", "url": "https://huggingface.co/datasets/civilytics/crdc-school-arrest-rates"}
      ]
    }
  ]
  ```
  Copied into the image unchanged (already covered by the Dockerfile's
  `COPY site/ /usr/share/nginx/html/`).
- New `portal/generator/apis_reader.py::load_apis(path)` — stdlib `json.load`,
  returns a list of a small `ApiEntry` dataclass (mirrors the `App` dataclass
  in `render.py`).
- Extend `render.py`: add `ApiEntry`, `render_api_panels(apis)` producing a
  panel styled like the existing `.p-panel` but with **multi-link rows**
  (title + description + a row of link chips, since an API entry has 2–3
  named links and no single URL/screenshot) — a small new CSS block
  (`.api-row`, `.api-links`) added alongside the existing `<style>` block in
  `index.template.html`. Extend `render_page` to replace a second marker.
- New marker `<!-- APIS -->` in `index.template.html`, in a new
  `<section class="cv-directory">` below "Live apps", eyebrow-labeled
  **"APIs & Data"**, with the same directory-note treatment as the apps
  section.
- Extend `build.py::generate_once()` to also read `apis.json` from `SITE_DIR`
  and pass it to `render_page`.
- Unit tests mirroring `portal/generator/tests/test_render.py` (new
  `test_apis_reader.py`, extended `test_render.py` / `test_build.py` cases):
  JSON parse, empty-list → no section rendered, HTML-escaping, link rendering.

This is additive only — it does not touch `docker_reader.py` or the
`shiny-*` label-discovery path at all, and needs no docker-socket-proxy
access (the config is static, baked into the image, not container-discovered).

### 4.3 Placement question (defer to implementation)
Whether "APIs & Data" renders above or below "Live apps" is a minor visual
call left to implementation/preview — default plan is **below**, since "Live
apps" is the flagship content.

---

## 5. Component D — cross-linking cleanup

- `README.md`'s "API & Data Product" section currently links the
  repo-relative `docs/api/data-dictionary.md`. Update it to link the live,
  now-branded published site (`https://pages.civilytics.org/crdc-arrests/`)
  as the primary human-facing entry point, keeping the repo-relative link as
  a secondary "or read it in-repo" pointer.
- No changes needed to `llms.txt` (already correct and agent-facing).

---

## 6. Testing

- **Component A:** no new automated tests (a publish script, run manually,
  like its siblings); verify by rendering locally and diffing against the
  current live site's structure, then a manual post-push `curl` check
  (mirrors how `publish_db.R`/`publish_hf.R` are verified today).
- **Component C:** `api_reader`/`render` unit tests run via the existing
  `pytest` setup in `portal/generator/tests/` (no CI currently gates this
  directory beyond local runs — matches current practice for that generator).

---

## 7. Explicitly Out of Scope

- Any change to the Draws API's data layer, deployment mechanism, or
  two-tier architecture (2026-05-30 spec, unchanged and working).
- Reworking `docker_reader.py`/the `shiny-*` label-discovery path.
- CI automation for the docs-site publish (stays a manual script, matching
  `publish_db.R`/`publish_hf.R`).
- Landing the orphaned `fix/api-400-error-handling` branch (unrelated,
  flagged separately, not part of this spec).
- A general-purpose "add any API" onboarding guide for ShinyAppHost (only one
  entry exists today; `apis.json`'s shape should accommodate more later
  without a redesign, but writing that guide is deferred until there's a
  second entry).

## 8. Resolved Items (locked)

No open items remain.
