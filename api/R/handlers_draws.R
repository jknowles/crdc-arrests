HF_DATASET <- "civilytics/crdc-school-arrest-rates"
HF_BASE <- sprintf("https://huggingface.co/datasets/%s/resolve/main/parquet", HF_DATASET)

#' GET /draws handler: locate the HF Parquet shard(s) + a runnable DuckDB query.
#' Does NOT stream draws.
handle_draws <- function(state, race, sex, year, model) {
  model_id <- validate_model(model)
  state <- validate_state(state)
  race <- validate_enum(race, ALLOWED_RACE, "race")
  sex  <- validate_enum(sex, ALLOWED_SEX, "sex")
  year <- validate_enum(year, ALLOWED_YEAR, "year")

  parts <- sprintf("model_id=%s", model_id)
  if (!is.null(year)) parts <- c(parts, sprintf("YEAR=%s", year))
  if (!is.null(state)) parts <- c(parts, sprintf("LEA_STATE=%s", state))
  partition_path <- paste(parts, collapse = "/")
  url <- sprintf("%s/%s/*.parquet", HF_BASE, partition_path)

  filt <- c()
  if (!is.null(race)) filt <- c(filt, sprintf("RACE = '%s'", race))
  if (!is.null(sex))  filt <- c(filt, sprintf("SEX = '%s'", sex))
  where <- if (length(filt)) paste("WHERE", paste(filt, collapse = " AND ")) else ""
  sql <- sprintf(
    "SELECT * FROM read_parquet('%s', hive_partitioning=true) %s;", url, where)

  ok_envelope(list(parquet_url = url, duckdb_sql = sql, dataset = HF_DATASET),
              meta = list(model = model_id, note = "Bulk draws are served via Hugging Face, not this API."))
}
