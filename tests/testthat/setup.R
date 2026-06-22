# Sourced automatically by testthat::test_dir before tests run.
# Guard with file.exists so the suite works as files are added task-by-task.
for (f in c("funs.R", "district_dim.R", "summarize_draws.R",
            "export_parquet.R", "build_api_artifacts.R",
            "model_registry.R", "crdc_path.R", "stage_artifacts.R",
            "paper_figures.R", "check_read_contract.R",
            "export_hugo_posts.R", "branding.R")) {
  p <- file.path("..", "..", "R", f)
  if (file.exists(p)) source(p)
}
