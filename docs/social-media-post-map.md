# CRDC Social Media Post Map

**Purpose.** Single source of truth linking each social media post (gold-standard
prose) to the figures/tables that illustrate it and to the exact
`social_media_posts.qmd` chunk that reproduces each figure. Posts 1–6 are
**already posted** — their prose is canonical and the QMD must reproduce their
figures and numbers. Posts 7–10 are **drafted** and still need finalizing.

**Sources**
- Prose: `inst/Posts 1-3.docx`, `inst/Posts 4-6.docx`, `inst/Posts 7-x.docx`,
  `inst/Posts TO EDIT.docx`, `inst/Other ideas.docx`
- Figures/code: `social_media_posts.qmd` → PNGs in `export/figures/socialmedia-*.png`
- Data: local staged parquets under `export/stages/…`; model draws under
  `export/parquet/**` (set `CRDC_ARTIFACTS=export` to resolve everything locally —
  no network needed).

**Number verification.** All descriptive figures (Posts 1–8) were recomputed from
the same local parquets the QMD reads (`/tmp/verify_posts.R`, 2026-06-22). Status
column: ✓ matches gold-standard prose, ⚠ drift to reconcile. Model-draw figures
(Posts 7 & 9) confirmed reproducible offline (local draws tree present, 1,876
partitions) but their posterior summaries were not numerically re-verified here.

Legend: **chunk** = `#| label:` in the qmd (or `(unlabeled)` + line); **PNG** =
file under `export/figures/`.

---

## Series intro (text only)
**Source:** Posts 1-3.docx (lead paragraph) · **Figure:** none

