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
