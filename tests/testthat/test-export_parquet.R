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

test_that("export_draws_parquet clears orphan shards on re-export (no duplicate rows)", {
  # Regression guard for the orphan-shard parquet-duplication bug: re-running the
  # export over a non-emptied out_dir used to leave higher-indexed shard files
  # behind (OVERWRITE_OR_IGNORE overwrites same-named files but never deletes
  # files the new run does not recreate). Those orphans were an exact-duplicate
  # subset of the data, which double-counted whole districts downstream and broke
  # the supplement `browardsmallgroups` per-group difference
  # (pred[RACE=="WH"] became length 2 -> summarize() "must be size 1, not 2").
  con <- fixture_draws_con(); on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  out <- file.path(tempfile(), "parquet")
  export_draws_parquet(con, out_dir = out)

  count_rows <- function(dir) {
    rcon <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    on.exit(DBI::dbDisconnect(rcon, shutdown = TRUE))
    DBI::dbGetQuery(rcon, sprintf(
      "SELECT COUNT(*) n FROM read_parquet('%s/**/*.parquet', hive_partitioning=true)",
      dir))$n
  }
  expect_equal(count_rows(out), 20)  # fixture has 20 rows

  # Plant an orphan: a copy of a real shard under an index the next run will not
  # overwrite -- exactly what a prior, larger export leaves behind.
  shard  <- list.files(out, recursive = TRUE, pattern = "\\.parquet$",
                       full.names = TRUE)[1]
  orphan <- file.path(dirname(shard), "data_99.parquet")
  file.copy(shard, orphan)
  expect_true(file.exists(orphan))
  expect_equal(count_rows(out), 40)  # the bug mechanism: orphan inflates the count

  # Re-export: the clear-dir step must remove the orphan so counts match source.
  export_draws_parquet(con, out_dir = out)
  expect_false(file.exists(orphan))  # out_dir was cleared
  expect_equal(count_rows(out), 20)  # no duplication
})

test_that("export_draws_parquet rejects out_dir containing a single quote", {
  con <- fixture_draws_con(); on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  expect_error(export_draws_parquet(con, out_dir = "/tmp/bad'path"), class = "simpleError")
})

test_that("export_draws_parquet chunks per model_id (all models exported)", {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  draws <- rbind(
    data.frame(LEAID="0100005", LEA_STATE="AL", YEAR="21-22", RACE="BL", SEX="M",
               pred=0:9, draw_id=1:10, model_id="nat_m2_mod",
               subgroup_id="nat_m2_mod", stringsAsFactors=FALSE),
    data.frame(LEAID="0100006", LEA_STATE="AL", YEAR="21-22", RACE="WH", SEX="F",
               pred=rep(5L,10), draw_id=1:10, model_id="sg_m2_mod",
               subgroup_id="sg_m2_mod", stringsAsFactors=FALSE)
  )
  DBI::dbWriteTable(con, "predicted_draws", draws)
  out <- file.path(tempfile(), "pq")
  export_draws_parquet(con, out_dir = out)
  files <- list.files(out, recursive = TRUE, pattern = "\\.parquet$")
  expect_true(any(grepl("model_id=nat_m2_mod", files)))
  expect_true(any(grepl("model_id=sg_m2_mod", files)))
  rcon <- DBI::dbConnect(duckdb::duckdb()); on.exit(DBI::dbDisconnect(rcon, shutdown=TRUE), add=TRUE)
  n <- DBI::dbGetQuery(rcon, sprintf(
    "SELECT COUNT(*) n FROM read_parquet('%s/**/*.parquet', hive_partitioning=true)", out))$n
  expect_equal(n, 20)
})
