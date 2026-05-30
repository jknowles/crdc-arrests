#' GET /districts handler: name/geo lookup -> LEAID.
handle_districts <- function(con, q, state, limit, offset) {
  lim <- validate_limit(limit); off <- validate_offset(offset)
  state <- if (!is.null(state) && nzchar(state)) state else NULL

  where <- c("1=1"); params <- list()
  if (!is.null(q) && nzchar(q)) {
    where[[length(where)+1]] <- "lea_name ILIKE ?"; params[[length(params)+1]] <- paste0("%", q, "%")
  }
  if (!is.null(state)) { where[[length(where)+1]] <- "LEA_STATE = ?"; params[[length(params)+1]] <- state }
  where_sql <- paste(where, collapse = " AND ")

  total <- DBI::dbGetQuery(con, paste("SELECT COUNT(*) n FROM district_dim WHERE", where_sql),
                           params = params)$n
  rows <- DBI::dbGetQuery(con, sprintf(
    "SELECT * FROM district_dim WHERE %s ORDER BY lea_name LIMIT %d OFFSET %d",
    where_sql, lim, off), params = params)

  data <- lapply(seq_len(nrow(rows)), function(i) {
    r <- rows[i, ]
    list(leaid=r$LEAID, lea_name=r$lea_name, state=r$LEA_STATE,
         state_name=r$state_name, lat=r$lat, lon=r$lon, enrollment=r$enrollment)
  })
  ok_envelope(data, meta = list(total = total, limit = lim, offset = off))
}
