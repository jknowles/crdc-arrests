# Test exploration

library(targets)
library(brms)
library(dplyr)
library(tidybayes)


mod <- targets::tar_read(nat_m2_mod)
mod <- targets::tar_read(sg_m1_mod)

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
