#!/usr/bin/env Rscript
# Publish a full CRDC release to Hugging Face in one reviewed, idempotent step:
#   export/parquet/         -> <repo>/parquet        (atomic mirror; orphan shards deleted)
#   export/api/crdc_api...  -> <repo>/summary.duckdb
#   export/stages/          -> <repo>/stages
# all on --revision (default "main"), then create (or move) the release TAG so
# the pinned `@<release>` reads — crdc_path() default, the API DATA_URL, and the
# new-user reproduction path — resolve to exactly this publish.
#
# Supersedes the single-artifact trio (scripts/publish_hf.R, scripts/publish_db.R,
# R/publish_stages.R) for a coordinated release; those remain for one-off pushes.
#
# SAFE BY DEFAULT: prints the plan and exits. Pass --execute to actually upload.
#
# Auth: the `hf` CLI on PATH + a WRITE-scoped HF_TOKEN in the environment OR a
# stored `hf auth login` session.
#
# Usage:
#   Rscript scripts/publish_all.R                       # dry-run (print the plan)
#   Rscript scripts/publish_all.R --execute             # publish + create tag
#   Rscript scripts/publish_all.R --execute --move-tag  # also repoint an existing tag
#   Rscript scripts/publish_all.R --release=civilytics-crdc-arrests-2025.2 --execute
#   Rscript scripts/publish_all.R --no-tag --execute    # artifacts only, no tag
#   Rscript scripts/publish_all.R --revision=dev --no-tag --execute   # stage to a branch
#
# Defaults: --repo=civilytics/crdc-school-arrest-rates  --revision=main
#   --parquet-dir=export/parquet  --db=export/api/crdc_api.duckdb  --stages-dir=export/stages
#   --release=<meta.data_release read from --db>  (falls back to DEFAULT_RELEASE)

DEFAULT_REPO    <- "civilytics/crdc-school-arrest-rates"
DEFAULT_RELEASE <- "civilytics-crdc-arrests-2025.1"

args <- commandArgs(trailingOnly = TRUE)
has_flag <- function(f) f %in% args
arg_val  <- function(key, default) {
  hit <- grep(paste0("^--", key, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^--", key, "="), "", hit[[1]]) else default
}

repo        <- arg_val("repo", DEFAULT_REPO)
revision    <- arg_val("revision", "main")
parquet_dir <- arg_val("parquet-dir", "export/parquet")
db          <- arg_val("db", "export/api/crdc_api.duckdb")
stages_dir  <- arg_val("stages-dir", "export/stages")
execute     <- has_flag("--execute")
move_tag    <- has_flag("--move-tag")
do_tag      <- !has_flag("--no-tag")

# Resolve the release tag. Default = the data_release stamped into the DB meta,
# so the tag can never silently drift from what the artifact claims to be.
read_db_release <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  tryCatch({
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = path, read_only = TRUE)
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
    v <- DBI::dbGetQuery(con, "SELECT data_release FROM meta LIMIT 1")$data_release
    if (length(v) && nzchar(v)) v[[1]] else NA_character_
  }, error = function(e) NA_character_)
}
release <- arg_val("release", {
  r <- read_db_release(db)
  if (is.na(r)) {
    message("NOTE: could not read meta.data_release from ", db,
            "; defaulting tag to ", DEFAULT_RELEASE)
    DEFAULT_RELEASE
  } else r
})

# Accept either an HF_TOKEN env var or a stored `hf auth login` session.
authed <- nzchar(Sys.getenv("HF_TOKEN")) ||
  identical(suppressWarnings(system("hf auth whoami",
            ignore.stdout = TRUE, ignore.stderr = TRUE)), 0L)
if (!authed) {
  stop("Not authenticated to Hugging Face. Run `hf auth login` (paste a WRITE ",
       "token) or set HF_TOKEN=hf_... with write scope, then re-run.")
}

# Fail loudly (even in dry-run) if a local artifact is missing.
missing <- c(
  if (!dir.exists(parquet_dir)) parquet_dir,
  if (!file.exists(db))         db,
  if (!dir.exists(stages_dir))  stages_dir
)
if (length(missing)) {
  stop("missing local artifact(s):\n  ", paste(missing, collapse = "\n  "),
       "\nRun the pipeline (tar_make()) to produce export/ first.")
}

hf_git_url <- sprintf("https://huggingface.co/datasets/%s", repo)
tag_exists <- function(tag) {
  out <- suppressWarnings(system(
    sprintf("git ls-remote %s refs/tags/%s", shQuote(hf_git_url), shQuote(tag)),
    intern = TRUE))
  length(out) > 0 && any(nzchar(out))
}

# `extra` is a literal CLI fragment (e.g. --delete '*'), NOT shell-quoted.
upload_cmd <- function(src, path_in_repo, extra = "") {
  sprintf("hf upload %s %s %s --repo-type=dataset --revision=%s %s--commit-message=%s",
          shQuote(repo), shQuote(src), shQuote(path_in_repo), shQuote(revision),
          if (nzchar(extra)) paste0(extra, " ") else "",
          shQuote(sprintf("publish %s -> %s (%s)", path_in_repo, revision, release)))
}
# parquet uses --delete '*' so a re-publish removes orphan shards (the same
# fix as R/export_parquet.R): a plain upload only overwrites same-named files.
plan <- list(
  parquet = upload_cmd(parquet_dir, "parquet", "--delete '*'"),
  db      = upload_cmd(db, "summary.duckdb"),
  stages  = upload_cmd(stages_dir, "stages")
)

run <- function(cmd) {
  message("RUN: ", cmd)
  st <- system(cmd)
  if (st != 0) stop("command failed (status ", st, "): ", cmd)
}

message("== publish_all [", if (execute) "EXECUTE" else "DRY-RUN", "] ==")
message("  repo:     ", repo)
message("  revision: ", revision)
message("  release:  ", release, if (do_tag) "  (tag created/verified)" else "  (--no-tag)")
message("  parquet:  ", parquet_dir)
message("  db:       ", db)
message("  stages:   ", stages_dir)
message("")

if (!execute) {
  message("Planned uploads:")
  for (nm in names(plan)) message("  [", nm, "] ", plan[[nm]])
  if (do_tag) {
    ex <- tag_exists(release)
    note <- if (ex) {
      if (move_tag) "  (EXISTS -> will delete + recreate)" else
        "  (EXISTS -> skipped; pass --move-tag to repoint)"
    } else "  (will create)"
    message("Planned tag: ", release, " -> ", revision, note)
  }
  message("\nRe-run with --execute to publish.")
  quit(save = "no", status = 0)
}

run(plan$parquet)
run(plan$db)
run(plan$stages)

if (do_tag) {
  if (tag_exists(release) && !move_tag) {
    message("Tag ", release, " already exists; NOT moved (pass --move-tag to ",
            "repoint it). Artifacts on ", revision, " are updated.")
  } else {
    if (tag_exists(release) && move_tag) {
      run(sprintf("hf repos tag delete %s %s --repo-type dataset --yes",
                  shQuote(repo), shQuote(release)))
    }
    run(sprintf("hf repos tag create %s %s --revision %s --repo-type dataset -m %s",
                shQuote(repo), shQuote(release), shQuote(revision),
                shQuote(sprintf("Release %s", release))))
    message("Tag ", release, " -> ", revision, " created.")
  }
}

message("\nDone. Published ", release, " to ", repo, " @ ", revision, ".")
message("Pinned reads resolve at: ",
        sprintf("https://huggingface.co/datasets/%s/resolve/%s/", repo, release))
