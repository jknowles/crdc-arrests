# CRDC Social Media Posts Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `social_media_posts.qmd` into the single authored source of truth for a 10-post CRDC series (gold-standard prose + figures), build out the four unfinished posts, and add a Hugo-page-bundle export so every post can be published/syndicated on the Civilytics website.

**Architecture:** Each post becomes a fenced `:::{.smpost ...}` div in `social_media_posts.qmd` carrying its metadata, gold-standard prose, and the figure chunks that already reproduce it. The qmd renders to HTML (human review, existing `scripts/render-artifacts.sh`) and, with `freeze`, to gfm markdown without recomputing. A new `R/export_hugo_posts.R` splits the rendered markdown on the `smpost` divs and emits one Hugo page bundle per post (`index.md` + co-located figures) under `export/hugo/posts/<slug>/`.

**Tech Stack:** R (dplyr, duckdb, ggplot, flextable, brms-backed draws via DuckDB view), Quarto 1.9.37, pandoc fenced divs, testthat (3e) for the export helpers, Hugo page-bundle conventions.

## Global Constraints

- Resolve all data locally with `CRDC_ARTIFACTS=export` (no network). Draws tree present at `export/parquet/**` (1,876 partitions).
- Figures are written by knitr to `export/figures/socialmedia-<label>-1.png`; table PNGs are written explicitly to `export/figures/socialmedia-<name>.png`. Do not change these paths in Phase A/B (the export layer consumes them).
- Gold-standard posts (1-6) are **already publicly posted**: insert their prose **verbatim** from the docx, with two **resolved** corrections applied inline (see below) and the remaining drift wrapped in `<!-- DRIFT: prose=<X> data=<Y> -->` for the author.
  - **RESOLVED (apply inline, A1):** Post 1 national NNH "1 out of every 1,428" → **"1 out of every 1,395"**, and add a footnote: the original 1,428 used an external national-enrollment denominator; the corrected value uses CRDC-reported enrollment (48,596,489 ÷ 34,846), consistent with the 0.72/1,000 rate.
  - **RESOLVED (apply inline, A2):** Post 2 "declined by ~40%" → **"declined by ~44%"** (or "over 40%").
  - **RESOLVED (apply inline, A6):** Post 6 — use "7 districts" (canonical) and Hispanic rate "0.66". No footnote/marker; both were already corrected live when posted on LinkedIn.
- Stage provenance: descriptive counts (Posts 1-6, 8) come from the **unfiltered** `full_crdc_data_y*` stage (`RACE=TOTAL & SEX=TOTAL`). `model_data_y*` is the filtered modeling subset (grade 7+, ≥30 students) and is used only for model figures (Posts 7 & 9). Never mix the two denominators.
- Unfinished posts (7-10) were never posted: draft fresh prose using the data-verified numbers below.
- Verified numbers (2026-06-22, `/tmp/verify_posts.R`): national 34,846 arrests, 0.72/1,000, NNH 1,395; KS NNH 194, SD 348; trend 62,020→52,300→34,846 (−44%); KS 2,413/565/521, CA 1,563/2,151/3,424; rates/1k WH 0.51, HI 0.66, AM 1.16, BL 1.62; male NNH WH 1,489, BL 506, AM 714; AM 529 arrests / top-7 districts = 51.8% (largest 2,038, smallest 58); zeros: 2,060 districts with an arrest (11.6%, 45% of students), 376 districts ≥20k students, 125 (33.2%) report 0.
- Post slugs (fixed): `how-states-stack-up`, `arrests-declining-everywhere`, `districts-most-arrests`, `highest-arrest-rates`, `coefficient-of-variation`, `arrest-rates-by-race`, `american-indian-arrests-models`, `misreported-zeros-descriptive`, `misreported-zeros-analytic`, `estimating-rare-events`.
- Source map of record: `docs/social-media-post-map.md`.

---

## File Structure

- **Modify** `social_media_posts.qmd` — add YAML `freeze: auto`; wrap each of the 10 posts in `:::{.smpost}` divs; insert gold-standard prose (1-6) and drafted prose (7-10); add the missing Post 9 figure chunk; add `#| label:` to currently-unlabeled chunks.
- **Create** `R/export_hugo_posts.R` — pure functions to parse the rendered gfm markdown and write Hugo bundles. No side effects beyond the documented writer.
- **Create** `tests/testthat/test-export_hugo_posts.R` — testthat tests for the parser/writer using synthetic markdown + a dummy PNG.
- **Create** `scripts/export-hugo-posts.sh` — orchestration: render to gfm (frozen), then run the exporter.
- **Modify** `docs/social-media-post-map.md` — tick off gaps as they close (Post 9 fig, labels, drift decisions).
- **Output (generated, git-ignored)** `export/hugo/posts/<slug>/index.md` + figures.

Per-post figure manifest (post → ordered figure files), used by Phase C and as the authoritative ordering when inserting chunks in Phase A/B:

