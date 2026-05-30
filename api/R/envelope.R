# Consistent API response envelope: status / data / error / meta.

API_VERSION <- "v1"

#' Build a success envelope.
ok_envelope <- function(data, meta = list()) {
  base_meta <- list(version = API_VERSION)
  list(status = "success", data = data, error = NULL,
       meta = utils::modifyList(base_meta, meta))
}

#' Build an error envelope.
err_envelope <- function(message, meta = list()) {
  list(status = "error", data = NULL, error = message,
       meta = utils::modifyList(list(version = API_VERSION), meta))
}
