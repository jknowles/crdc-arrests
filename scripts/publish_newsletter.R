#!/usr/bin/env Rscript
# Bridge social_media_posts.qmd's .smpost sections into homepage_test
# newsletter bundles (content/newsletter/<slug>/index.md) for staging review,
# then push straight to homepage_test's `dev` branch -- its own CI
# (.gitea/workflows/pages.yml) auto-builds and publishes dev to
# https://pages.civilytics.org/homepage_test/ on every push. No PR needed for
# a staging refresh; a PR is only opened by hand, later, to promote dev to
# main (production, civilytics.com).
#
# Lock-in rule: a slug already present under content/newsletter/<slug>/ on
# homepage_test's `main` (production) branch is skipped entirely -- it has
# shipped, and social_media_posts.qmd is no longer authoritative for it.
# Re-running this script after a post goes live never touches it again.
#
# Mirrors the ephemeral-workspace + commit-only-if-changed style of
# scripts/publish_docs.R, but targets a second repo (a fresh throwaway clone,
# not a worktree of this repo) -- homepage_test is a wholly separate site
# with its own history, and the maintainer's personal local clone of it may
# have unrelated uncommitted work in progress, so this script never touches
# that clone.
#
# Usage: Rscript scripts/publish_newsletter.R [--dry-run]
#   --dry-run   Build the bundles locally and print what would change;
#               never clones, commits, or pushes to homepage_test.

QMD_PATH <- "social_media_posts.qmd"
FIGURES_DIR <- "export/figures"
HOMEPAGE_REMOTE <- "https://gitea.civilytics.org/jared/homepage_test.git"

# Named POST-PROSE block in the qmd holding the standing AERA/NSF funder
# disclaimer. It sits outside every .smpost div (it belongs to all of them), so
# it is pulled separately and appended to every generated bundle.
BOILERPLATE_MARKER <- "aera-nsf-disclaimer"

# --- Per-post editorial metadata not present in the qmd --------------------
# authors/tags/summary are firm-editorial content, not derivable from prose --
# filled in by hand, once, here. Extend as new posts are added to the qmd.
# Every author slug/tag slug must already exist in homepage_test's
# data/authors.yaml / data/tags.yaml -- the site's CI hard-fails otherwise.
POST_META <- list(
  "how-states-stack-up" = list(
    summary = "34,846 students were arrested at school in 2021-22 -- see how arrest and referral rates vary by state in the CRDC's most recent release.",
    tags = c("education", "policing")
  ),
  "arrests-declining-everywhere" = list(
    summary = "School-based arrests fell nationally in 2021-22, but the trend isn't uniform -- several states, including Kansas, are moving the opposite direction.",
    tags = c("education", "policing")
  ),
  "districts-most-arrests" = list(
    summary = "A small number of U.S. school districts report hundreds of arrests a year, with rates ten times the national average -- who they are and what that concentration means.",
    tags = c("education", "policing")
  ),
  "highest-arrest-rates" = list(
    summary = "The districts with the highest school arrest rates tend to be small, and disproportionately serve students in special education and American Indian/Alaska Native students.",
    tags = c("education", "policing")
  ),
  "coefficient-of-variation" = list(
    summary = "A short explainer on coefficient of variation -- the statistic behind why small student subgroups produce such volatile, unreliable arrest-rate estimates.",
    tags = c("education", "data")
  ),
  "arrest-rates-by-race" = list(
    summary = "Basic facts on how school-based arrest rates differ by race, and why American Indian/Alaska Native arrests are so concentrated in a handful of districts.",
    tags = c("education", "policing")
  ),
  "american-indian-arrests-models" = list(
    summary = "Seven districts account for over half of all American Indian student arrests nationally -- we use Bayesian models to ask how much of that spike is real versus reporting noise.",
    tags = c("education", "policing", "data")
  ),
  "misreported-zeros-descriptive" = list(
    summary = "125 large school districts reported exactly zero arrests in 2021-22 -- a share that's statistically implausible if the national arrest rate applied uniformly. Policy change, or under-reporting?",
    tags = c("education", "policing")
  ),
  "misreported-zeros-analytic" = list(
    summary = "Ten Bayesian models, one case study: what Paterson, NJ's own arrest history says about whether its reported zero for 2021-22 is real.",
    tags = c("education", "policing", "data")
  ),
  "estimating-rare-events" = list(
    summary = "How statisticians estimate rare events in small, fixed populations -- from Census poverty estimates to oil-spill risk -- and what applying that tradition to CRDC school arrests reveals.",
    tags = c("education", "policing", "data")
  )

  # "open-corrected-data" is deliberately WITHHELD, not deleted. Its prose stays
  # in social_media_posts.qmd and its .smpost div is untouched; a post with no
  # entry in this list is reported under "Skipped (no POST_META entry)" and is
  # never written to a bundle. It no longer fits the spirit of the series and
  # its ideas have been superseded elsewhere at Civilytics.
  #
  # To restore it: uncomment the entry below and add a comma to the
  # "estimating-rare-events" entry above. Nothing else is needed.
  #
  # ,"open-corrected-data" = list(
  #   summary = "We're publishing the cleaned, longitudinally-aligned CRDC arrest data and the ten-model uncertainty estimates behind it as open infrastructure -- so the next researcher doesn't have to redo the cleaning, alignment, and modeling from scratch.",
  #   tags = c("education", "policing", "data", "collaboration")
  # )
)