| post | slug | figures (in `export/figures/`) |
|------|------|--------------------------------|
| 1 | how-states-stack-up | `socialmedia-arrest_chloropleth-1.png`, `socialmedia-arrest_rate_chloropleth-1.png`, `socialmedia-state_arrest_nnh_map-1.png` |
| 2 | arrests-declining-everywhere | `socialmedia-national_trend-1.png`, `socialmedia-national_arrest_rate_trend-1.png`, `socialmedia-select_state_arrest_trend-1.png` |
| 3 | districts-most-arrests | `socialmedia-national_lea_table.png` |
| 4 | highest-arrest-rates | `socialmedia-national_lea_table_higharrestrate.png` |
| 5 | coefficient-of-variation | `socialmedia-cov_plot_decile_byraceeth-1.png` |
| 6 | arrest-rates-by-race | `socialmedia-arrests_concentration_by_sg-1.png` |
| 7 | american-indian-arrests-models | `socialmedia-am_districts_table.png`, `socialmedia-am_districts_table_3yr.png`, `socialmedia-arrests_model_comparison_am-1.png` |
| 8 | misreported-zeros-descriptive | `socialmedia-expected_arrest_table.png`, `socialmedia-big0_example_dist_table.png` |
| 9 | misreported-zeros-analytic | `socialmedia-paterson_model_comparison-1.png` (NEW, Task B1), `socialmedia-zero_arrest_counts_draws-1.png` |
| 10 | estimating-rare-events | *(text only)* |

---

## PHASE A — Make the qmd the single source of truth (Posts 1-6)

### Task A0: Add freeze + the post-div scaffold and a verification render

**Files:**
- Modify: `social_media_posts.qmd` (YAML header ~lines 3-21; body)

**Interfaces:**
- Produces: the `:::{.smpost slug=… title=… date=… status=… series=…}` div convention every later task uses, and `freeze: auto` so the gfm render reuses HTML compute.

- [ ] **Step 1: Add `freeze: auto` to the qmd execute block**

In the YAML header `execute:` map, add:
```yaml
execute:
  freeze: auto
  warning: false
  message: false
  error: false
  fig-width: 11
  fig-height: 7
```

- [ ] **Step 2: Wrap the existing Post 1 section in an smpost div (scaffold only, no prose yet)**

Immediately after `## Post 1: State and National Totals` insert an opening div and close it before `## Post 2`:
```markdown
::: {.smpost slug="how-states-stack-up" title="Arrests in schools in 2021-22: How states stack up on student arrests" date="2025-02-01" status="gold" series="1"}
```
(close with a line containing only `:::` just before the `## Post 2` heading). Use a real publication date if known; otherwise leave the date and resolve in Phase C front matter.

- [ ] **Step 3: Render to confirm the div parses and figures still build**

Run: `CRDC_ARTIFACTS=export quarto render social_media_posts.qmd --to html`
Expected: completes without error; `social_media_posts.html` regenerated; Post 1 maps present in `export/figures/`.

- [ ] **Step 4: Commit**

```bash
git add social_media_posts.qmd
git commit -m "refactor(social): add freeze + smpost div scaffold for Post 1"
```

### Task A1: Post 1 prose (gold-standard, verbatim) + drift markers

**Files:**
- Modify: `social_media_posts.qmd` (inside the Post 1 smpost div)

**Interfaces:**
- Consumes: smpost div from A0.
- Produces: prose pattern (verbatim docx text + `<!-- DRIFT -->` comments) reused by A2-A6.

- [ ] **Step 1: Insert the verbatim Post 1 prose from `inst/Posts 1-3.docx` (section "Basic facts — average rate and rate by state").**

Place the series-intro paragraph + AERA/NSF disclaimer once at the very top of the document (above Post 1) as a shared preamble, then the post body. Interleave the three figure chunks in manifest order between the prose paragraphs exactly where the docx places image1/image2/image3. **Apply the resolved NNH correction:** change "1 out of every 1,428 students was arrested" to "1 out of every 1,395 students was arrested", and add a footnote at that sentence:
```markdown
^[Corrected from the originally posted "1 in 1,428." This number-needed-to-harm uses
CRDC-reported enrollment (48,596,489 students ÷ 34,846 arrests = 1 in 1,395), the exact
reciprocal of the 0.72-per-1,000 national rate from the same data. The original 1,428
reflected an external national-enrollment denominator.]
```

- [ ] **Step 2: Render and verify**

Run: `CRDC_ARTIFACTS=export quarto render social_media_posts.qmd --to html`
Expected: Post 1 shows the three maps with prose; no render error.

- [ ] **Step 3: Commit**

```bash
git add social_media_posts.qmd
git commit -m "feat(social): author Post 1 gold-standard prose with drift marker"
```

### Task A2: Post 2 prose + drift marker

**Files:** Modify `social_media_posts.qmd` (Post 2 section).

