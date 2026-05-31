# CRDC Arrests — Project Roadmap

**Goal:** ship the CRDC school-arrest-rate project as a reproducible, public good:
a pipeline that builds the analytics from source, a public API/data product so
people don't have to re-run the models, and reproducible versions of the
published artifacts (white paper, social posts, etc.).

Decomposed into **three independently-buildable subsystems**. Each gets its own
spec → plan → implement cycle. We build them in dependency order and spec #2/#3
**just-in-time** (informed by what building #1 teaches us), rather than all up
front.

---

## Subsystem 1 — Draws API  ✅ spec done · ⏳ plan next

Two-tier public data product over the model results.

- **Status:** spec complete & locked — [`2026-05-30-draws-api-design.md`](./2026-05-30-draws-api-design.md). Next: writing-plans → implement on `feature/draws-api`.
- **Scope:** new pipeline targets (`district_dim`, `arrest_summary`,
  `state_summary`, `draws_parquet`) → small summary DuckDB + Parquet on HF;
  R/plumber API (`/estimates`, `/states`, `/districts`, `/models`, `/draws`) with
  OpenAPI + JSON envelope; Docker + SWAG/Cloudflare deploy via Gitea Action;
  docs (OpenAPI, llms.txt, Gitea Pages, data dictionary).
- **Key locked decisions:** see that spec's §1 + §9.

## Subsystem 2 — Pipeline reproducibility polish  📝 scoped, not specced

Make a stranger able to `tar_make()` from source and get the same results.

- **Status:** scoped only. Spec when we reach it.
- **Likely scope:** `renv` lockfile + pinned R/CmdStan versions; verify the
  automated CRDC download (`R/download_crdc_files.R` + `DOWNLOAD_GUIDE.md`) wires
  to `_targets.R` paths; documented `DEV_MODE` smoke test; compute-requirement
  docs; CI smoke run (DEV_MODE) on Gitea Actions; tidy `inst/.old`, `tmp/`,
  `.gitignore`. Confirm seeds/determinism end-to-end.
- **Note:** subsystem 1 already adds reproducible summary/Parquet targets, so it
  pays down part of this debt; #2 finishes the job (env capture + onboarding).

## Subsystem 3 — Artifact reproduction  📝 scoped, not specced

Deterministically rebuild the published outputs from pipeline data.

- **Status:** scoped only. Spec when we reach it.
- **Likely scope:** turn the Quarto docs into reproducible render targets
  (`tarchetypes::tar_render`, currently commented out in `_targets.R`):
  `results.qmd` (paper results), `applied_examples.qmd`, `social_media_posts.qmd`,
  `combined_eda.qmd`, annual/model descriptive templates. Pin figures
  (`export/figures/`), publish rendered HTML to Gitea Pages.
- **Open question to resolve at spec time:** what exactly is the "white paper"
  artifact — is `results.qmd` it, or is there a separate final report
  (the civilytics.com report) to bring into the repo?

---

## Dependency order

```
2 (pipeline) ──underpins──> 1 (API)  and  3 (artifacts)
1 (API) ──build first (highest-risk, defines data contract)──> informs 3
```

- **Build order:** 1 (now) → 2 → 3. (1 is sequenced first by decision; 2 is
  speccable in parallel once 1's plan is set, since it's mostly env/onboarding.)
- Each subsystem: own spec in `docs/superpowers/specs/`, own implementation plan,
  own review + merge.

## Status legend
✅ done · ⏳ in progress / next · 📝 scoped, not specced
