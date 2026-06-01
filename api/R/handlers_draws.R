HF_DATASET <- "civilytics/crdc-school-arrest-rates"
# Use the hf:// protocol (not https resolve URLs): DuckDB httpfs can glob hf://
# paths (it lists via the HF API) but rejects globs on generic https URLs.
HF_BASE <- sprintf("hf://datasets/%s/parquet", HF_DATASET)

#' GET /draws handler: locate the HF Parquet shard(s) + a runnable DuckDB query.
#' Does NOT stream draws.
handle_draws <- function(state, race, sex, year, model) {
  model_id <- validate_model(model)
  state <- validate_state(state)
  race <- validate_enum(race, ALLOWED_RACE, "race")
  sex  <- validate_enum(sex, ALLOWED_SEX, "sex")
  year <- validate_enum(year, ALLOWED_YEAR, "year")

  # Partition order is model_id / YEAR / LEA_STATE. Always emit all three levels
  # (wildcard `*` when a filter is absent) so the glob depth matches the on-disk
  # layout; DuckDB's hive_partitioning reads YEAR/LEA_STATE from the matched
  # paths and prunes partitions via the WHERE clause.
  parts <- c(
    sprintf("model_id=%s", model_id),
    if (!is.null(year)) sprintf("YEAR=%s", year) else "*",
    if (!is.null(state)) sprintf("LEA_STATE=%s", state) else "*"
  )
  url <- sprintf("%s/%s/*.parquet", HF_BASE, paste(parts, collapse = "/"))

  filt <- c()
  if (!is.null(race)) filt <- c(filt, sprintf("RACE = '%s'", race))
  if (!is.null(sex))  filt <- c(filt, sprintf("SEX = '%s'", sex))
  where <- if (length(filt)) paste("WHERE", paste(filt, collapse = " AND ")) else ""
  sql <- sprintf(
    "SELECT * FROM read_parquet('%s', hive_partitioning=true) %s;", url, where)

  ok_envelope(list(parquet_url = url, duckdb_sql = sql, dataset = HF_DATASET),
              meta = list(model = model_id, note = "Bulk draws are served via Hugging Face, not this API."))
}