AUTHORS <- c("jared-knowles", "hannah-miller")

# --- Alt text ---------------------------------------------------------------
# Keyed by the image's bare filename -- the exact key render_body() has in hand.
# Filenames derive from chunk labels and are globally unique across posts, so no
# per-slug nesting is needed; a flat map also makes the completeness and
# staleness checks in preflight() one-liners over the whole document.
#
# Every image the parser finds MUST have a real entry here or the run aborts --
# there is no placeholder fallback. This site enforces descriptive alt text
# (homepage_test docs/AUTHORING.md: name what the image conveys, never "image
# of", never the filename, never a duplicate of the caption).
#
# The six marked "reused" are copied byte-for-byte from the already-published
# post content/newsletter/arrests-in-schools-starting-with-the-basics/index.md
# (lines 53, 55, 61, 69, 71, 87), which shares these exact figures. They were
# written and approved during that site's 205-image alt-text sweep; keeping them
# identical avoids two different descriptions of one image on the same site.
ALT_TEXT <- c(
  # -- how-states-stack-up (all three reused) --
  "socialmedia-arrest_chloropleth.png" = paste(
    "Choropleth map showing school-based arrests by state for the 2021-22 school",
    "year. Texas had the highest number of arrests at 5,387, while Maine reported",
    "only three."),
  "socialmedia-arrest_rate_chloropleth.png" = paste(
    "This choropleth map displays arrest rates per 1,000 students enrolled by state",
    "for the 2021-22 school year. Kansas had the highest arrest rate, with",
    "approximately one in every 194 students arrested or 5.15 per 1,000."),
  "socialmedia-state_arrest_nnh_map.png" = paste(
    "This choropleth map displays arrests per student by state, using data from the",
    "Civil Rights Data Collection. The most significant finding is that 1 in every",
    "194 students in Kansas was arrested."),

  # -- arrests-declining-everywhere (first two reused) --
  "socialmedia-national_trend.png" = paste(
    "This line graph, displaying data from the Civil Rights Data Collection (CRDC)",
    "between 2015-16 and 2021-22, shows a national decline in total arrests from",
    "62,020 to 34,846. Arrests have steadily decreased over the CRDC waves examined."),
  "socialmedia-national_arrest_rate_trend.png" = paste(
    "This line graph illustrates arrest rate trends across CRDC waves, plotting",
    "arrests per 1,000 students from 2015-16 to 2021-22. Arrest rates have steadily",
    "decreased, falling from 1.23 arrests per 1,000 students in 2015-16 to 0.72",
    "arrests per 1,000 students in 2021-22."),
  "socialmedia-select_state_arrest_trend.png" = paste(
    "Line chart of total school-based arrests in California and Kansas across the",
    "2015-16, 2017-18, and 2021-22 CRDC waves. California falls steadily from 3,424",
    "to 2,151 to 1,563, while Kansas holds near 500 for two waves, 521 then 565,",
    "before jumping to 2,413 and crossing above California despite enrolling roughly",
    "a twelfth as many students."),

  # -- districts-most-arrests --
  "socialmedia-national_lea_table.png" = paste(
    "Table of the 20 school districts reporting the most student arrests in 2021-22,",
    "with enrollment, arrest rate per 1,000, and arrest counts from the 2015-16 and",
    "2017-18 collections for comparison. DeKalb CUSD 428 in Illinois and Derby in",
    "Kansas top the list at 2,197 and 2,092 arrests on enrollments near 6,000, rates",
    "above 320 per 1,000, yet both reported zero arrests in 2015-16. The next",
    "highest district, Pinellas County, Florida, reports 601."),

  # -- highest-arrest-rates --
  "socialmedia-national_lea_table_higharrestrate.png" = paste(
    "Table of the 20 school districts with the highest student arrest rates in",
    "2021-22, showing each district's rate in all three CRDC waves alongside its",
    "enrollment and arrest counts. Rates run from 442.9 per 1,000 students in",
    "Pemiscot County Special School District, Missouri down to 35.4, against a",
    "national rate of 0.72. Most of these districts enroll fewer than 2,000 students,",
    "and many are special education districts or intermediate units."),

  # -- coefficient-of-variation --
  "socialmedia-cov_plot_decile_byraceeth.png" = paste(
    "Two panels of points with loess trend lines comparing the coefficient of",
    "variation in district arrest rates, on the left, with referral rates, on the",
    "right, across ten enrollment deciles, with a separate series for American",
    "Indian, Black, Hispanic, White, and all students. Variation is far higher for",
    "arrests than referrals at every district size and falls as enrollment grows, but",
    "American Indian students remain the least precisely measured group throughout,",
    "and the arrest panel ticks back up in the largest districts."),

  # -- arrest-rates-by-race (reused) --
  "socialmedia-arrests_concentration_by_sg.png" = paste(
    "Line graph showing cumulative arrest rates by race/ethnicity, plotted as a",
    "percentage of all arrests against the percentage of national student population.",
    "Black students experience arrest rates significantly higher than other groups,",
    "reaching 50% of all arrests before White and Hispanic students."),

  # -- american-indian-arrests-models --
  "socialmedia-am_districts_table.png" = paste(
    "Table of the seven school districts that together account for 51.8% of American",
    "Indian/Alaska Native student arrests nationally in 2021-22, listing arrests,",
    "referrals, American Indian enrollment, arrest rate per 1,000, and total district",
    "enrollment. Rapid City, South Dakota reports the most at 96 arrests among 2,038",
    "American Indian students, while Derby, Kansas reports 28 among just 58, a rate of",
    "482.76 per 1,000. Nationally only 529 such arrests were reported."),
  "socialmedia-am_districts_table_3yr.png" = paste(
    "Table of American Indian/Alaska Native student arrests and enrollment in those",
    "same seven districts across the 2015-16, 2017-18, and 2021-22 CRDC waves. Every",
    "district reports its highest count in the most recent wave while its American",
    "Indian enrollment holds flat or falls: Zuni rises from 9 to 24 to 67, Derby from",
    "0 to 2 to 28, and Douglas County and Sioux Falls report their first arrests, 15",
    "and 13, after two waves of zero."),
  "socialmedia-arrests_model_comparison_am.png" = paste(
    "Four density plots of predicted American Indian student arrests for Sioux Falls",
    "School District 49-5 in South Dakota, arranged as one-year models on the left and",
    "three-year models on the right, each shown without and with covariates. A bright",
    "blue point marks the 13 arrests actually reported, with its frequentist interval.",
    "The one-year models place that count comfortably inside their range, but both",
    "three-year models concentrate well below it, peaking near 1 and 4 arrests."),

  # -- misreported-zeros-descriptive --
  "socialmedia-expected_arrest_table.png" = paste(
    "Table comparing how many districts reported at least one arrest in 2021-22 with",
    "how many would be expected to at the national rate of 0.71 arrests per 1,000",
    "students, grouped into four enrollment bands. Every district enrolling 10,000 or",
    "more students would be expected to report an arrest, yet only 263 of 490 in the",
    "10,000 to 19,999 band and 251 of 376 in the 20,000-plus band actually did."),
  "socialmedia-big0_example_dist_table.png" = paste(
    "Table of arrests reported by Paterson Public School District, New Jersey across",
    "three CRDC waves. Paterson reported 47 arrests in 2015-16 and 11 in 2017-18, then",
    "zero in 2021-22, while its grade 7 to 12 enrollment held between 17,401 and",
    "19,468 throughout."),

  # -- misreported-zeros-analytic --
  "socialmedia-big0_missing_arrests_table.png" = paste(
    "Table of predicted arrests from ten Bayesian models for the 100 largest districts",
    "that reported zero arrests in 2021-22, listing each model's estimation sample,",
    "covariates, median prediction, and 95% interval against a reported total of zero",
    "and a naive ceiling of 2,645. The four models using only the most recent wave",
    "predict between 27 and 139 arrests; the six drawing on three CRDC waves predict",
    "between 810 and 1,704. Within the three-wave models, adding a referral-rate",
    "covariate roughly halves the estimate, from about 1,700 to about 820. No model's",
    "interval includes zero."),
  "socialmedia-paterson_model_comparison.png" = paste(
    "Interval plot of predicted arrests for Paterson Public School District, New",
    "Jersey from ten Bayesian models, split into four panels by baseline versus",
    "covariate and one-year versus three-year data, each model shown against the",
    "frequentist rule-of-three interval in gray. The one-year models center on zero,",
    "while every three-year model centers above it, near 11 or 12 arrests without",
    "covariates and near 3 or 4 with them."),
  # -- estimating-rare-events --
  "socialmedia-rare_events_ridges.png" = paste(
    "Ridge plot comparing posterior predicted school arrest rates per 1,000 students",
    "in Mobile County and Jefferson County, Alabama, with one row per student group",
    "and a diamond marking each district's reported rate. Mobile's distribution for",
    "Black students centers near 8 arrests per 1,000 and does not come close to",
    "Jefferson's, which sits at zero. For American Indian and Hispanic students",
    "Mobile's distributions are wide and spiky, because only a few hundred students",
    "are enrolled and each additional arrest moves the rate sharply, so those gaps",
    "reach down toward Jefferson's and stay unresolved."),

  "socialmedia-zero_arrest_counts_draws.png" = paste(
    "Four panels of histograms showing all 500 posterior draws of predicted arrests",
    "for Paterson, one panel per combination of one-year or three-year data and",
    "baseline or covariate models. Both one-year panels put 50% or more of their draws",
    "on zero arrests, whereas the three-year baseline models spread across 5 to 16",
    "arrests and the three-year covariate models peak at 3 to 5, giving zero almost no",
    "weight.")
)