- [ ] **Step 1:** Wrap `## Post 2: Trends` in `::: {.smpost slug="arrests-declining-everywhere" title="School-based arrests are declining but is this true everywhere?" date="2025-02-08" status="gold" series="2"} … :::`. Insert verbatim prose from `inst/Posts 1-3.docx` ("Basic facts — trends over time…"), interleaving `national_trend` / `national_arrest_rate_trend` / `select_state_arrest_trend` chunks where image4/5/6 sit. **Apply the resolved correction:** change "declined by ~40%" to "declined by ~44%". Keep the "\*A note on CRDC waves" block.
- [ ] **Step 2:** Run `CRDC_ARTIFACTS=export quarto render social_media_posts.qmd --to html`; expect Post 2 line charts + KS/CA panel render.
- [ ] **Step 3:** `git add social_media_posts.qmd && git commit -m "feat(social): author Post 2 gold-standard prose with drift marker"`

### Task A3: Post 3 prose

**Files:** Modify `social_media_posts.qmd` (the `## Districts` / `national_lea_table` area).

- [ ] **Step 1:** Wrap the top-20-by-arrests table in `::: {.smpost slug="districts-most-arrests" title="Some districts arrest hundreds of students and have arrest rates 10x the national average" date="2025-02-15" status="gold" series="3"} … :::`. Insert verbatim prose from `inst/Posts 1-3.docx` ("Basic facts — districts with most arrests"), including the four numbered observations, around the `national_lea_table` chunk.
- [ ] **Step 2:** Render; expect the top-20 arrests table PNG embedded.
- [ ] **Step 3:** `git commit -m "feat(social): author Post 3 gold-standard prose"`

### Task A4: Post 4 prose

**Files:** Modify `social_media_posts.qmd` (`national_lea_table_higharrestrates`).

- [ ] **Step 1:** Wrap that chunk in `::: {.smpost slug="highest-arrest-rates" title="Districts with the highest arrest rates are small, serve special education students and Native Americans" date="2025-02-22" status="gold" series="4"} … :::`. Insert verbatim prose from `inst/Posts 4-6.docx` ("Basic facts — districts with highest arrest rates"), including the five numbered points and the "Tomorrow, we'll look…" teaser.
- [ ] **Step 2:** Render; expect the top-20-by-rate table.
- [ ] **Step 3:** `git commit -m "feat(social): author Post 4 gold-standard prose"`

### Task A5: Post 5 prose + retire unused CV chunks

**Files:** Modify `social_media_posts.qmd` (CV section).

- [ ] **Step 1:** Wrap `cov_plot_decile_byraceeth` in `::: {.smpost slug="coefficient-of-variation" title="Basic facts — coefficient of variation" date="2025-03-01" status="gold" series="5"} … :::`. Insert verbatim prose from `inst/Posts 4-6.docx` ("Basic facts — coefficient of variation"), including the closing "uptick…underreporting" note.
- [ ] **Step 2:** Mark the two unused CV chunks (`cov_plot_quintile_total`, `cov_plot_decile_total`) `#| eval: false` and add a comment `# exploratory: superseded by cov_plot_decile_byraceeth (see post map)`. Do not delete (kept for exploration).
- [ ] **Step 3:** Render; expect only the by-race CV patchwork in Post 5, no errors from the disabled chunks.
- [ ] **Step 4:** `git commit -m "feat(social): author Post 5 prose; disable superseded CV chunks"`

### Task A6: Post 6 prose + drift markers + decide sg_summary figure

**Files:** Modify `social_media_posts.qmd` (`arrests_concentration_by_sg`, `sg_summary_arrestNNH`).

- [ ] **Step 1:** Wrap `arrests_concentration_by_sg` in `::: {.smpost slug="arrest-rates-by-race" title="Basic facts — arrest rates by race" date="2025-03-08" status="gold" series="6"} … :::`. Insert prose from `inst/Posts 4-6.docx` ("Basic facts — arrest rates by race") with two corrections applied inline (no markers): change the closing "just 6 districts" to "just 7 districts" so both mentions read **7**, and change "Hispanic students 0.65" to "Hispanic students 0.66".
- [ ] **Step 2:** Leave `sg_summary_arrestNNH` chunk in place but OUTSIDE the smpost div (it backs the NNH sentence but was not in the posted image). Add comment `# candidate add-on for Post 6 NNH sentence; not in posted version`.
- [ ] **Step 3:** Render; expect the cumulative-concentration figure in Post 6.
- [ ] **Step 4:** `git commit -m "feat(social): author Post 6 prose with drift markers"`

---

## PHASE B — Build out the unfinished posts (7-10)

### Task B1: Add the missing Post 9 "Figure 1" render (Paterson model-vs-frequentist)

**Files:**
- Modify: `social_media_posts.qmd` (the Paterson section around qmd:1576-1622, before `zero_arrest_counts_draws`)

