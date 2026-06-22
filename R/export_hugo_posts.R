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
