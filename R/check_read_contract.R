#' Standalone-render read-contract guard.
#'
#' Returns the docs that violate the contract: any RUNTIME reference to the
#' targets store (tar_read / tar_load / tar_read_raw) or the raw 69 GB draws DB.
#' Full-line comments are ignored (they don't execute), so historical commented
#' `# targets::tar_read(...)` notes don't trip the check.
check_read_contract <- function(docs) {
  bad <- "tar_read|tar_load|tar_read_raw|crdc_arrests\\.duckdb"
  is_bad <- function(f) {
    lines <- readLines(f, warn = FALSE)
    code  <- lines[!grepl("^\\s*#", lines)]   # drop full-line comments
    any(grepl(bad, code))
  }
  Filter(is_bad, docs)
}
