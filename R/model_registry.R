#' Model identifier + display-label registry (single source of truth).
#'
#' The published `model_id` keys are `unified_*` (one model fit to the whole
#' dataset) and `stratified_*` (one model per RACE x SEX), matching the white
#' paper's "unified" vs "stratified" terminology. `group` and `label` derive
#' from the same vocabulary, so the id, the data contract, and the prose all
#' agree. This registry is the single place the model vocabulary is defined.
crdc_model_registry <- function() {
  tibble::tribble(
    ~id,                 ~group,        ~spec, ~label,
    "unified_m1_mod",    "unified",     "m1",  "Unified (m1)",
    "unified_m2_mod",    "unified",     "m2",  "Unified (m2)",
    "unified_m3_mod",    "unified",     "m3",  "Unified (m3)",
    "unified_m4_mod",    "unified",     "m4",  "Unified (m4)",
    "unified_m5_mod",    "unified",     "m5",  "Unified (m5)",
    "stratified_m1_mod", "stratified",  "m1",  "Stratified (m1)",
    "stratified_m2_mod", "stratified",  "m2",  "Stratified (m2)",
    "stratified_m3_mod", "stratified",  "m3",  "Stratified (m3)",
    "stratified_m4_mod", "stratified",  "m4",  "Stratified (m4)",
    "stratified_m5_mod", "stratified",  "m5",  "Stratified (m5)"
  )
}

#' Map model_id keys to display labels (vectorised; NA for unknown ids).
crdc_model_label <- function(id) {
  reg <- crdc_model_registry()
  reg$label[match(id, reg$id)]
}

#' The unified model ids whose brms fits ship as qs2 for live diagnostics.
crdc_unified_ids <- function() {
  reg <- crdc_model_registry()
  reg$id[reg$group == "unified"]
}