# --- Parsing -----------------------------------------------------------

#' Split the qmd into one record per `::: {.smpost ...} ... :::` block.
#' Returns a list of lists: attrs (named character vector) and body_lines
#' (the raw lines strictly between the opening and closing fence).
parse_smposts <- function(lines) {
  starts <- grep('^::: \\{\\.smpost\\s', lines)
  ends <- grep('^:::$', lines)
  stopifnot(length(starts) == length(ends))

  attr_pattern <- function(name) sprintf('%s="([^"]*)"', name)
  extract_attr <- function(line, name) {
    m <- regmatches(line, regexec(attr_pattern(name), line))[[1]]
    if (length(m) < 2) NA_character_ else m[2]
  }

  Map(function(s, e) {
    header <- lines[s]
    attrs <- c(
      slug = extract_attr(header, "slug"),
      title = extract_attr(header, "title"),
      date = extract_attr(header, "date"),
      status = extract_attr(header, "status"),
      series = extract_attr(header, "series")
    )
    list(attrs = attrs, body_lines = lines[(s + 1):(e - 1)])
  }, starts, ends)
}

#' Walk a post's body in document order, emitting an ordered list of content
#' events: prose (POST-PROSE blocks + trailing footnote definitions) and
#' images (figures/tables the post's chunks produce), interleaved the same
#' way they appear in the qmd -- this preserves the intended "text, then
#' figure, then more text" reading flow rather than dumping images at the end.
extract_content_events <- function(body_lines) {
  events <- list()
  i <- 1
  n <- length(body_lines)
  in_prose <- FALSE
  prose_buf <- character(0)

  flush_prose <- function() {
    if (length(prose_buf) > 0 && any(nzchar(trimws(prose_buf)))) {
      events[[length(events) + 1]] <<- list(type = "prose", text = paste(prose_buf, collapse = "\n"))
    }
    prose_buf <<- character(0)
  }

  while (i <= n) {
    line <- body_lines[i]

    if (grepl("^<!-- POST-PROSE", line)) {
      in_prose <- TRUE
      i <- i + 1
      next
    }
    if (grepl("^<!-- /POST-PROSE -->", line)) {
      in_prose <- FALSE
      flush_prose()
      i <- i + 1
      next
    }
    if (in_prose) {
      prose_buf <- c(prose_buf, line)
      i <- i + 1
      next
    }

    # Footnote definitions live outside POST-PROSE blocks, after the chunk
    # that uses them -- keep them as their own prose event in document order.
    # Both Pandoc and Goldmark allow lazy continuation, so a definition runs
    # until the next blank line: consume the whole block, not just the matched
    # line. Emitting only the first line silently truncated every wrapped
    # footnote (post7-1, post8-1, post9-1, post9-2 -- 11 dropped lines).
    if (grepl("^\\[\\^[^]]+\\]:", line)) {
      j <- i
      while (j < n && nzchar(trimws(body_lines[j + 1]))) j <- j + 1
      events[[length(events) + 1]] <- list(
        type = "prose",
        text = paste(body_lines[i:j], collapse = "\n")
      )
      i <- j + 1
      next
    }

    # Fenced R chunk: scan its full body as one unit for whichever image
    # signal it carries. An explicit img_path <- "..." assignment (table PNGs
    # saved by hand, then knitr::include_graphics()) takes priority over the
    # auto-capture heuristic (#| label: X ... grid::grid.draw(...), which
    # knitr saves to export/figures/socialmedia-X-1.png via this document's
    # fig.path/dev options). Scanning the whole chunk in one pass -- rather
    # than line-by-line -- avoids skipping past an img_path line that sits
    # after the #| label: line in the same chunk.
    if (grepl("^```\\{r", line)) {
      close_idx <- which(body_lines[(i + 1):n] == "```")[1] + i
      chunk <- body_lines[i:close_idx]

      # #| include: false chunks are exploratory/superseded -- knitr never
      # renders their output into the document, so this script shouldn't
      # either, even if they still contain a grid.draw() or img_path (e.g.
      # cov_plot_quintile_total / cov_plot_decile_total, kept only to build
      # shared data for the chunk that supersedes them).
      included <- !any(grepl("^#\\| include: false", chunk))

      path_hits <- if (included) {
        hits <- regmatches(chunk, regexec('img_path <- "(export/figures/socialmedia-[^"]+\\.png)"', chunk))
        Filter(function(x) length(x) == 2, hits)
      } else {
        list()
      }

      if (length(path_hits) > 0) {
        events[[length(events) + 1]] <- list(type = "image", path = path_hits[[1]][2])
      } else if (included && any(grepl("grid::grid\\.draw\\(", chunk))) {
        label_line <- grep("^#\\| label: (\\S+)", chunk, value = TRUE)
        if (length(label_line) > 0) {
          label <- sub("^#\\| label: (\\S+).*", "\\1", label_line[1])
          events[[length(events) + 1]] <- list(
            type = "image",
            path = sprintf("%s/socialmedia-%s-1.png", FIGURES_DIR, label)
          )
        }
      }
      i <- close_idx + 1
      next
    }

    i <- i + 1
  }
  flush_prose()
  events
}

