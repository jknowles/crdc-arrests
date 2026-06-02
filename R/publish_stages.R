#' Upload export/stages/ to the HF dataset under stages/, pinned to a release.
#'
#' Mirrors scripts/publish_hf.R / scripts/publish_db.R (the Subsystem-1 pattern).
#' Requires `hf`/`huggingface-cli` on PATH + HF_TOKEN in the environment. Returns
#' the remote base URL. Does NOT push unless `execute = TRUE` (dry-run by default).
publish_stages <- function(local_dir = "export/stages",
                           repo = "civilytics/crdc-school-arrest-rates",
                           revision = "civilytics-crdc-arrests-2025.1",
                           message = "Publish staged intermediate artifacts",
                           execute = FALSE) {
  stopifnot(dir.exists(local_dir))
  cmd <- sprintf(
    "hf upload %s %s stages --repo-type=dataset --revision=%s --commit-message=%s",
    shQuote(repo), shQuote(local_dir), shQuote(revision), shQuote(message))
  if (!execute) {
    message("[dry-run] ", cmd)
    return(invisible(cmd))
  }
  status <- system(cmd)
  if (status != 0) stop("hf upload failed (status ", status, ")")
  sprintf("https://huggingface.co/datasets/%s/resolve/%s/stages", repo, revision)
}
