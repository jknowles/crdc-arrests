#' Stamp the Civilytics logo onto a saved raster PNG (e.g. a flextable export).
#'
#' The plot builders brand figures with `civilytics::civilytics_logo()`, which
#' operates on ggplot/grobs. Table chunks export a flextable to PNG first, so
#' they need a raster compositor instead. This helper resolves the SAME package
#' logo asset that `civilytics::make_logo_grob()` uses (so tables match plots and
#' automatically track the current brand) and composites it onto `img_path` in
#' place via magick. No dependency on a document-level `logo_file` global.
#'
#' @param img_path Path to the PNG to stamp (overwritten in place).
#' @param type "wordmark" (default) or "mark".
#' @param variant "light" (default, dark logo for light backgrounds) or "dark".
#' @param position One of bottom-right (default), bottom-left, top-right, top-left.
#' @param width_frac Logo width as a fraction of the image width (default 0.15).
#' @param margin Padding from the edges, in pixels (default 20).
#' @return `img_path`, invisibly.
cv_stamp_logo_png <- function(img_path,
                              type     = c("wordmark", "mark"),
                              variant  = c("light", "dark"),
                              position = c("bottom-right", "bottom-left",
                                           "top-right", "top-left"),
                              width_frac = 0.15,
                              margin     = 20) {
  type <- match.arg(type); variant <- match.arg(variant); position <- match.arg(position)

  # Mirror civilytics::make_logo_grob()'s asset selection.
  img_file <- switch(paste(type, variant, sep = "_"),
    wordmark_light = "civilytics-wordmark.png",
    wordmark_dark  = "civilytics-wordmark-reverse.png",
    mark_light     = "civilytics-mark.png",
    mark_dark      = "civilytics-mark-reverse.png")
  logo_path <- system.file("img", img_file, package = "civilytics")
  if (!nzchar(logo_path)) {
    stop("Civilytics logo asset not found in the 'civilytics' package: ", img_file)
  }

  table_img <- magick::image_read(img_path)
  info      <- magick::image_info(table_img)
  logo      <- magick::image_scale(magick::image_read(logo_path),
                                   paste0(round(info$width * width_frac), "x"))
  linfo     <- magick::image_info(logo)

  x <- if (grepl("right",  position)) info$width  - linfo$width  - margin else margin
  y <- if (grepl("bottom", position)) info$height - linfo$height - margin else margin

  out <- magick::image_composite(table_img, logo, offset = sprintf("+%d+%d", x, y))
  magick::image_write(out, img_path, format = "png")
  invisible(img_path)
}
