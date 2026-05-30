library(DBI)

#' Open a read-only connection to the API DuckDB.
api_connect <- function(db_path = Sys.getenv("API_DB_PATH", "data/crdc_api.duckdb")) {
  DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
}

api_disconnect <- function(con) {
  try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE)
}

read_meta <- function(con) {
  as.list(DBI::dbGetQuery(con, "SELECT * FROM meta LIMIT 1"))
}

#' Map an interval mass + measure to summary column names.
interval_cols <- function(interval, measure = c("rate", "count")) {
  measure <- match.arg(measure)
  list(lower = sprintf("%s_lower_%d", measure, interval),
       upper = sprintf("%s_upper_%d", measure, interval))
}
