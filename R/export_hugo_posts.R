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
  # Strip DRIFT author-scaffolding comments (kept in qmd, must not ship in bundles).
  body <- gsub("<!--\\s*/?DRIFT.*?-->[ \\t]*\\n?", "", body, perl = TRUE)
  writeLines(paste0(hugo_front_matter(post), body), file.path(dir, "index.md"))
  dir
}

export_hugo_posts <- function(md_path, out_root = "export/hugo/posts", repo_root = ".") {
  md <- paste(readLines(md_path, warn = FALSE), collapse = "\n")
  posts <- parse_smposts(md)
  vapply(posts, write_hugo_bundle, character(1), out_root = out_root, repo_root = repo_root)
}
