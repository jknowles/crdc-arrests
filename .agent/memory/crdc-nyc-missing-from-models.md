---
name: crdc-nyc-missing-from-models
description: NYC (CRDC LEAID 3620580) is absent from every release-2025.1 wave because the CCD join fails; arrests are -5/-6 in 15-16/17-18
metadata:
  node_type: memory
  type: project
  originSessionId: e3b91a8f-0cd2-4067-a12f-4f5da848c38e
  modified: 2026-09-29T14:32:50.867Z
---

As of release `2025.1`, New York City is missing from all three modeled waves. The cause is that `intersect_crdc_ccd()` inner-joins CRDC COMBOKEY to CCD `ncessch`. CRDC files NYC as one LEA, `3620580`, while CCD puts its schools under about 32 geographic-district LEAIDs (e.g. COMBOKEY `362058000116` → NCES `360007700116`), and CCD's own `3620580` is "NYC Chancellor's Office" with 0 schools. The fix is the Appendix K crosswalk, which exists for 2021-22 and 2023-24.

NYC arrest data by wave:
- 2015-16: all `-5` (action plan)
- 2017-18: nearly all `-6` (force certified)
- 2021-22: reported
- 2023-24: reported (mostly `-9` structural zeros)

**Why:** Jared decided (2026-09-29) for release 2026.1:
- apply the crosswalk to all four waves;
- model NYC at CCD geographic-district scale, with a draw-wise citywide aggregate under `3620580`;
- treat `-5`/`-6` as missing (dropped), never zero.

Improvements flowing backward are a stated feature of the continuously updated pipeline. Imputation is explicitly deferred to its own design session. Fully imputing NYC 15-16/17-18 is "too strong an assumption" — do not propose it as a default.

**How to apply:** Any NYC figure from 2025.1 artifacts is an absence, not a zero. In 2026.1, NYC appears only in 21-22 and 23-24. Modeling runs on euler; ingest and prep run on efron. Plan: `pm/plans/2026-09-29-crdc-2023-24-release-2026.1.md` (issues #6–#13). Related: [[crdc-check-prior-wave-docs]].
