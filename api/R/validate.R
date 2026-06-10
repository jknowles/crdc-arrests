# Fail-fast boundary validation. All raise condition class "api_bad_request"
# (caught by the plumber error filter -> 400 envelope).

ALLOWED_RACE  <- c("AM", "BL", "HI", "WH")
ALLOWED_SEX   <- c("F", "M")
ALLOWED_YEAR  <- c("15-16", "17-18", "21-22")
ALLOWED_MODELS <- c(paste0("unified_m", 1:5, "_mod"), paste0("stratified_m", 1:5, "_mod"))
ALLOWED_INTERVALS <- c(50L, 80L, 95L)
LIMIT_CAP <- 1000L
ALLOWED_STATES <- c("AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA","HI",
  "ID","IL","IN","IA","KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT",
  "NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD",
  "TN","TX","UT","VT","VA","WA","WV","WI","WY")

api_abort <- function(message) {
  stop(structure(class = c("api_bad_request", "error", "condition"),
                 list(message = message, call = NULL)))
}

#' Normalize a model param to a canonical `*_mod` id.
validate_model <- function(x, default = "unified_m2_mod") {
  if (is.null(x) || !nzchar(x)) return(default)
  cand <- if (grepl("_mod$", x)) x else paste0(x, "_mod")
  if (!cand %in% ALLOWED_MODELS) api_abort(sprintf("Unknown model '%s'.", x))
  cand
}

validate_interval <- function(x, default = 95L) {
  if (is.null(x) || !nzchar(x)) return(default)
  v <- suppressWarnings(as.integer(x))
  if (is.na(v) || !v %in% ALLOWED_INTERVALS)
    api_abort("interval must be one of 50, 80, 95.")
  v
}

validate_state <- function(x) {
  if (is.null(x) || !nzchar(x)) return(NULL)
  if (!x %in% ALLOWED_STATES)
    api_abort(sprintf("state must be a valid 2-letter US state/DC code; got '%s'.", x))
  x
}

validate_enum <- function(x, allowed, name) {
  if (is.null(x) || !nzchar(x)) return(NULL)
  if (!x %in% allowed)
    api_abort(sprintf("%s must be one of %s.", name, paste(allowed, collapse=", ")))
  x
}

validate_limit <- function(x, default = 100L) {
  if (is.null(x) || !nzchar(x)) return(default)
  v <- suppressWarnings(as.integer(x))
  if (is.na(v) || v < 0) api_abort("limit must be a non-negative integer.")
  min(v, LIMIT_CAP)
}

validate_offset <- function(x, default = 0L) {
  if (is.null(x) || !nzchar(x)) return(default)
  v <- suppressWarnings(as.integer(x))
  if (is.na(v) || v < 0) api_abort("offset/page must be non-negative.")
  v
}