#' Alt text for one image, or abort. There is deliberately no fallback and no
#' placeholder: this site enforces real, descriptive alt text
#' (homepage_test docs/AUTHORING.md), and a placeholder that renders is a
#' placeholder that ships. preflight() catches a missing entry before anything
#' is cloned or written; this is the last line of defence.
alt_for <- function(fname) {
  txt <- ALT_TEXT[[fname]]
  if (is.null(txt) || !nzchar(trimws(txt))) {
    stop(sprintf(
      "No alt text for '%s'.\n  Add an entry to ALT_TEXT in scripts/publish_newsletter.R.",
      fname), call. = FALSE)
  }
  txt
}

#' Render content events to a markdown body. Native markdown image syntax with
#' the file at the bundle root is what homepage_test's docs/AUTHORING.md
#' prescribes for new posts -- its render-image.html hook picks those up as page
#' resources and generates the WebP derivatives and lightbox attributes. The
#' {{< figure src="images/..." >}} form in older posts there is Substack-migration
#' legacy; do not copy it.
render_body <- function(events) {
  parts <- vapply(events, function(ev) {
    if (ev$type == "prose") {
      ev$text
    } else {
      fname <- basename(ev$path)
      sprintf("![%s](%s)", alt_for(fname), fname)
    }
  }, character(1))
  paste(parts, collapse = "\n\n")
}

