# Compute pole-of-inaccessibility label positions for sf polygon data.
#
# Uses sf::st_inscribed_circle() (requires GEOS >= 3.9 / sf >= 1.0) to find
# the largest circle fitting inside each polygon, then takes its centroid as
# the label anchor.  For MULTIPOLYGON geometries only the largest component
# polygon is used so the label lands on the main body of the state.
#
# Note on st_inscribed_circle() output: the function returns 2 geometries per
# input feature -- [1] the inscribed circle polygon, [2] always EMPTY.
# We extract every first element.
#
# @param sf_obj      An sf object with POLYGON or MULTIPOLYGON geometry.
# @param dTolerance  Tolerance passed to st_inscribed_circle(). Default 0.01
#                    degrees is ~1 km accuracy at US latitudes.
# @return  A plain data.frame (geometry dropped) with columns label_x, label_y
#          in the same CRS units as the input.
pole_of_inaccessibility <- function(sf_obj, dTolerance = 0.01) {

  crs       <- sf::st_crs(sf_obj)
  geom_type <- as.character(sf::st_geometry_type(sf_obj, by_geometry = FALSE))
  n         <- nrow(sf_obj)

  # For MULTIPOLYGON: keep only the largest component per feature so labels
  # land on the main landmass, not a small island or peninsula.
  if (geom_type == "MULTIPOLYGON") {
    geoms   <- sf::st_geometry(sf_obj)
    largest <- lapply(geoms, function(mp) {
      parts <- sf::st_cast(sf::st_sfc(mp, crs = crs), "POLYGON")
      parts[[which.max(sf::st_area(parts))]]
    })
    geoms_for_label <- sf::st_sfc(largest, crs = crs)
  } else {
    geoms_for_label <- sf::st_geometry(sf_obj)
  }

  # st_inscribed_circle() returns 2 POLYGON geometries per input feature:
  #   index 1 (odd)  -> the inscribed circle
  #   index 2 (even) -> always POLYGON EMPTY
  # Extract per-feature by calling on each geometry individually.
  circle_centres <- lapply(seq_len(n), function(i) {
    circ <- sf::st_inscribed_circle(geoms_for_label[i], dTolerance = dTolerance)
    # circ[[1]] is the non-empty circle polygon; take its centroid
    if (!sf::st_is_empty(circ[1])) {
      sf::st_coordinates(sf::st_centroid(circ[1]))[1, 1:2]
    } else {
      # Fallback: plain centroid of the original polygon
      sf::st_coordinates(sf::st_centroid(geoms_for_label[i]))[1, 1:2]
    }
  })

  coords <- do.call(rbind, circle_centres)
  data.frame(label_x = coords[, 1], label_y = coords[, 2])
}


# Add label_x / label_y columns to an sf data frame in-place.
#
# Call this once after building your sf object, then reuse across plots.
#
# @param sf_df       An sf data frame.
# @param dTolerance  Passed to pole_of_inaccessibility().
# @return  The input sf data frame with two additional numeric columns.
add_pole_of_inaccessibility <- function(sf_df, dTolerance = 0.01) {
  coords        <- pole_of_inaccessibility(sf_df, dTolerance = dTolerance)
  sf_df$label_x <- coords$label_x
  sf_df$label_y <- coords$label_y
  sf_df
}


# ...existing code...
# Drop-in ggplot2 layer: places text labels at the pole of inaccessibility.
#
# Pre-computes label positions and returns a geom_text() layer that can be
# added directly to a ggplot built with geom_sf().
#
# @param sf_df      The sf data frame used in the ggplot (same object as `data`
#                   in the ggplot() call, or a pre-filtered version).
# @param label_col  Name of the column to use as labels (string).
# @param label_fn   Optional function to transform label values before display
#                   (e.g. scales::comma, civilytics::pretty_count). Default: NULL.
# @param ...        Additional arguments forwarded to geom_text()
#                   (e.g. size, color, fontface, check_overlap).
# @return  A geom_text() layer.
#
# Usage:
#   ggplot(state_map2, aes(fill = arrests)) +
#     geom_sf() +
#     label_states(state_map2, "arrests", label_fn = civilytics::pretty_count, size = 3) +
#     ...
label_states <- function(sf_df, label_col, label_fn = NULL, ...) {

  if (!all(c("label_x", "label_y") %in% names(sf_df))) {
    sf_df <- add_pole_of_inaccessibility(sf_df)
  }

  df <- sf::st_drop_geometry(sf_df)

  if (!is.null(label_fn)) {
    df$label_col__ <- label_fn(df[[label_col]])
  } else {
    df$label_col__ <- df[[label_col]]
  }

  ggplot2::geom_label(
    data    = df,
    mapping = ggplot2::aes(x = label_x, y = label_y, label = label_col__),
    ...
  )
}
