test_that("check_read_contract flags runtime store reads but ignores comments", {
  clean <- tempfile(fileext = ".qmd")
  writeLines(c("```{r}", "# old: targets::tar_read(x)",
               "y <- read_stage_df('stages/inputs/a.parquet')", "```"), clean)
  expect_equal(check_read_contract(clean), character(0))

  dirty <- tempfile(fileext = ".qmd")
  writeLines(c("z <- targets::tar_read(x)"), dirty)
  expect_equal(check_read_contract(dirty), dirty)
})

test_that("no in-scope doc reads the targets store at render time", {
  root <- file.path("..", "..")   # tests run with cwd = tests/testthat
  docs <- c("supplement.qmd", "social_media_posts.qmd",
            "annual_descriptives_template.qmd",
            "model_descriptives_template.qmd", "white_paper.qmd")
  paths <- file.path(root, docs)
  paths <- paths[file.exists(paths)]
  expect_equal(check_read_contract(paths), character(0))
})