#' Pull one named POST-PROSE block from anywhere in the qmd -- including blocks
#' outside every .smpost div, which extract_content_events() never sees. Used
#' for standing boilerplate that belongs on every post, so the qmd stays the
#' single source of truth for prose rather than the text being duplicated here.
extract_marked_prose <- function(lines, name) {
  s <- grep(sprintf("^<!-- POST-PROSE:\\s*%s\\s*-->$", name), lines)
  if (length(s) != 1L) {
    stop(sprintf("Expected exactly one '<!-- POST-PROSE: %s -->' marker in %s, found %d",
                 name, QMD_PATH, length(s)), call. = FALSE)
  }
  e <- grep("^<!-- /POST-PROSE -->", lines)
  e <- e[e > s][1]
  if (is.na(e)) stop(sprintf("Unclosed POST-PROSE block '%s'", name), call. = FALSE)
  txt <- trimws(paste(lines[(s + 1):(e - 1)], collapse = "\n"))
  if (!nzchar(txt)) stop(sprintf("POST-PROSE block '%s' is empty", name), call. = FALSE)
  txt
}

# --- Preflight -------------------------------------------------------------

#' Reject alt strings that are technically present but useless. Mirrors the
#' classifier in homepage_test's scripts/audit_newsletter_alt.py so the two
#' tools agree on what counts as real alt text. (That auditor only matches
#' {{< figure >}} and <img>, so it will not see the native markdown images this
#' script emits -- this check is the substitute, not a duplicate.)
alt_is_placeholder <- function(txt) {
  low <- tolower(trimws(txt))
  grepl("^(todo|fixme|xxx|tk\\b|describe )", low) ||
    low %in% c("image", "images", "photo", "picture", "img", "screenshot",
               "graphic", "chart", "table", "figure", "map") ||
    grepl("^(photo of|picture of|image of)", low) ||
    grepl("\\.(png|jpe?g|gif|webp|svg)$", low)
}

