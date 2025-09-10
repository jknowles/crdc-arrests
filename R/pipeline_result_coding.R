# Test exploration

library(targets)
library(brms)
library(dplyr)
library(ggdist)
library(marginaleffects)
library(tidybayes)
library(ggridges)


library(duckdb)

con <- DBI::dbConnect(duckdb::duckdb(), "export/db/crdc_arrests.duckdb")

tydata <- targets::tar_read(three_year_data)$data

large_ids <- c("2400090", "2400120", "2400480",
              # "2400510",
               #"2400270",
               "2400330")

zz <- get_prediction_draws(con, LEAID = large_ids, RACE = c("WH", "BL"),
                            )


zz <- inner_join(zz, tydata, by = join_by(YEAR, LEAID, LEA_STATE, RACE, SEX))



ggplot(zz |> filter(YEAR == "21-22") |> filter(model_id %in% c("sg_m5_mod", "sg_m4_mod"))) +
  aes(x = pred / (stu_enroll / 1000), y = LEA_NAME, fill = model_id) +
  geom_density_ridges(rel_min_height = 0.02, scale = 1, color = "white", alpha = 3/5,
                      bandwidth = 0.1) + # bw set to 0.2 to avoid jaggediness in BCPS
  scale_y_discrete("District", labels = function(x) stringr::str_wrap(x, 12), expand = c(0, 0)) +
  scale_x_sqrt("Predicted arrests per 1,000 students", limits = c(0, 5),
                  expand = c(0,0)) +
  geom_point(data = zz |> filter(YEAR == "21-22") |> filter(model_id %in% c("sg_m5_mod", "sg_m4_mod")),
              aes(x = arrest_rate, y = LEA_NAME)) +
  #                                       size = enroll ), alpha = 3/5,
  #            show.legend = FALSE) +
  # scale_size_area(trans = "sqrt", max_size = 12) +
  guides(size = guide_none(), color = guide_none()) +
  # scale_fill_manual(values = color_fill_values2) +
  # scale_color_manual(values = color_fill_values2) +
  coord_cartesian(clip = "off") +
  facet_wrap(RACE ~ SEX) +
  theme_ridges(grid = FALSE) +
  civilytics::theme_civilytics(font_size = 14) +
  theme(legend.position = "inside",
    legend.position.inside = c(0.8, 0.2))


plotdf <- get_state_prediction_summary(con, LEA_STATE = c("KS", "TX", "SD", "MA"),
                          RACE = c("WH", "BL"),
                          YEAR = "21-22", confidence_level = 0.9)


zz <- inner_join(plotdf,
                        tydata |>  group_by(LEA_STATE, YEAR, RACE, SEX) |>
                          summarize(stu_enroll = sum(stu_enroll),
                                    arrests = sum(ARRESTS)),
                          by = join_by(YEAR, LEA_STATE, RACE, SEX))



ggplot(zz |> filter(YEAR == "21-22") |> filter(model_id %in% c("sg_m4_mod", "sg_m5_mod"))) +
  geom_pointinterval(aes(y = LEA_STATE, x = fitted_value / (stu_enroll/1000), xmin = min_pred/(stu_enroll/1000),
                      xmax = max_pred/(stu_enroll/1000), color = model_id), position = position_dodge()) +
  scale_y_discrete("State", labels = function(x) stringr::str_wrap(x, 12), expand = c(0, 0)) +
  scale_x_continuous("Predicted arrests per 1,000 students",
                  expand = c(0,0)) +
  geom_point(data = zz |> filter(YEAR == "21-22") |> filter(model_id %in% c("sg_m4_mod", "sg_m5_mod")),
              aes(x = arrests/(stu_enroll / 1000), y = LEA_STATE)) +

  guides(size = guide_none(), fill = guide_none()) +
  # scale_fill_manual(values = color_fill_values2) +
  # scale_color_manual(values = color_fill_values2) +
  coord_cartesian(clip = "off") +
  facet_wrap(RACE ~ SEX) +
  theme_ridges(grid = FALSE) +
  civilytics::theme_civilytics(font_size = 14) +
  theme(legend.position = "inside",
    legend.position.inside = c(0.8, 0.2))




# TODO: Stop here
nat_mod <- targets::tar_read(nat_m2_mod)


# TODO: Can we facet these by region?
nat_mod %>%
  spread_draws(b_Intercept, r_LEA_STATE[state,]) %>%
  mutate(state_mean = b_Intercept + r_LEA_STATE) %>%
  ggplot(aes(y = reorder(state, state_mean), x = brms::inv_logit_scaled(state_mean)* 1000))+
  stat_halfeye() +
  theme_ridges()



z <- add_predicted_draws(nat_mod$data[1:100,], nat_mod, ndraws = 200)
z <- z |> select(LEAID, LEA_STATE, YEAR, RACE, SEX, .prediction, .draw) |>
  mutate(model_id = "model_id")



