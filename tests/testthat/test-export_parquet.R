test_that("export_draws_parquet writes Hive-partitioned parquet by model/year/state", {
  con <- fixture_draws_con(); on.exit(DBI::dbDisconnect(con, shutdown=TRUE))
  out <- file.path(tempfile(), "parquet")
  export_draws_parquet(con, out_dir = out)

  # Hive partition dirs exist
  expect_true(dir.exists(out))
  files <- list.files(out, recursive = TRUE, pattern = "\\.parquet$")
  expect_true(length(files) >= 1)
  expect_true(any(grepl("model_id=nat_m2_mod", files)))
  expect_true(any(grepl("YEAR=21-22", files)))
  expect_true(any(grepl("LEA_STATE=AL", files)))

  # round-trip: read back and count rows == source
  rcon <- DBI::dbConnect(duckdb::duckdb(), dbdir=":memory:")
  on.exit(DBI::dbDisconnect(rcon, shutdown=TRUE), add=TRUE)
  n <- DBI::dbGetQuery(rcon, sprintf(
    "SELECT COUNT(*) n FROM read_parquet('%s/**/*.parquet', hive_partitioning=true)", out))$n
  expect_equal(n, 20)  # fixture has 20 rows

  # intra-shard rows must be sorted by (LEAID, RACE, SEX) for row-group pruning
  # list.files pattern matches basename only, so filter full paths separately
  all_parquet <- list.files(out, recursive = TRUE, pattern = "\\.parquet$",
                             full.names = TRUE)
  shard <- all_parquet[grepl("model_id=nat_m2_mod", all_parquet) &
                         grepl("LEA_STATE=AL", all_parquet)]
  expect_true(length(shard) >= 1)
  rcon2 <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(rcon2, shutdown = TRUE), add = TRUE)
  ord <- DBI::dbGetQuery(rcon2, sprintf(
    "SELECT LEAID, RACE, SEX FROM read_parquet('%s')", shard[1]))
  expect_equal(ord, ord[order(ord$LEAID, ord$RACE, ord$SEX), ], ignore_attr = TRUE)
})

test_that("export_draws_parquet rejects out_dir containing a single quote", {
  con <- fixture_draws_con(); on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  expect_error(export_draws_parquet(con, out_dir = "/tmp/bad'path"), class = "simpleError")
})