#' Every check that can be made without touching the network, made once, over
#' all posts, before anything is cloned or written -- so a single missing alt
#' string aborts the run rather than publishing 10 of 11. Returns the slugs
#' that will be published (consumed by validate_links()).
preflight <- function(posts) {
  pub <- Filter(function(p) !is.null(POST_META[[p$attrs["slug"]]]), posts)
  slugs <- vapply(pub, function(p) unname(p$attrs["slug"]), character(1))

  # Future dates: homepage_test's config/_default/hugo.toml sets
  # buildFuture = false, so a future-dated post is silently NOT built -- and
  # any cross-link into it then fails that repo's internal link check, which
  # hard-fails the CI job. Both failures are invisible from this side.
  dates <- as.Date(vapply(pub, function(p) unname(p$attrs["date"]), character(1)))
  if (any(is.na(dates))) {
    stop("Unparseable date= attribute on: ",
         paste(slugs[is.na(dates)], collapse = ", "), call. = FALSE)
  }
  future <- dates > Sys.Date()
  if (any(future)) {
    stop("Post date(s) in the future; homepage_test sets buildFuture = false, so ",
         "these pages will not be built and any link to them fails CI:\n  ",
         paste(sprintf("%s (%s)", slugs[future], dates[future]), collapse = "\n  "),
         call. = FALSE)
  }

  needed <- unique(unlist(lapply(pub, function(p) {
    ev <- extract_content_events(p$body_lines)
    vapply(Filter(function(e) e$type == "image", ev),
           function(e) basename(e$path), character(1))
  }), use.names = FALSE))

  missing <- setdiff(needed, names(ALT_TEXT))
  have    <- intersect(needed, names(ALT_TEXT))
  weak    <- have[vapply(ALT_TEXT[have], alt_is_placeholder, logical(1))]
  # A literal '[' or ']' would terminate the ![...] span early.
  unsafe  <- have[grepl("[][]", ALT_TEXT[have])]
  stale   <- setdiff(names(ALT_TEXT), needed)

  problems <- c(
    if (length(missing)) sprintf("missing alt text: %s", paste(missing, collapse = ", ")),
    if (length(weak))    sprintf("placeholder alt text: %s", paste(weak, collapse = ", ")),
    if (length(unsafe))  sprintf("alt text contains [ or ]: %s", paste(unsafe, collapse = ", "))
  )
  if (length(problems)) stop(paste(problems, collapse = "\n  "), call. = FALSE)
  if (length(stale)) {
    warning("ALT_TEXT has entries for images no longer produced: ",
            paste(stale, collapse = ", "), call. = FALSE)
  }

  message(sprintf("Preflight OK: %d post(s), %d image(s), all alt text present",
                  length(pub), length(needed)))
  slugs
}

