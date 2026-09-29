---
name: pm-vs-docs
description: Project-management artifacts (plans, journal, decisions) live in pm/; docs/ is reserved for documentation a human reader uses
metadata:
  type: feedback
---

Put plans, specs-in-progress, journals and decision records under `pm/` (e.g. `pm/plans/`), never under `docs/`. `docs/` holds human-facing documentation: API docs, data dictionary, model notes, runbooks.

**Why:** Jared's running rule, stated 2026-09-29 when the 2026.1 plan was first saved to `docs/plans/`: "project management work lives in pm and docs is usually reserved for human docs." It also keeps `docs/` clean in this public repo, which an earlier commit tidied by removing agent plans from `docs/superpowers/`.

**How to apply:** When saving a plan or other PM artifact in any compass-managed repo, write it to `pm/`. Compass's retrofit survey looks for `docs/plans` as prior art, but that is not a reason to put new plans there. Related: [[crdc-nyc-missing-from-models]].
