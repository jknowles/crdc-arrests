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