**Interfaces:**
- Consumes: `con` (draws view), `rdata`, `get_prediction_summary`, `get_prediction_draws`, `agresti_coull`, `add_model_time`, `add_model_cov` — all already defined in the qmd.
- Produces: `export/figures/socialmedia-paterson_model_comparison-1.png` (manifest entry for Post 9).

- [ ] **Step 1: Add a labelled figure chunk that clones `arrests_model_comparison_am` for Paterson.**

Insert directly after the existing Paterson `plotdf`/`model_plot` prep chunk (the one ending ~qmd:1622):
````markdown
```{r}
#| label: paterson_model_comparison
#| echo: false
#| warning: false
#| message: false
#| fig-width: 12
#| fig-height: 8

# Figure 1 of Post 9 (Posts 7-x): predicted-arrest density per model vs the
# frequentist interval for Paterson NJ (focal_dist = 3412690), mirroring
# arrests_model_comparison_am. dist_draws/obsv_plot are from the prep chunk above.
res_pat <- dist_draws |>
  filter(!grepl("_m5", model_id), !grepl("sg_", model_id)) |>
  group_by(model_id, draw_id) |>
  summarize(pred = sum(pred), .groups = "drop") |>
  group_by(model_id) |>
  mutate(model_time = add_model_time(model_id),
         model_label = paste0(add_model_time(model_id), "\n", add_model_cov(model_id)))

obsv_pat <- obsv_plot |>
  tidyr::crossing(model_id = unique(res_pat$model_id)) |>
  mutate(model_label = paste0(add_model_time(model_id), "\n", add_model_cov(model_id)),
         model_time  = add_model_time(model_id))

p1 <- ggplot(res_pat, aes(x = pred, y = model_label, group = model_label)) +
  ggridges::geom_density_ridges(scale = 0.9, rel_min_height = 0.01) +
  geom_pointrange(data = obsv_pat,
    aes(y = model_label, x = arrests, xmin = ci_lower, xmax = ci_upper),
    color = I("#2993fd"), position = position_nudge(y = 0.2)) +
  scale_y_discrete("Model", limits = rev,
                   expand = expansion(mult = c(0.1, 0.15))) +
  facet_wrap(~add_model_time(model_id), ncol = 2, scales = "free") +
  labs(title = stringr::str_wrap(paste0("Predicted arrests probability density for ",
        dist_name_for_title), 90),
       x = "Predicted arrests", y = "Model type",
       subtitle = stringr::str_wrap("Observed arrests and frequentist interval shown in bright blue pointrange (0 reported arrests).", 90)) +
  ggridges::theme_ridges(grid = FALSE, font_size = 14) +
  theme(legend.position = "bottom",
        panel.grid.major.y = element_line(color = "gray50"),
        axis.text.y = element_text(angle = 90, hjust = -0.5))

grid::grid.draw(civilytics::civilytics_logo(p1, position = "bottom-left"))
```
````

- [ ] **Step 2: Render just this document and confirm the PNG is produced**

Run: `CRDC_ARTIFACTS=export quarto render social_media_posts.qmd --to html`
Then: `ls -la export/figures/socialmedia-paterson_model_comparison-1.png`
Expected: file exists, non-zero size; HTML shows the Paterson ridge+pointrange figure with two facets (one-year vs three-year).

- [ ] **Step 3: Tick the gap in the post map**

In `docs/social-media-post-map.md`, change the Post 9 Fig 1 row status from `⚠ GAP` to `✓` and check the consolidated-gaps box.

- [ ] **Step 4: Commit**

```bash
git add social_media_posts.qmd docs/social-media-post-map.md
git commit -m "feat(social): render Post 9 Fig 1 (Paterson model-vs-frequentist)"
```

### Task B2: Author Post 7 (American Indian arrests + models)

**Files:** Modify `social_media_posts.qmd` (the `## Arrests by race` AM deep-dive: `am_districts_table`, the unlabeled 3-yr table chunk ~1153, `arrests_model_comparison_am`).

- [ ] **Step 1:** Add `#| label: am_districts_table_3yr` to the currently-unlabeled 3-year AM table chunk (~qmd:1153) so its PNG path is stable.
- [ ] **Step 2:** Wrap the three AM chunks in `::: {.smpost slug="american-indian-arrests-models" title="A closer look: American Indian student arrests and what models tell us" date="" draft="true" status="draft" series="7"} … :::`.
- [ ] **Step 3:** Draft gold-standard prose (to match the Posts 1-6 voice) from `inst/Posts TO EDIT.docx`, using verified numbers: 529 AM arrests, top-7 districts = 51.8%, largest 2,038 / smallest 58 students, AM rate 1.16/1,000, Sioux Falls binomial-CI ruling out 0, and the two model patterns (more years → lower estimate; covariates → higher). Keep the "Which is correct? …future posts!" hook. Place figures in manifest order.
- [ ] **Step 4:** Run `CRDC_ARTIFACTS=export quarto render social_media_posts.qmd --to html`; expect both AM tables + the model panel.
- [ ] **Step 5:** `git commit -m "feat(social): draft Post 7 (American Indian arrests + models)"`