#' Abort if a post links to a /newsletter/ slug that will not exist once this
#' push lands. homepage_test's CI runs scripts/check_internal_links.py on every
#' push to dev and hard-fails on a link to a missing page, so a typo here breaks
#' that repo's build rather than this one's.
validate_links <- function(md, slug, known) {
  hits <- regmatches(md, gregexpr("\\]\\(/newsletter/[a-z0-9-]+/\\)", md))[[1]]
  if (!length(hits)) return(invisible())
  targets <- unique(sub("^\\]\\(/newsletter/([a-z0-9-]+)/\\)$", "\\1", hits))
  bad <- setdiff(targets, known)
  if (length(bad)) {
    stop(sprintf(paste0("%s links to newsletter slug(s) not being published: %s\n",
                        "  homepage_test CI hard-fails on links to pages that do not exist."),
                 slug, paste(bad, collapse = ", ")), call. = FALSE)
  }
  if (slug %in% targets) warning(sprintf("%s links to itself", slug), call. = FALSE)
  invisible()
}

#' YAML frontmatter for a bundle. yaml::as.yaml keeps quoting/escaping of the
#' free-text fields (titles with colons, summaries with apostrophes) correct
#' without hand-rolling it.
#'
#' Two things it gets wrong for Hugo, both handled here:
#'  - Logicals serialize as YAML 1.1 `yes`/`no`. Every one of the 60 posts
#'    already on homepage_test writes `draft: false`, and Hugo's YAML parser
#'    follows the 1.2 core schema where `no` is a plain string, not a boolean.
#'    Emit the bare token instead.
#'  - A date would be quoted ('2026-08-07'); the site writes dates unquoted.
#'  - A length-1 character vector collapses to a scalar (`tags: education`)
#'    rather than a one-item sequence, so wrap the list-valued fields.
render_frontmatter <- function(attrs, meta) {
  verbatim <- function(x) structure(x, class = "verbatim")
  fm <- list(
    title = unname(attrs["title"]),
    date = verbatim(unname(attrs["date"])),
    authors = as.list(AUTHORS),
    summary = meta$summary,
    tags = as.list(meta$tags),
    draft = verbatim("false")
  )
  paste0("---\n", yaml::as.yaml(fm), "---\n")
}

# --- Lock-in check -------------------------------------------------------

#' TRUE if content/newsletter/<slug>/index.md already exists on origin/main.
#' Uses ls-remote + a bare fetch of just that ref so this never requires a
#' full clone just to answer "has this shipped".
slug_is_live <- function(bare_repo_dir, slug) {
  path <- sprintf("content/newsletter/%s/index.md", slug)
  ok <- system2("git", shQuote(c("-C", bare_repo_dir, "cat-file", "-e",
                                 sprintf("origin/main:%s", path))),
                stdout = FALSE, stderr = FALSE)
  ok == 0
}

