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