### Task B3: Author Post 8 (misreported zeros — descriptive)

**Files:** Modify `social_media_posts.qmd` (`## Post 8` expected-arrests + `big0_example_dist_table`).

- [ ] **Step 1:** Add `#| label: big0_example_dist_table` to the unlabeled Paterson reporting-pattern table chunk (~qmd:1624).
- [ ] **Step 2:** Wrap the expected-arrest table + Paterson reporting table in `::: {.smpost slug="misreported-zeros-descriptive" title="Failure to report, or a real difference in policy? Populous districts reporting zero arrests" date="" draft="true" status="draft" series="8"} … :::`.
- [ ] **Step 3:** Draft prose from `inst/Posts 7-x.docx` ("True vs Misreported Zeros — Descriptive"), verified numbers: 2,060 districts (11.6%) reported an arrest yet enrolled 45% of students; 376 districts ≥20k students, 125 (33.2%) reported 0; Paterson 47→11→0. Keep the OCR data-quality citation.
- [ ] **Step 4:** Render; expect the expected-arrests table and the Paterson table.
- [ ] **Step 5:** `git commit -m "feat(social): draft Post 8 (misreported zeros — descriptive)"`

### Task B4: Author Post 9 (misreported zeros — analytic)

**Files:** Modify `social_media_posts.qmd` (Paterson `paterson_model_comparison` from B1 + `zero_arrest_counts_draws`).

- [ ] **Step 1:** Wrap both Paterson figure chunks + the existing trailing analytic prose (qmd:1826-1846) in `::: {.smpost slug="misreported-zeros-analytic" title="What ten models say about Paterson's zero arrests" date="" draft="true" status="draft" series="9"} … :::`.
- [ ] **Step 2:** Replace/expand the existing draft analytic text with gold-standard prose from `inst/Posts 7-x.docx` ("True vs Misreported Zeros — Analytic"): Paterson 18,310 students; one-year vs three-year split; per-model 0-arrest probabilities (stratified 47.2%→76.4% with covariate; unified 82.2%→84%); three-year no-covariate models confidently rule out 0; covariates pull down (0 referrals reported in 2021-22); the "100 largest 0-arrest districts → 751-1,794 missing arrests" framing. Reference Figure 1 (`paterson_model_comparison`) then Figure 2 (`zero_arrest_counts_draws`).
- [ ] **Step 3:** Render; expect both Paterson figures with the analytic narrative.
- [ ] **Step 4:** `git commit -m "feat(social): draft Post 9 (misreported zeros — analytic)"`

### Task B5: Author Post 10 (methodology & future ideas, text only)

**Files:** Modify `social_media_posts.qmd` (append a new text-only section before the `cleanup` chunk).

- [ ] **Step 1:** Add `::: {.smpost slug="estimating-rare-events" title="Estimating rare events in fixed populations: lessons from other fields" date="" draft="true" status="draft" series="10"} … :::` containing drafted prose from `inst/Other ideas.docx`: the small-area-estimation tradition (SAIPE, public-health prevalence, Bayesian rare-event models), the measurement-vs-population framing, the shared methodology footnotes (grade 7+, ≥30 students, exclude 0-group-enrollment), and the future-ideas paragraph (web app/API; Mobile County 309/56,521 vs Jefferson County 1/35,963).
- [ ] **Step 2:** Render; expect a text-only post section, no new figures, no errors.
- [ ] **Step 3:** `git commit -m "feat(social): draft Post 10 (methodology & future ideas)"`

---

## PHASE C — Hugo page-bundle export

### Task C1: Parser — split rendered gfm markdown into posts

**Files:**
- Create: `R/export_hugo_posts.R`
- Test: `tests/testthat/test-export_hugo_posts.R`

**Interfaces:**
- Produces: `parse_smposts(md_text) -> list` where each element is `list(slug=chr, title=chr, date=chr, status=chr, series=chr, draft=lgl, body=chr, images=chr[])`. `images` are repo-relative paths extracted from `![...](path)` and any `<img src="path">` in the post body, in document order, deduplicated.

- [ ] **Step 1: Write the failing test**

