# Fail-fast boundary validation. All raise condition class "api_bad_request"
# (caught by the plumber error filter -> 400 envelope).

ALLOWED_RACE  <- c("AM", "BL", "HI", "WH")
ALLOWED_SEX   <- c("F", "M")
ALLOWED_YEAR  <- c("15-16", "17-18", "21-22")
ALLOWED_MODELS <- c(paste0("nat_m", 1:5, "_mod"), paste0("sg_m", 1:5, "_mod"))
ALLOWED_INTERVALS <- c(50L, 80L, 95L)
LIMIT_CAP <- 1000L

api_abort <- function(message) {
  stop(structure(class = c("api_bad_request", "error", "condition"),
                 list(message = message, call = NULL)))
}

#' Normalize a model param to a canonical `*_mod` id.
validate_model <- function(x, default = "nat_m2_mod") {
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
