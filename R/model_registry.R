#' Model identifier + display-label registry (single source of truth).
#'
#' PRESENTATION-ONLY "pooled" rename lives here. The published `model_id` keys
#' stay `nat_*` / `sg_*` (Subsystem 1 data contract); only the human-facing
#' `label` says "Pooled" vs "Student-group". The future deep rename flips `id`
#' to `pooled_*` HERE and nowhere else.
crdc_model_registry <- function() {
  tibble::tribble(
    ~id,          ~group,          ~spec, ~label,
    "nat_m1_mod", "pooled",        "m1",  "Pooled (m1)",
    "nat_m2_mod", "pooled",        "m2",  "Pooled (m2)",
    "nat_m3_mod", "pooled",        "m3",  "Pooled (m3)",
    "nat_m4_mod", "pooled",        "m4",  "Pooled (m4)",
    "nat_m5_mod", "pooled",        "m5",  "Pooled (m5)",
    "sg_m1_mod",  "student_group", "m1",  "Student-group (m1)",
    "sg_m2_mod",  "student_group", "m2",  "Student-group (m2)",
    "sg_m3_mod",  "student_group", "m3",  "Student-group (m3)",
    "sg_m4_mod",  "student_group", "m4",  "Student-group (m4)",
    "sg_m5_mod",  "student_group", "m5",  "Student-group (m5)"
  )
}

#' Map model_id keys to display labels (vectorised; NA for unknown ids).
crdc_model_label <- function(id) {
  reg <- crdc_model_registry()
  reg$label[match(id, reg$id)]
}

#' The pooled model ids whose brms fits ship as qs2 for live diagnostics.
crdc_pooled_ids <- function() {
  reg <- crdc_model_registry()
  reg$id[reg$group == "pooled"]
}