```r
# tests/testthat/test-export_hugo_posts.R
source(here::here("R/export_hugo_posts.R"))

test_that("parse_smposts splits posts and pulls metadata + images", {
  md <- paste(
    '<div class="smpost" slug="alpha" title="Alpha Title" date="2025-02-01" status="gold" series="1">',
    'Intro text about arrests.',
    '![map](export/figures/socialmedia-arrest_chloropleth-1.png)',
    'More text.',
    '</div>',
    '<div class="smpost" slug="beta" title="Beta Title" date="" status="draft" series="7" draft="true">',
    'Beta body.',
    '![tab](export/figures/socialmedia-am_districts_table.png)',
    '</div>',
    sep = "\n")
  posts <- parse_smposts(md)
  expect_length(posts, 2)
  expect_equal(posts[[1]]$slug, "alpha")
  expect_equal(posts[[1]]$title, "Alpha Title")
  expect_equal(posts[[1]]$series, "1")
  expect_false(posts[[1]]$draft)
  expect_equal(posts[[1]]$images, "export/figures/socialmedia-arrest_chloropleth-1.png")
  expect_true(posts[[2]]$draft)
  expect_equal(posts[[2]]$slug, "beta")
})
```

- [ ] **Step 2: Run it, expect failure**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-export_hugo_posts.R")'`
Expected: FAIL — `could not find function "parse_smposts"`.

- [ ] **Step 3: Implement `parse_smposts`**

```r
# R/export_hugo_posts.R
# Split Quarto-rendered gfm markdown into per-post records. Pandoc renders a
# fenced ::: {.smpost k="v"} div as <div class="smpost" k="v"> ... </div> in gfm
# (with raw_html), which we parse here. No external deps beyond base R.

.attr <- function(tag, name) {
  m <- regmatches(tag, regexec(sprintf('%s="([^"]*)"', name), tag))[[1]]
  if (length(m) >= 2) m[2] else ""
}

parse_smposts <- function(md_text) {
  # Grab each <div class="smpost" ...> ... </div> block (non-greedy, multiline).
  pat <- '(?s)<div class="smpost"[^>]*>.*?</div>'
  blocks <- regmatches(md_text, gregexpr(pat, md_text, perl = TRUE))[[1]]
  lapply(blocks, function(b) {
    open_tag <- regmatches(b, regexpr('<div class="smpost"[^>]*>', b))
    body <- sub('^<div class="smpost"[^>]*>\\s*', "", b)
    body <- sub('\\s*</div>\\s*$', "", body)
    md_imgs  <- regmatches(body, gregexpr('!\\[[^]]*\\]\\(([^)]+)\\)', body, perl = TRUE))[[1]]
    md_paths <- sub('^!\\[[^]]*\\]\\(([^)]+)\\)$', '\\1', md_imgs)
    html_imgs <- regmatches(body, gregexpr('<img[^>]*src="([^"]+)"', body, perl = TRUE))[[1]]
    html_paths <- sub('.*src="([^"]+)".*', '\\1', html_imgs)
    imgs <- unique(c(md_paths, html_paths))
    list(
      slug   = .attr(open_tag, "slug"),
      title  = .attr(open_tag, "title"),
      date   = .attr(open_tag, "date"),
      status = .attr(open_tag, "status"),
      series = .attr(open_tag, "series"),
      draft  = identical(.attr(open_tag, "draft"), "true"),
      body   = body,
      images = imgs
    )
  })
}
```

- [ ] **Step 4: Run the test, expect pass**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-export_hugo_posts.R")'`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add R/export_hugo_posts.R tests/testthat/test-export_hugo_posts.R
git commit -m "feat(export): parse_smposts splits rendered markdown into posts"
```

### Task C2: Front matter + bundle writer

**Files:**
- Modify: `R/export_hugo_posts.R`
- Test: `tests/testthat/test-export_hugo_posts.R`

**Interfaces:**
- Consumes: a post record from `parse_smposts`.
- Produces:
  - `hugo_front_matter(post) -> chr` (a `---`-delimited YAML block: title, date (empty → omitted), draft, weight=series, slug, plus `series: "CRDC school arrests"` and `source: "U.S. Dept. of Education CRDC"`).
  - `write_hugo_bundle(post, out_root, repo_root) -> chr` (creates `out_root/<slug>/`, copies each image to the bundle as `figure-<n>.png`, rewrites body image links to the bundle-relative filename, writes `index.md` = front matter + rewritten body, returns the bundle dir).

- [ ] **Step 1: Write failing tests**

```r
test_that("hugo_front_matter renders required keys and omits empty date", {
  p <- list(slug="alpha", title="Alpha Title", date="", status="gold",
            series="1", draft=FALSE, body="x", images=character())
  fm <- hugo_front_matter(p)
  expect_match(fm, '^---\\n')
  expect_match(fm, 'title: "Alpha Title"')
  expect_match(fm, 'weight: 1')
  expect_false(grepl("date:", fm))   # empty date omitted
  expect_match(fm, 'draft: false')
})