z <- predict(nat_mod, summary = TRUE, robust = TRUE, cores = 16, draws = 300)
tyfit_data <- cbind(tydata, z)




sg_mod <- targets::tar_read(sg_m1_mod)

tydata <- targets::tar_read(three_year_data)$data


tydata |> filter(LEA_STATE == "KS") |> filter(YEAR == "21-22") |>
  filter(RACE == "TOTAL") |>
  arrange(desc(ARRESTS)) |>
  filter(ARRESTS >= 3) |> pull(LEAID) |> unique() -> plot_leas



tydata |> filter(RACE == "TOTAL", SEX == "M", YEAR == "21-22") %>%
  predictions(nat_mod, type = "prediction", newdata = .) |>
  get_draws() -> testdf

# draw is the value for a specific draw and
# estimate, conf.low, conf.high are the aggregations for all draws
# for that rowid
# TODO> add more finegrained grouping and proceed
testdf |> filter(as.integer(drawid) < 100) |> group_by(LEA_STATE, drawid) |>
  summarize(true_arrests = sum(ARRESTS),
            true_enroll = sum(stu_enroll),
            estimate = sum(draw)) |>
              mutate(true_rate = true_arrests / true_enroll,
                    fitted_rate = estimate / true_enroll) |>
        group_by(LEA_STATE) -> state_df



      state_df |>
        mean_qi(state_mean = fitted_rate, true_mean = true_rate)




# State estimeated means and true values for 21-22, total, male arrests

ggplot(state_df |> filter(LEA_STATE %in% c("KS", "TX", "CA", "SD"))) +
  aes(x = fitted_rate *1000, y = LEA_STATE) +
  geom_density_ridges(rel_min_height = 0.02, scale = 1, color = "white", alpha = 3/5,
                      bandwidth = 0.2) + # bw set to 0.2 to avoid jaggediness in BCPS
  scale_y_discrete("State", labels = function(x) stringr::str_wrap(x, 12), expand = c(0, 0)) +
  scale_x_sqrt("Predicted arrests per 1,000 students", expand = c(0,0)) +
  geom_point(data = state_df |> filter(LEA_STATE %in% c("KS", "TX", "CA", "SD")),
        aes(x = true_rate*1000, y = LEA_STATE, size = true_enroll ), alpha = 3/5,
             show.legend = FALSE) +
  scale_size_area(trans = "sqrt", max_size = 12) +
  #guides(size = guide_none(), color = guide_none()) +
  #scale_fill_manual(values = color_fill_values2) +
  #scale_color_manual(values = color_fill_values2) +
  coord_cartesian(clip = "off") +
  theme_ridges(grid = FALSE) +
  civilytics::theme_civilytics(font_size = 14) +
  theme(legend.position = c(0.8, 0.2))





# This lumps all years and race/sex together
nat_mod %>%
  spread_draws(b_Intercept, r_LEA_STATE[state,]) %>%
  mean_qi(state_mean = b_Intercept + r_LEA_STATE, .width = c(.95, .8)) %>%
  ggplot(aes(y = reorder(state, state_mean), x = exp(state_mean)*1000, xmin = exp(.lower)*1000, xmax = exp(.upper)*1000)) +
  geom_pointinterval()






nat_mod %>%
  recover_types %>%
  gather_draws(`b_.*`, regex = TRUE) %>%
  median_qi(.width = c(.95, .66)) %>%
  ggplot(aes(y = .variable, x = .value, xmin = .lower, xmax = .upper)) +
  geom_pointinterval()


# Generate state predictions
state_pred <- marginaleffects::predictions(nat_mod, newdata = tydata |> filter(LEA_STATE == "KS") |> filter(YEAR == "21-22") |> filter(LEAID %in% plot_leas))

p1 <- state_pred |> get_draws() |> transform(type = "Response")

ggplot(p1, aes(x = draw, fill = SEX, y = estimate)) +
  stat_halfeye(alpha = 0.5) +
  facet_wrap(~LEAID) +
  theme_bw()

# Get fixed effect posterior draws on the exponential scale
mod |> spread_draws(r_LEA_STATE[i, j], ndraws = 10)

# Obviously can do this to summarize regression model output too



# Get fitted values for specific districts
mod$data |> slice(1:10) |> add_epred_draws(mod, ndraws = 500)







results <- targets::tar_read(sg_m4_sg_m4)
formula <- ARRESTS | trials(stu_enroll) ~ 1 + referral_rate + total_referrals + (1|LEA_STATE) +  (1|LEAID)
data <- tar_read(recent_data)
draws <- targets::tar_read(nat_m2m_draws_nat_m2)

library(dplyr)
library(stringr)

