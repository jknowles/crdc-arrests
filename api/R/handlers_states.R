#' GET /states handler (state grain, draw-wise aggregate).
handle_states <- function(con, state, race, sex, year, model,
                          interval, limit, page) {
  model_id <- validate_model(model)
  iv <- validate_interval(interval)
  state <- validate_state(state)
  race <- validate_enum(race, ALLOWED_RACE, "race")
  sex  <- validate_enum(sex, ALLOWED_SEX, "sex")
  year <- validate_enum(year, ALLOWED_YEAR, "year")
  lim  <- validate_limit(limit); off <- validate_offset(page) * lim

  where <- c("model_id = ?"); params <- list(model_id)
  add <- function(col, val) if (!is.null(val)) {
    where[[length(where)+1]] <<- sprintf("%s = ?", col); params[[length(params)+1]] <<- val }
  add("LEA_STATE", state); add("RACE", race); add("SEX", sex); add("YEAR", year)
  where_sql <- paste(where, collapse = " AND ")

  ic <- list(rate = interval_cols(iv, "rate"), count = interval_cols(iv, "count"))
  total <- DBI::dbGetQuery(con, paste(
    "SELECT COUNT(*) n FROM state_summary WHERE", where_sql), params=params)$n
  rows <- DBI::dbGetQuery(con, sprintf(
    "SELECT * FROM state_summary WHERE %s ORDER BY LEA_STATE, RACE, SEX LIMIT %d OFFSET %d",
    where_sql, lim, off), params=params)

  ok_envelope(.summary_row_to_obj(rows, ic),
    meta = list(total = total, page = validate_offset(page), limit = lim,
                model = model_id, interval = iv, grain = "state"))
}
