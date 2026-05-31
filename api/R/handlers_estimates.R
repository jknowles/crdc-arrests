#' Shared row -> public JSON object mapper for summary tables.
.summary_row_to_obj <- function(df, ic) {
  lapply(seq_len(nrow(df)), function(i) {
    r <- df[i, ]
    obj <- list(
      leaid = if ("LEAID" %in% names(r)) r$LEAID else NULL,
      lea_name = if ("lea_name" %in% names(r)) r$lea_name else NULL,
      state = r$LEA_STATE,
      state_name = if ("state_name" %in% names(r)) r$state_name else NULL,
      lat = if ("lat" %in% names(r)) r$lat else NULL,
      lon = if ("lon" %in% names(r)) r$lon else NULL,
      race = r$RACE, sex = r$SEX, year = r$YEAR, model = r$model_id,
      stu_enroll = r$stu_enroll,
      observed_arrests = if ("observed_arrests" %in% names(r)) r$observed_arrests else NULL,
      rate_median = r$rate_median, rate_lower = r[[ic$rate$lower]], rate_upper = r[[ic$rate$upper]],
      count_median = r$count_median, count_lower = r[[ic$count$lower]], count_upper = r[[ic$count$upper]]
    )
    obj[!vapply(obj, is.null, logical(1))]
  })
}

#' GET /estimates handler (LEA grain).
handle_estimates <- function(con, leaid, state, race, sex, year, model,
                             interval, limit, page) {
  model_id <- validate_model(model)
  iv <- validate_interval(interval)
  state <- validate_state(state)
  race <- validate_enum(race, ALLOWED_RACE, "race")
  sex  <- validate_enum(sex, ALLOWED_SEX, "sex")
  year <- validate_enum(year, ALLOWED_YEAR, "year")
  lim  <- validate_limit(limit); off <- validate_offset(page) * lim

  where <- c("model_id = ?")
  params <- list(model_id)
  add <- function(col, val) if (!is.null(val)) {
    where[[length(where)+1]] <<- sprintf("%s = ?", col); params[[length(params)+1]] <<- val }
  add("LEAID", leaid); add("LEA_STATE", state); add("RACE", race)
  add("SEX", sex); add("YEAR", year)

  ic <- list(rate = interval_cols(iv, "rate"), count = interval_cols(iv, "count"))
  where_sql <- paste(where, collapse = " AND ")

  total <- DBI::dbGetQuery(con, paste(
    "SELECT COUNT(*) n FROM arrest_summary WHERE", where_sql), params = params)$n
  rows <- DBI::dbGetQuery(con, sprintf(
    "SELECT * FROM arrest_summary WHERE %s ORDER BY LEAID, RACE, SEX LIMIT %d OFFSET %d",
    where_sql, lim, off), params = params)

  ok_envelope(.summary_row_to_obj(rows, ic),
    meta = list(total = total, page = validate_offset(page), limit = lim,
                model = model_id, interval = iv))
}