test_that("write_hugo_bundle copies figures and rewrites links", {
  tmp <- withr::local_tempdir()
  repo <- withr::local_tempdir()
  dir.create(file.path(repo, "export/figures"), recursive = TRUE)
  png_src <- file.path(repo, "export/figures/socialmedia-x-1.png")
  writeBin(as.raw(c(0x89,0x50,0x4e,0x47)), png_src)  # fake PNG header
  p <- list(slug="alpha", title="Alpha", date="2025-02-01", status="gold",
            series="1", draft=FALSE,
            body="Body\n![map](export/figures/socialmedia-x-1.png)\nEnd",
            images="export/figures/socialmedia-x-1.png")
  dir <- write_hugo_bundle(p, out_root = tmp, repo_root = repo)
  expect_true(file.exists(file.path(dir, "index.md")))
  expect_true(file.exists(file.path(dir, "figure-1.png")))
  idx <- paste(readLines(file.path(dir, "index.md")), collapse = "\n")
  expect_match(idx, '\\!\\[map\\]\\(figure-1.png\\)')
  expect_false(grepl("export/figures", idx))
})
```

- [ ] **Step 2: Run, expect failure**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-export_hugo_posts.R")'`
Expected: FAIL — functions not found.

- [ ] **Step 3: Implement**

```r
hugo_front_matter <- function(post) {
  lines <- c("---",
             sprintf('title: "%s"', gsub('"', '\\\\"', post$title)),
             sprintf('slug: "%s"', post$slug),
             sprintf('weight: %s', if (nzchar(post$series)) post$series else "0"),
             sprintf('draft: %s', tolower(as.character(isTRUE(post$draft)))),
             'series: "CRDC school arrests"',
             'source: "U.S. Department of Education, Civil Rights Data Collection"')
  if (nzchar(post$date)) lines <- append(lines, sprintf('date: "%s"', post$date), after = 2)
  paste(c(lines, "---", ""), collapse = "\n")
}

write_hugo_bundle <- function(post, out_root, repo_root) {
  dir <- file.path(out_root, post$slug)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  body <- post$body
  for (i in seq_along(post$images)) {
    src <- file.path(repo_root, post$images[i])
    dest_name <- sprintf("figure-%d.png", i)
    if (file.exists(src)) file.copy(src, file.path(dir, dest_name), overwrite = TRUE)
    # rewrite both ![..](path) and <img src="path"> occurrences of this image
    body <- gsub(post$images[i], dest_name, body, fixed = TRUE)
  }
  writeLines(paste0(hugo_front_matter(post), body), file.path(dir, "index.md"))
  dir
}
```

- [ ] **Step 4: Run, expect pass**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-export_hugo_posts.R")'`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add R/export_hugo_posts.R tests/testthat/test-export_hugo_posts.R
git commit -m "feat(export): hugo_front_matter + write_hugo_bundle"
```

### Task C3: Orchestrator function + end-to-end smoke test

**Files:**
- Modify: `R/export_hugo_posts.R`
- Test: `tests/testthat/test-export_hugo_posts.R`

**Interfaces:**
- Produces: `export_hugo_posts(md_path, out_root = "export/hugo/posts", repo_root = ".") -> chr[]` (reads the rendered markdown file, parses, writes every bundle, returns the bundle dirs).

- [ ] **Step 1: Write failing test**

```r
test_that("export_hugo_posts writes one bundle per post from a markdown file", {
  repo <- withr::local_tempdir()
  dir.create(file.path(repo, "export/figures"), recursive = TRUE)
  writeBin(as.raw(c(0x89,0x50)), file.path(repo, "export/figures/socialmedia-x-1.png"))
  md <- paste(
    '<div class="smpost" slug="alpha" title="A" date="2025-02-01" status="gold" series="1">',
    'Body ![m](export/figures/socialmedia-x-1.png)',
    '</div>',
    '<div class="smpost" slug="beta" title="B" date="" status="draft" series="7" draft="true">',
    'Beta body, no image.',
    '</div>', sep = "\n")
  md_path <- file.path(repo, "social_media_posts.md")
  writeLines(md, md_path)
  out <- file.path(repo, "export/hugo/posts")
  dirs <- export_hugo_posts(md_path, out_root = out, repo_root = repo)
  expect_length(dirs, 2)
  expect_true(file.exists(file.path(out, "alpha", "index.md")))
  expect_true(file.exists(file.path(out, "alpha", "figure-1.png")))
  expect_true(file.exists(file.path(out, "beta", "index.md")))
})
```

- [ ] **Step 2: Run, expect failure** — `export_hugo_posts` not found.

- [ ] **Step 3: Implement**

```r
export_hugo_posts <- function(md_path, out_root = "export/hugo/posts", repo_root = ".") {
  md <- paste(readLines(md_path, warn = FALSE), collapse = "\n")
  posts <- parse_smposts(md)
  vapply(posts, write_hugo_bundle, character(1), out_root = out_root, repo_root = repo_root)
}
```

- [ ] **Step 4: Run, expect pass** (4 tests total).

- [ ] **Step 5: Commit**

```bash
git add R/export_hugo_posts.R tests/testthat/test-export_hugo_posts.R
git commit -m "feat(export): export_hugo_posts orchestrator"
```

### Task C4: Render-to-gfm + export shell script, run end-to-end

**Files:**
- Create: `scripts/export-hugo-posts.sh`
- Modify: `.gitignore` (add `export/hugo/`)

**Interfaces:**
- Consumes: `export_hugo_posts()`.
- Produces: real bundles under `export/hugo/posts/<slug>/`.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Render social_media_posts.qmd to gfm (reusing frozen compute) and split it
# into Hugo page bundles under export/hugo/posts/<slug>/.
set -euo pipefail
cd "$(dirname "$0")/.."
export CRDC_ARTIFACTS="${CRDC_ARTIFACTS:-export}"

echo ">>> rendering social_media_posts.qmd -> gfm (frozen)"
quarto render social_media_posts.qmd --to gfm

echo ">>> exporting Hugo page bundles"
Rscript -e 'source("R/export_hugo_posts.R"); dirs <- export_hugo_posts("social_media_posts.md"); cat(length(dirs), "bundles:\n"); cat(dirs, sep="\n")'

echo "Done. Bundles in export/hugo/posts/."
```

