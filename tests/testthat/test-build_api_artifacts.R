test_that("build_draws_parquet exports every model from a db path", {
  dbpath <- fixture_draws_db_file(c("nat_m2_mod", "sg_m2_mod"))
  on.exit(unlink(dbpath), add = TRUE)
  out <- file.path(tempfile(), "parquet")
  res <- build_draws_parquet(dbpath, out)
  expect_equal(res, out)
  files <- list.files(out, recursive = TRUE, pattern = "\\.parquet$")
  expect_true(any(grepl("model_id=nat_m2_mod", files)))
  expect_true(any(grepl("model_id=sg_m2_mod", files)))
})

test_that("build_api_db writes arrest_summary, state_summary, district_dim, meta", {
  dbpath <- fixture_draws_db_file("nat_m2_mod")
  on.exit(unlink(dbpath), add = TRUE)
  api <- tempfile(fileext = ".duckdb")
  res <- build_api_db(dbpath, api, fixture_enroll_lookup(), fixture_district_dim(),
                      data_release = "test-release")
  expect_equal(res, api)
  acon <- DBI::dbConnect(duckdb::duckdb(), dbdir = api, read_only = TRUE)
  on.exit(DBI::dbDisconnect(acon, shutdown = TRUE), add = TRUE)
  tbls <- DBI::dbListTables(acon)
  expect_true(all(c("arrest_summary", "state_summary", "district_dim", "meta") %in% tbls))
  rel <- DBI::dbGetQuery(acon, "SELECT data_release FROM meta")$data_release
  expect_equal(rel, "test-release")
})

test_that("duckdb_mem_limit_gb returns a positive integer", {
  expect_true(duckdb_mem_limit_gb() >= 8)
})
