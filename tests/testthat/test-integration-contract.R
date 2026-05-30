test_that("arrest_summary contract: intervals ordered, rates in [0,1]", {
  draws_con <- fixture_draws_con(); on.exit(DBI::dbDisconnect(draws_con, shutdown=TRUE))
  api_path <- tempfile(fileext=".duckdb")
  build_arrest_summary(draws_con, fixture_enroll_lookup(), fixture_district_dim(), api_path)

  acon <- DBI::dbConnect(duckdb::duckdb(), dbdir=api_path, read_only=TRUE)
  on.exit(DBI::dbDisconnect(acon, shutdown=TRUE), add=TRUE)
  s <- DBI::dbGetQuery(acon, "SELECT * FROM arrest_summary")

  for (p in c(50, 80, 95)) {
    lo <- s[[sprintf("count_lower_%d", p)]]
    hi <- s[[sprintf("count_upper_%d", p)]]
    rlo <- s[[sprintf("rate_lower_%d", p)]]
    rhi <- s[[sprintf("rate_upper_%d", p)]]

    # The interval must be internally valid (lower <= upper) for all masses.
    expect_true(all(lo <= hi), info = paste("lower<=upper", p))

    # For p >= 0.80, the HPD window is wide enough that it reliably brackets the
    # interpolated median even for n=10 draws.  At p=0.50 with n=10 discrete
    # uniform draws {0..9}, ceil(0.5*10)=5 draws give upper_50=4 while the
    # DuckDB interpolated median is 4.5 — so lo<=median<=hi does NOT hold for
    # the 50% mass on this fixture without being a contract violation (it is a
    # known property of discrete HPD + continuous median interpolation at small
    # n).  We therefore test median-bracketing only for the broader intervals.
    if (p >= 80) {
      expect_true(all(lo <= s$count_median), info = paste("lower<=median", p))
      expect_true(all(hi >= s$count_median), info = paste("upper>=median", p))
    }

    # Rates must lie in [0, 1].
    expect_true(all(rlo >= 0), info = paste("rate_lower >= 0 at", p))
    expect_true(all(rhi <= 1), info = paste("rate_upper <= 1 at", p))
  }

  # Wider mass must contain narrower mass (nesting invariant).
  expect_true(all(s$count_lower_95 <= s$count_lower_80))
  expect_true(all(s$count_upper_95 >= s$count_upper_80))
})