Grant acknowledgment (AERA / NSF award NSF-DRL #1749275) + roadmap: descriptive
posts (state, race, district) → "getting the most" modeling → reflections on loss
if national collection stops. The required AERA/NSF disclaimer should head every
post.

---

## Post 1 — How states stack up
**Source:** Posts 1-3.docx · **Title:** "Arrests in schools in 2021-22: How states stack up on student arrests" · **Status: posted**

| docx | chunk | PNG | status |
|------|-------|-----|--------|
| image1 (count map) | `arrest_chloropleth` | `socialmedia-arrest_chloropleth-1.png` | ✓ |
| image2 (rate map) | `arrest_rate_chloropleth` | `socialmedia-arrest_rate_chloropleth-1.png` | ✓ |
| image3 (NNH map) | `state_arrest_nnh_map` | `socialmedia-state_arrest_nnh_map-1.png` | ✓ |

Verified: 34,846 national arrests ✓ · rate 0.72/1,000 ✓ · Kansas NNH 1-in-194 ✓ ·
South Dakota NNH 1-in-348 ✓.
- ✅ **RESOLVED — National NNH.** Posted text said "1 out of every 1,428"; that value
  is not reproducible from any CRDC stage (it implies ~49.76M enrollment ≈ the external
  NCES/CCD national K-12 total, and is the reciprocal of a 0.70/1,000 rate, inconsistent
  with the post's own 0.72). **Decision: use the CRDC-consistent value, 1 in ~1,395**
  (= 48,596,489 reported enrollment ÷ 34,846 arrests, the exact reciprocal of the
  0.72/1,000 rate from the same `full_crdc` data). Add a footnote noting the correction
  from the originally posted 1,428 and stating the denominator is **CRDC-reported
  enrollment**, not external national enrollment.

---

## Post 2 — Arrests are declining, but everywhere?
**Source:** Posts 1-3.docx · **Title:** "School-based arrests are declining but is this true everywhere?" · **Status: posted**

| docx | chunk | PNG | status |
|------|-------|-----|--------|
| image4 (national count trend) | `national_trend` | `socialmedia-national_trend-1.png` | ✓ |
| image5 (national rate trend) | `national_arrest_rate_trend` | `socialmedia-national_arrest_rate_trend-1.png` | ✓ |
| image6 (KS vs CA) | `select_state_arrest_trend` | `socialmedia-select_state_arrest_trend-1.png` | ✓ |

Supporting (no figure): `kansas_lea` chunk preps the Derby-district drill-down
(87% of KS arrests; ~6,500 students) cited in prose.

Verified: 15-16 = 62,020 (">62,000") ✓ · 21-22 = 34,846 ("<35,000") ✓ ·
KS 2,413 / 565 / 521 ✓ · CA 17-18 = 2,151 ✓, 15-16 = 3,424 ✓ (footnote values).
- ✅ **RESOLVED — Decline magnitude.** Posted "~40%"; actual 15-16→21-22 decline is
  **43.8%** from `full_crdc` (43.6% from `model_data`; 52,300 in 17-18 is the
  intermediate). **Decision: change wording to "~44%" / "over 40%".** Endpoint counts
  already match exactly, so this is wording only.

---

## Post 3 — Districts with the most arrests
**Source:** Posts 1-3.docx · **Title:** "Some districts arrest hundreds of students and have arrest rates 10x the national average" · **Status: posted**

| docx | chunk | PNG | status |
|------|-------|-----|--------|
| image7 (top-20 by arrests, 3 waves) | `national_lea_table` | `socialmedia-national_lea_table.png` | ✓ |

Verified: 11.6% of districts reported ≥1 arrest ✓ (2,060 districts). Prose's
named-district call-outs (DeKalb, Derby, Pasadena TX, Pinellas, Anne Arundel,
NYC, Miami-Dade, Waterbury, Bibb, Chambersburg) come from this table's rows.

---

## Post 4 — Districts with the highest arrest *rates*
**Source:** Posts 4-6.docx · **Title:** "Districts with the highest arrest rates are small, serve special education students and Native Americans" · **Status: posted**

| docx | chunk | PNG | status |
|------|-------|-----|--------|
| image1 (top-20 by rate) | `national_lea_table_higharrestrates` | `socialmedia-national_lea_table_higharrestrate.png` | ✓ |

Note the PNG filename is singular (`…higharrestrate.png`) while the chunk label is
plural (`…higharrestrates`) — harmless but easy to mistype.

---

## Post 5 — Coefficient of variation (precision)
**Source:** Posts 4-6.docx · **Title:** "Basic facts — coefficient of variation" · **Status: posted**

| docx | chunk | PNG | status |
|------|-------|-----|--------|
| image2 (arrests vs referrals CV, by race × enrollment decile) | `cov_plot_decile_byraceeth` | `socialmedia-cov_plot_decile_byraceeth-1.png` | ✓ |

The posted figure is the two-panel (arrests / referrals) patchwork by race/eth.
- **Unused alternates** (rendered but not in any post): `cov_plot_quintile_total`,
  `cov_plot_decile_total` — total-only CV views, superseded by the by-race panel.
  Keep as exploratory or delete; flagged so they aren't mistaken for post assets.

---

## Post 6 — Arrest rates by race
**Source:** Posts 4-6.docx · **Title:** "Basic facts — arrest rates by race" · **Status: posted**

| docx | chunk | PNG | status |
|------|-------|-----|--------|
| image3 (cumulative share of arrests by population) | `arrests_concentration_by_sg` | `socialmedia-arrests_concentration_by_sg-1.png` | ✓ |

Verified rates /1,000: White 0.51 ✓ · AmInd 1.16 ✓ · Black 1.62 ✓ · Hispanic **0.66** ·
NNH male: White 1-in-1,489 (~1,500) ✓ · Black 1-in-506 (~500) ✓ · AmInd 1-in-714 (~700) ✓.
- ✅ **RESOLVED — district count & Hispanic rate.** Use **7 districts** (canonical;
  cumulative AM arrests reach 51.8% at 7) and Hispanic rate **0.66**. Apply inline in
  the qmd, no footnote/marker — both were already corrected live when posted on LinkedIn.
- **Candidate figure not shown:** `sg_summary_arrestNNH` (NNH by race × sex bars)
  directly backs this post's NNH sentence and could be added if a second image is
  wanted.

---

## Post 7 — Race deep-dive: American Indian arrests + first models *(draft)*
**Source:** Posts TO EDIT.docx ("Basic facts — arrest rates by race", expanded) · **Status: prose drafted, figures exist**

This continues Post 6 into the AM-specific analytic story and introduces the
modeling (the start of the "getting the most" arc).

| docx | chunk | PNG | status |
|------|-------|-----|--------|
| image1 (top AM districts → 51.8%) | `am_districts_table` | `socialmedia-am_districts_table.png` | ✓ |
| image2 (same districts, 3 waves) | `am_districts_table_3yr` (unlabeled, ~qmd:1153) | `socialmedia-am_districts_table_3yr.png` | ✓ |
| image3 (model panel, Sioux Falls) | `arrests_model_comparison_am` | `socialmedia-arrests_model_comparison_am-1.png` | ✓ |

Verified: 529 national AM arrests ✓ · 7 districts to 51.8% ✓ · largest AM district
2,038 students ("just over 2,000") ✓ · smallest in the set 58 ✓. Prose's
Sioux Falls binomial-CI-does-not-overlap-0 point is the blue frequentist pointrange
inside the `arrests_model_comparison_am` figure (`focal_dist = 4666270`).
- Model figure reproducible offline (draws tree present). Draft prose needs an
  editing pass; otherwise complete.

---

## Post 8 — "True" vs misreported zeros: descriptive *(draft)*
**Source:** Posts 7-x.docx (part 1) · **Title:** "Failure to report or actual difference in policy? …" · **Status: prose drafted, figures exist**

| docx | chunk | PNG | status |
|------|-------|-----|--------|
| image1 (expected arrests by enrollment range) | `display-expected-arrests` (+ `compute-expected-arrests`) | `socialmedia-expected_arrest_table.png` | ✓ |
| image2 (Paterson 47→11→0) | `big0_example_dist_table` (unlabeled, ~qmd:1624) | `socialmedia-big0_example_dist_table.png` | ✓ |

Verified: 2,060 districts reported an arrest ✓ · 45% of students in those districts
✓ · 376 districts with 20k+ students ✓ · 125 of them (33.2%) reported 0 arrests ✓ ·
national rate used for the "naïve" expectation ≈ 0.717/1,000.

---

## Post 9 — "True" vs misreported zeros: analytic *(draft — has a gap)*
**Source:** Posts 7-x.docx (part 2) · **Status: prose drafted; one figure missing**

| docx | chunk | PNG | status |
|------|-------|-----|--------|
| image3 — Fig 1 (Paterson: models vs frequentist interval) | **none** — `plotdf` is prepped at qmd:1613 but never plotted | **missing** | ⚠ **GAP** |
| image4 — Fig 2 (all-model histogram for Paterson) | `zero_arrest_counts_draws` | `socialmedia-zero_arrest_counts_draws-1.png` | ✓ |

- ⚠ **Action — render Fig 1.** The qmd computes Paterson's observed/frequentist
  pointrange data (`obsv_plot`, `model_plot`, `plotdf` near qmd:1576–1622) but stops
  before drawing the ridge-vs-frequentist comparison the post calls "Figure 1." The
  AM equivalent already exists — clone `arrests_model_comparison_am` with
  `focal_dist = 3412690` (Paterson NJ) to produce it. No PNG exists today.
- Fig 2 (`zero_arrest_counts_draws`) is the 4-panel posterior histogram; matches the
  post's "every draw plotted as a histogram." Reproducible offline.

---

## Post 10 — Methodology & future ideas (text only) *(draft)*
**Source:** Other ideas.docx · **Status: framing prose, no figures**

Two threads, both currently figure-free:
1. **Why model rare events** — small-area-estimation tradition (SAIPE, public-health
   prevalence, Bayesian rare-event models) and the *measurement vs population*
   framing. Natural lead-in to the modeling arc (Posts 7 & 9) and/or a closing post.
2. **Future ideas** — web app / API / AI interface; metro-area neighbor comparisons.
   Includes the Mobile County (309 arrests / 56,521 students) vs Jefferson County–
   Birmingham (1 arrest / 35,963) contrast — **no figure drafted**; a small
   two-district comparison plot or table could be generated if wanted.

Shared methodology footnotes (appear in Posts 7-x and Other ideas): restrict to
schools enrolling grade 7+, districts ≥30 students (drops 308 districts / 4,693
students / 1 arrest), and exclude group observations with 0 group enrollment.

---

## Consolidated gaps & TODOs

**Figures**
- [ ] **Post 9 Fig 1 missing** — add a render of the Paterson model-vs-frequentist
  comparison (clone `arrests_model_comparison_am`, `focal_dist = 3412690`).
- [ ] Decide on **`sg_summary_arrestNNH`** (NNH by race×sex) — promote into Post 6 or
  mark exploratory.
- [ ] Decide on **`cov_plot_quintile_total`, `cov_plot_decile_total`** — exploratory
  or delete (not used by any post).
- [ ] Optional Post 10 two-district comparison figure (Mobile vs Jefferson County).

**Number drift in posted copy (reconcile canonical values)**
- [x] Post 1: national NNH "1,428" → **1,395** (CRDC-consistent), with correction
  footnote citing CRDC-reported enrollment. *(Resolved 2026-06-22; not a stage diff —
  1,428 is an external/NCES denominator or 0.70-rate rounding artifact.)*
- [x] Post 2: decline "~40%" → **"~44% / over 40%"**. *(Resolved 2026-06-22.)*
- [x] Post 6: use **7 districts** and Hispanic rate **0.66**, applied inline (no footnote
  — already corrected live on LinkedIn). *(Resolved 2026-06-22.)*

**Stage provenance note.** Posts 1-2 (and all descriptive counts) are computed from the
**unfiltered** `full_crdc_data_y*` stage (`RACE=TOTAL & SEX=TOTAL`). The `model_data_y*`
stage is the filtered modeling subset (grade 7+, ≥30 students) used only for the model
figures (Posts 7 & 9) and gives slightly lower totals (e.g. 34,403 arrests in 2021-22).
Do not mix denominators across the two when reproducing numbers.

**QMD hygiene (reproducibility)**
- [ ] Add `#| label:` to the unlabeled figure chunks: AM 3-yr table (~qmd:1153),
  Paterson `big0` table (~qmd:1624), and the Paterson setup/prep chunks (~1547, 1576).
- [ ] Filename/label mismatch noted for Post 4 (`higharrestrate` vs `higharrestrates`).

**Reproduce from QMD**
- Set `CRDC_ARTIFACTS=export` and render `social_media_posts.qmd`; all 19 current
  PNGs (and the to-be-added Post 9 Fig 1) build from local artifacts. Posts 1–8
  numbers verified against gold-standard prose on 2026-06-22.