# --- Main ------------------------------------------------------------------

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  dry_run <- "--dry-run" %in% args

  stopifnot(nzchar(Sys.which("git")))
  lines <- readLines(QMD_PATH, warn = FALSE)
  posts <- parse_smposts(lines)

  message(sprintf("Parsed %d posts from %s", length(posts), QMD_PATH))

  # Everything checkable offline, checked before the clone: alt-text
  # completeness and quality, future dates, stale ALT_TEXT entries.
  publishable <- preflight(posts)

  # Standing funder disclaimer, carried from the qmd rather than duplicated
  # here -- the grant number and wording are funder-sensitive and already live
  # in two places (the qmd and the published post that first used it).
  disclaimer <- extract_marked_prose(lines, BOILERPLATE_MARKER)

  # Ephemeral clone -- see the file header for why this is a fresh clone
  # (not a worktree of the maintainer's personal homepage_test checkout).
  clone_dir <- tempfile("homepage-test-publish-")
  # shQuote() every argument: system2() pastes command and args into a single
  # string and hands it to system(), which runs it through /bin/sh. Unquoted
  # shell metacharacters are therefore interpreted, not passed through -- the
  # parenthesised slug list in the commit message below died with
  # `sh: 1: Syntax error: "(" unexpected`. system2() quotes the command but
  # never the arguments; that is the caller's job.
  run <- function(cmd, args, dir = clone_dir) {
    message("Running: git ", paste(c(cmd, args), collapse = " "))
    status <- system2("git", shQuote(c(if (!is.null(dir)) c("-C", dir), cmd, args)))
    if (status != 0) stop("git command failed (status ", status, ")")
  }

  if (!dry_run) {
    dir.create(clone_dir)
    on.exit(unlink(clone_dir, recursive = TRUE), add = TRUE)
    message("Cloning homepage_test (branch dev)...")
    status <- system2("git", shQuote(c("clone", "--branch", "dev", "--single-branch",
                                       HOMEPAGE_REMOTE, clone_dir)))
    if (status != 0) stop("git clone failed")
    run("fetch", c("origin", "main"))
  }

  changed <- character(0)
  skipped_live <- character(0)
  skipped_no_meta <- character(0)

  for (post in posts) {
    slug <- post$attrs["slug"]

    if (!dry_run && slug_is_live(clone_dir, slug)) {
      skipped_live <- c(skipped_live, slug)
      next
    }

    meta <- POST_META[[slug]]
    if (is.null(meta)) {
      skipped_no_meta <- c(skipped_no_meta, slug)
      next
    }

    events <- extract_content_events(post$body_lines)
    body <- render_body(events)
    frontmatter <- render_frontmatter(post$attrs, meta)
    # Goldmark hoists footnote definitions into a trailing <section
    # class="footnotes">, so the disclaimer renders as the last body paragraph
    # even on posts whose source ends with a footnote -- matching how it appears
    # on the already-published post that first carried it.
    bundle_md <- paste0(frontmatter, "\n", body, "\n\n", disclaimer, "\n")

    # In a real run a link to an already-live post is fine too, so widen the
    # accepted set with what is already on the site.
    known <- if (dry_run) publishable else union(
      publishable, list.files(file.path(clone_dir, "content", "newsletter")))
    validate_links(bundle_md, slug, known)

    # Catches a placeholder typed into *prose* in the qmd, which preflight()
    # does not inspect, plus any empty-alt image that slipped past alt_for().
    if (grepl("TODO|FIXME|!\\[\\s*\\]\\(", bundle_md)) {
      stop("placeholder or empty alt text reached the bundle for ", slug, call. = FALSE)
    }

    image_paths <- vapply(Filter(function(e) e$type == "image", events),
                           function(e) e$path, character(1))

    if (dry_run) {
      message(sprintf("\n--- %s (%d images) ---", slug, length(image_paths)))
      cat(bundle_md)
      next
    }

    bundle_dir <- file.path(clone_dir, "content", "newsletter", slug)
    dir.create(bundle_dir, recursive = TRUE, showWarnings = FALSE)

    # Drop figures this post no longer references. Without this, renaming a
    # chunk (or dropping knitr's "-1" suffix) leaves the old PNG behind forever
    # -- dead weight in a repo with no LFS, and a second copy of a figure that
    # is supposed to have exactly one. Scoped to socialmedia-*.png so nothing
    # else in the bundle is touched.
    keep <- basename(image_paths)
    stale <- setdiff(list.files(bundle_dir, pattern = "^socialmedia-.*\\.png$"), keep)
    if (length(stale)) {
      message(sprintf("  pruning %d stale figure(s) from %s: %s",
                      length(stale), slug, paste(stale, collapse = ", ")))
      unlink(file.path(bundle_dir, stale))
    }

    writeLines(bundle_md, file.path(bundle_dir, "index.md"))
    for (p in image_paths) {
      src <- p # already repo-relative to crdc-arrests' working directory
      if (file.exists(src)) {
        file.copy(src, file.path(bundle_dir, basename(src)), overwrite = TRUE)
      } else {
        warning(sprintf("Missing image for %s: %s (render social_media_posts.qmd first)", slug, src))
      }
    }
    changed <- c(changed, slug)
  }

  if (dry_run) {
    message("\n--- Skipped (already live on main) ---")
    print(skipped_live)
    message("--- Skipped (no POST_META entry) ---")
    print(skipped_no_meta)
    return(invisible())
  }

  if (length(changed) == 0) {
    message("Nothing to publish -- all posts already live or unchanged.")
    return(invisible())
  }

  run("add", c("-A"))
  unchanged <- system2("git", shQuote(c("-C", clone_dir, "diff", "--cached", "--quiet"))) == 0
  if (unchanged) {
    message("No content changes to publish.")
    return(invisible())
  }
  # Short subject, slugs in the body: git joins repeated -m as paragraphs. The
  # old single-line form put all 11 slugs in the subject, which made for a
  # ~400-character summary line in the site's history.
  run("commit", c("-m", sprintf("feat(newsletter): publish %d CRDC arrests post%s",
                                length(changed), if (length(changed) == 1) "" else "s"),
                  "-m", paste(sprintf("- %s", changed), collapse = "\n")))
  run("push", c("origin", "dev"))
  message(sprintf(
    "Published %d post(s) to staging: %s",
    length(changed),
    paste0("https://pages.civilytics.org/homepage_test/newsletter/", changed, "/", collapse = "\n  ")
  ))
  message("Skipped (already live on main): ", paste(skipped_live, collapse = ", "))
}

main()
