library(plumber)
# Source handlers/helpers (paths relative to where plumber is run: api/)
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

# One read-only connection for the process lifetime.
.CON <- api_connect()
reg.finalizer(environment(), function(e) api_disconnect(.CON), onexit = TRUE)

#* @apiTitle CRDC School Arrest Rate API
#* @apiDescription Small-area Bayesian estimates of school-based arrest rates from
#*   the Civil Rights Data Collection. Summaries by district and state; raw draws
#*   via Hugging Face. Cite: Knowles & Miller 2025.
#* @apiVersion v1

# res$setHeader() appends rather than replaces (plumber does
# self$headers <- c(self$headers, he)), so overriding a header already set by
# an earlier filter requires dropping the old value first.
drop_header <- function(res, name) {
  h <- res$headers
  if (!is.null(h) && length(h)) res$headers <- h[names(h) != name]
  invisible(NULL)
}

set_no_store <- function(res) {
  drop_header(res, "Cache-Control")
  res$setHeader("Cache-Control", "no-store")
}

# Global error handler -> 400 for validation errors, 500 otherwise (no internal
# leak). A `@filter` wrapping forward() in tryCatch does NOT catch errors thrown
# inside endpoint handlers (plumber routes those to the error handler set here),
# so validation aborts must be mapped via pr_set_error, not a filter.
#* @plumber
function(pr) {
  pr |> plumber::pr_set_error(function(req, res, err) {
    # null="null" matches the endpoints' @serializer so `data` renders as JSON
    # null (not {}), keeping error envelopes consistent with success envelopes.
    res$serializer <- plumber::serializer_unboxed_json(null = "null")
    set_no_store(res)
    if (inherits(err, "api_bad_request")) {
      res$status <- 400L
      return(err_envelope(conditionMessage(err)))
    }
    res$status <- 500L
    err_envelope("Internal server error.")
  }) |> plumber::pr_set_404(function(req, res) {
    # Unmatched routes still run through the cacheHeaders filter (it applies
    # before routing), so they arrive here already stamped immutable -- never
    # reaching pr_set_error means that stamp is otherwise never corrected.
    res$serializer <- plumber::serializer_unboxed_json(null = "null")
    res$status <- 404L
    set_no_store(res)
    err_envelope("404 - Resource not found.")
  })
}

#* CORS + cache headers (responses are static per data_release)
#* @filter cacheHeaders
function(req, res) {
  # Allow browser-based clients (e.g., git-pages demo app) to fetch from the API.
  # The CRDC API is read-only and does not handle sensitive user data in requests,
  # so a permissive CORS policy is safe. See: docs/extensions.md for rationale.
  res$setHeader("Access-Control-Allow-Origin", "*")
  res$setHeader("Access-Control-Allow-Methods", "GET, OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "*" )

  # Handle CORS preflight requests (OPTIONS) before routing to endpoints.
  if (toupper(req$REQUEST_METHOD) == "OPTIONS") {
    res$status <- 204L
    return(list())
  }

  if (grepl("/health$", req$PATH_INFO)) {
    res$setHeader("Cache-Control", "no-store")
  } else {
    res$setHeader("Cache-Control", "public, max-age=31536000, immutable")
  }
  plumber::forward()
}

#* Liveness
#* @serializer unboxedJSON list(null="null")
#* @get /api/v1/health
function() list(status = "ok")

#* API metadata
#* @serializer unboxedJSON list(null="null")
#* @get /api/v1/
function() {
  m <- read_meta(.CON)
  ok_envelope(list(name="CRDC School Arrest Rate API", docs="/__docs__/",
                   openapi="/openapi.json", llms="/api/v1/llms.txt"),
              meta = list(data_release = m$data_release, citation = m$citation))
}

#* Agent-facing plain-text description
#* @serializer text
#* @get /api/v1/llms.txt
function(res) {
  res$setHeader("Content-Type", "text/plain")
  path <- if (file.exists("llms.txt")) "llms.txt" else "api/llms.txt"
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

#* List models
#* @serializer unboxedJSON list(null="null")
#* @get /api/v1/models
function() handle_models()

#* District name/geo lookup
#* @param q Search string (district name, partial)
#* @param state Two-letter state
#* @param limit Max rows (<=1000)
#* @param offset Row offset
#* @serializer unboxedJSON list(null="null")
#* @get /api/v1/districts
function(q="", state="", limit="100", offset="0") handle_districts(.CON, q, state, limit, offset)

#* LEA-level estimates
#* @param leaid
#* @param state
#* @param race One of AM, BL, HI, WH
#* @param sex One of F, M
#* @param year One of 15-16, 17-18, 21-22
#* @param model Model id (default unified_m2)
#* @param interval One of 50, 80, 95 (default 95)
#* @param limit
#* @param page
#* @serializer unboxedJSON list(null="null")
#* @get /api/v1/estimates
function(leaid="", state="", race="", sex="", year="", model="", interval="", limit="100", page="0")
  handle_estimates(.CON, nz(leaid), nz(state), nz(race), nz(sex), nz(year),
                   nz(model), nz(interval), limit, page)

#* Single district, all demographics
#* @param leaid
#* @param model
#* @param year
#* @param interval
#* @serializer unboxedJSON list(null="null")
#* @get /api/v1/estimates/<leaid>
function(leaid, model="", year="", interval="")
  handle_estimates(.CON, leaid, NULL, NULL, NULL, nz(year), nz(model), nz(interval), "1000", "0")

#* State-level estimates
#* @param state
#* @param race
#* @param sex
#* @param year
#* @param model
#* @param interval
#* @param limit
#* @param page
#* @serializer unboxedJSON list(null="null")
#* @get /api/v1/states
function(state="", race="", sex="", year="", model="", interval="", limit="100", page="0")
  handle_states(.CON, nz(state), nz(race), nz(sex), nz(year), nz(model), nz(interval), limit, page)

#* Single state, all demographics
#* @param state
#* @serializer unboxedJSON list(null="null")
#* @get /api/v1/states/<state>
function(state, model="", year="", interval="")
  handle_states(.CON, state, NULL, NULL, nz(year), nz(model), nz(interval), "1000", "0")

#* Locate raw-draw Parquet shard + DuckDB query (does not stream draws)
#* @param state
#* @param race
#* @param sex
#* @param year
#* @param model
#* @serializer unboxedJSON list(null="null")
#* @get /api/v1/draws
function(state="", race="", sex="", year="", model="")
  handle_draws(nz(state), nz(race), nz(sex), nz(year), nz(model))