- [ ] **Step 2: Make executable + ignore output**

Run: `chmod +x scripts/export-hugo-posts.sh` and add `export/hugo/` to `.gitignore`.

- [ ] **Step 3: Run end-to-end**

Run: `CRDC_ARTIFACTS=export scripts/export-hugo-posts.sh`
Expected: prints "10 bundles"; `export/hugo/posts/how-states-stack-up/index.md` exists with front matter + prose; `figure-1.png … figure-3.png` present in Post 1's bundle; draft posts (7-10) have `draft: true` front matter; Post 10 bundle has `index.md` and no figures.

- [ ] **Step 4: Spot-check a bundle**

Run: `head -20 export/hugo/posts/how-states-stack-up/index.md && ls export/hugo/posts/how-states-stack-up/`
Expected: YAML front matter (title, slug, weight: 1, draft: false, series, source), prose body, image links rewritten to `figure-N.png` (no `export/figures` paths remain).

- [ ] **Step 5: Commit**

```bash
git add scripts/export-hugo-posts.sh .gitignore
git commit -m "feat(export): render-to-gfm + Hugo bundle export script"
```

### Task C5: Wire export into the artifact render flow + document

**Files:**
- Modify: `scripts/render-artifacts.sh` (optional hook), `docs/social-media-post-map.md`

- [ ] **Step 1:** At the end of `scripts/render-artifacts.sh`, after the render loop, add an optional Hugo-export step guarded by a flag:
```bash
if [ "${EXPORT_HUGO:-0}" = "1" ]; then
  scripts/export-hugo-posts.sh
fi
```
- [ ] **Step 2:** Add a short "Publishing (Hugo bundles)" section to `docs/social-media-post-map.md` describing `scripts/export-hugo-posts.sh`, the `export/hugo/posts/<slug>/` layout, and that drafts emit `draft: true`.
- [ ] **Step 3:** Run `CRDC_ARTIFACTS=export EXPORT_HUGO=1 scripts/render-artifacts.sh social_media_posts.qmd`; expect HTML + 10 bundles.
- [ ] **Step 4:** `git add scripts/render-artifacts.sh docs/social-media-post-map.md && git commit -m "chore(export): optional Hugo export hook + docs"`

---

## Self-Review

**Spec coverage:**
- Goal #2 (re-render gold standard from source) → Phase A (A0-A6) puts prose in the qmd and verifies each renders from local data. ✓
- Goal #1 (build unfinished posts) → Phase B (B1 figure gap + B2-B5 prose). ✓
- Goal #3 (export for website/syndication) → Phase C (C1-C5), Hugo page bundles. ✓
- Post map gaps (Post 9 fig, unlabeled chunks, unused figures, drift) → B1, B2/B3 (labels), A5/A6 (unused/candidate figures), drift markers in A1/A2/A6. ✓

**Placeholder scan:** Prose-insertion steps reference exact docx sections (unambiguous, recoverable) rather than re-inlining ~3,000 words; all code steps include complete code. Dates in front matter are genuine author-owned config (empty date is explicitly handled and omitted). No "TBD"/"handle edge cases" left.

**Type consistency:** `parse_smposts` record fields (`slug,title,date,status,series,draft,body,images`) are consumed identically by `hugo_front_matter`, `write_hugo_bundle`, and `export_hugo_posts`. Figure file names (`figure-<n>.png`) and the manifest PNG names are consistent across Phase A/B authoring and Phase C rewriting.

**Resolved number drifts (applied inline in Phase A):** Post 1 NNH → 1,395 + correction footnote; Post 2 decline → "~44%"; Post 6 → "7 districts" and Hispanic "0.66" (no marker, fixed live on LinkedIn).

**Open author decisions (non-blocking):** real publication dates for Posts 1-6; whether to promote `sg_summary_arrestNNH` into Post 6.
