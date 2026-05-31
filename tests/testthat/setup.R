# Sourced automatically by testthat::test_dir before tests run.
# Guard with file.exists so the suite works as files are added task-by-task.
for (f in c("district_dim.R", "summarize_draws.R", "export_parquet.R")) {
  p <- file.path("..", "..", "R", f)
  if (file.exists(p)) source(p)
}