# ------------------------------------------------------------
# 1️⃣ Function that splits a Stan variable name into two parts
# ------------------------------------------------------------
split_var <- function(var_name) {
  # If the name contains brackets, split at the first '['
  if (!grepl("\\[", var_name)) {
    return(list(var_type = var_name,
                var_id   = NA_integer_))
  }

  # Separate the part before '[' and the inside of the brackets
  parts <- strsplit(var_name, "\\[")[[1]]
  prefix <- parts[1]                     # e.g. "z_1" or "b"
  inside <- sub("\\]", "", parts[2])     # remove trailing ']'

  # For z variables we only want the second number (after the comma)
  if (grepl("^z_", prefix)) {
    idx <- as.integer(strsplit(inside, ",")[[1]][2])
  } else {
    # For other variables (b, sd_1, etc.) take the first number
    idx <- as.integer(strsplit(inside, ",")[[1]][1])
  }

  list(var_type = prefix,
       var_id   = idx)
}

# ------------------------------------------------------------
# 2️⃣ Apply to an entire data frame of Stan results
# ------------------------------------------------------------
add_var_info <- function(results_df) {
  # `results$variable` is assumed to be a character vector
  vars_split <- lapply(results_df$variable, split_var)

  # Convert list of lists into two columns
  var_type_vec <- sapply(vars_split, `[[`, "var_type")
  var_id_vec   <- sapply(vars_split, `[[`, "var_id")

  results_df$var_type <- var_type_vec
  results_df$var_id   <- var_id_vec

  results_df
}


  vars <- unique(results$variable)   # replace with your actual column if needed
  # ------------------------------------------------------------
  # 2️⃣ Keep only entries that match the pattern z_<group>[...]
  #    Example matches: "z_1[1,5]" , "z_2[1,12]"
  # ------------------------------------------------------------
  z_pattern <- "^z_(\\d+)\\["               # captures the group number
  z_vars   <- vars[stringr::str_detect(vars, z_pattern)]

  group_id <- stringr::str_match(z_vars, "^z_(\\d+)\\[")[,2]          # first capture = g
  col_idx  <- stringr::str_match(z_vars, ",\\s*(\\d+)\\]$")[,2]      # second number = column

  # Convert to integers
  group_id <- as.integer(group_id)
  col_idx  <- as.integer(col_idx)

    z_df <- tibble(group = group_id,
                    col   = col_idx)

    # ------------------------------------------------------------
    # 5️⃣ Count **unique** column indices per group
    # ------------------------------------------------------------
    z_df <- z_df %>%
      group_by(group) %>%
      mutate(
        total_entries   = n(),
        unique_columns  = length(unique(col))
      ) %>%
      arrange(group)

      find_df_by_nrow <- function(lst, target_n) {
      # Look at list elements that have no name ("" or NA)
      idx <- 1:length(lst)
      for (i in idx) {
        candidate <- lst[[i]]
        if (is.data.frame(candidate) && nrow(candidate) == target_n) {
          return(candidate)
        }
      }
      NULL   # not found
    }

   result_list <- list()   # will store a tibble per group
    for (g in unique(z_df$group)) {
      # Number of distinct columns for this group
      n_cols <- z_df %>% filter(group == g) %>% pull(unique_columns) |> first()

      ## ----------------------------------------------------------------
      ## Choose the correct key vector (state_keys vs lea_keys)
      ## ----------------------------------------------------------------
      #keys_vec <- if (n_cols < 100) data$state_keys else data$lea_keys

      # Convert to tibble (if it is a plain character vector)
      # keys_tbl <- if (is.data.frame(keys_vec) || inherits(keys_vec, "tbl")) {
      #   keys_vec
      # } else {
      #   tibble(key = keys_vec)
      # }

      ## ----------------------------------------------------------------
      ## Find the unnamed dataframe inside `data` that has the same number
      ## of rows as the key vector.
      ## ----------------------------------------------------------------
      target_n <- n_cols          # expected row count
      df_to_join <- find_df_by_nrow(data, target_n)

      if (is.null(df_to_join)) {
        warning(sprintf("No matching unnamed data.frame for group %s (rows = %d)",
                        g, target_n))
        next
      }

      ## ----------------------------------------------------------------
      ## Ensure the dataframe we are joining has a column named `stan_value`
      ## and a column that can be matched to `col`. Adjust names if needed.
      ## ----------------------------------------------------------------
      df_to_join <- df_to_join %>%
        select(stan_value, human_value)
      ## ----------------------------------------------------------------
      ## Build a temporary tibble for this group that contains the column
      ## index (`col`) and then join the Stan values.
      ## ----------------------------------------------------------------
      tmp <- tibble(group = g,
                    stan_value   = z_df$col[z_df$group == g]) %>%          # all possible indices
        left_join(df_to_join, by = "stan_value")       # bring in stan_value

      result_list[[as.character(g)]] <- tmp
    }

  final_z_df <- bind_rows(result_list)
