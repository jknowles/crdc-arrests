# Calculate cov

# Calculate most recent year COV
# Calculate pooled 3 year COV
# Calculate fitted most recent year COV
# Calculate fitted pooled 3 year COV



library(targets)
library(brms)
library(dplyr)
library(ggdist)
library(marginaleffects)
library(tidybayes)
library(ggridges)
library(ggplot2)
source("R/funs.R")

nat_mod <- targets::tar_read(nat_m2_mod)
sg_mod <- targets::tar_read(sg_m1_mod)

tydata <- targets::tar_read(three_year_data)$data
rdata <- targets::tar_read(recent_data)$data
# arrest rate variable is arrests per 1,000 students

rdata |> filter(RACE != "TOTAL") |>
  group_by(RACE, SEX) |>
  summarize(enroll = sum(stu_enroll),
            arrests = sum(ARRESTS),
            mean_arr = mean(arrest_rate),
            sd_arr = sd(arrest_rate)
          ) |>
  mutate(cov_arr = (sd_arr / mean_arr) * 100) |>
  mutate(type = "One year") -> base_cov

tydata |>
  filter(RACE != "TOTAL") |>
  group_by(LEA_STATE, LEAID, LEA_NAME, RACE, SEX) |>
  summarize(
    enroll = sum(stu_enroll),
    arrests = sum(ARRESTS),
  ) |>
    mutate(arrest_rate = arrests / (enroll / 1000)) |>
    filter(enroll > 0 ) |> #16232 records with 0 enrollment
  group_by(RACE, SEX) |>
  summarize(enroll = sum(enroll),
            arrests = sum(arrests),
            mean_arr = mean(arrest_rate),
            sd_arr = sd(arrest_rate)) |>
  mutate(cov_arr = (sd_arr / mean_arr) * 100) |>
  mutate(type = "Pooled 3 year") -> pooled_cov


# Let's group by year now
tydata |>
  filter(RACE != "TOTAL") |>
    filter(stu_enroll > 0 ) |> #16232 records with 0 enrollment
  group_by(YEAR, RACE, SEX) |>
  summarize(enroll = sum(stu_enroll),
            arrests = sum(ARRESTS),
            mean_arr = mean(arrest_rate),
            sd_arr = sd(arrest_rate)) |>
  mutate(cov_arr = (sd_arr / mean_arr) * 100) |>
  arrange(RACE, SEX, YEAR)



# Fitted values for most recent year
nat_mod <- targets::tar_read(nat_m1_mod)

z <- predict(nat_mod, summary = TRUE, robust = TRUE, cores = 8)
rfit_data <- cbind(rdata, z)


rfit_data |> filter(RACE != "TOTAL") |>
  group_by(RACE, SEX) |>
  summarize(enroll = sum(stu_enroll),
            arrests = sum(ARRESTS),
            mean_arr = mean(Estimate),
            sd_arr = sd(Estimate)
          ) |>
  mutate(cov_arr = (sd_arr / mean_arr) * 100) |>
  mutate(type = "nat_m1") -> fitted_cov


# Let's fit a subgroup model sg_m1_mod  sg_m4_mod

# Basic mode
#sg_mod <- targets::tar_read(sg_m1_mod)


basic_sg_mod_cov <- calculate_model_cov_summaries(targets::tar_read(sg_m1_mod), ndraws = 500, type = "sg_m1")
full_sg_mod_cov <- calculate_model_cov_summaries(targets::tar_read(sg_m4_mod), ndraws = 500, type = "sg_m4")


# ONHOLD THIS TAKES FOREVER
# Fitted values pooled for three years
nat_mod <- targets::tar_read(nat_m2_mod)
z <- predict(nat_mod, newdata = rdata |> mutate(YEAR == "21-22"),
        summary = TRUE, robust = TRUE, cores = 8, draws = 300)
rfit_data <- cbind(rdata, z)


rfit_data |> filter(RACE != "TOTAL") |>
  group_by(RACE, SEX) |>
  summarize(enroll = sum(stu_enroll),
            arrests = sum(ARRESTS),
            mean_arr = mean(Estimate),
            sd_arr = sd(Estimate)
          ) |>
  mutate(cov_arr = (sd_arr / mean_arr) * 100) |>
  mutate(type = "nat_m2") -> fitted2_cov

# Now try three year fits pooled
# This will take some time since this refits/reruns the model to get predictions
z <- predict(nat_mod, summary = TRUE, robust = TRUE, cores = 16, draws = 300)
tyfit_data <- cbind(tydata, z)


tyfit_data |>
  filter(RACE != "TOTAL") |>
  group_by(LEA_STATE, LEAID, LEA_NAME, RACE, SEX) |>
  summarize(
    enroll = sum(stu_enroll),
    arrests = sum(Estimate),
  ) |>
    mutate(arrest_rate = arrests / (enroll / 1000)) |>
    filter(enroll > 0 ) |> #16232 records with 0 enrollment
  group_by(RACE, SEX) |>
  summarize(enroll = sum(enroll),
            arrests = sum(arrests),
            mean_arr = mean(arrest_rate),
            sd_arr = sd(arrest_rate)) |>
  mutate(cov_arr = (sd_arr / mean_arr) * 100) |>
  mutate(type = "nat_m2_pooled") ->  fitted3_cov


cov_results_frame <- bind_rows(
  base_cov,
  pooled_cov,
  fitted_cov,
  fitted2_cov,
  fitted3_cov,
  basic_sg_mod_cov,
  full_sg_mod_cov
) |>
  mutate(type = factor(type, levels = c("One year", "Pooled 3 year", "nat_m1", "nat_m2", "nat_m2_pooled", "sg_m1", "sg_m4"), ordered = TRUE))

ggplot(cov_results_frame |> filter(RACE != "TO"),
      aes(x = type, y = cov_arr)) +
        geom_col() +
        geom_text(aes(label = round(cov_arr, 0)), vjust = -1) +
        facet_wrap(RACE ~ SEX) +
        scale_y_continuous("COV (%)", expand = expansion(mult = c(0, 0.1))) +
        labs(x = "", title = "COV of District-Subgroup Arrest Rate") +
        civilytics::theme_civilytics() +
        theme(axis.text.x = element_text (angle = 15))




# Let's group by year now
tyfit_data |>
  filter(RACE != "TOTAL") |>
    filter(stu_enroll > 0 ) |> #16232 records with 0 enrollment
  group_by(YEAR, RACE, SEX) |>
  summarize(enroll = sum(stu_enroll),
            arrests = sum(Estimate),
            mean_arr = mean(arrest_rate),
            sd_arr = sd(arrest_rate)) |>
  mutate(cov_arr = (sd_arr / mean_arr) * 100) |>
  arrange(RACE, SEX, YEAR)


# Then try subgroup models


tydata %>%
  rename(enroll = stu_enroll) |>
  group_by(LEA_STATE, LEAID, LEA_NAME, RACE, SEX) |>
  select(-YEAR) |>
  summarize_all(sum) |>
  mutate(arrest_rate = ARRESTS / (enroll /1000)) |>
  mutate(referral_rate = REFERRALS / (enroll / 1000)) |>
  group_by(LEA_STATE, LEAID, LEA_NAME) |>
  mutate(total_enroll = sum(enroll[RACE == "TOTAL"]),
         total_arrests = sum(ARRESTS[RACE == "TOTAL"]),
         total_referrals = sum(REFERRALS[RACE == "TOTAL"])
  ) -> tabdf

total_enroll_quint <- quantile(tabdf$total_enroll[tabdf$RACE == "TOTAL"],
         probs = seq(0, 1,0.2))

# cut by enrollment quintiles


plotdf <- tabdf %>%
  mutate(size = cut(total_enroll, total_enroll_quint, ordered_result = TRUE)
  ) %>%
  mutate(size = as.numeric(size)) %>%
  #filter(SEX == "TOTAL") %>%
  filter(!is.na(size)) %>%
  group_by(size, RACE, SEX) %>%
  summarize(count = n(),
            all_enroll = sum(total_enroll),
            mean_arr = mean(arrest_rate, na.rm =TRUE),
            sd_arr = sd(arrest_rate, na.rm = TRUE),
            mean_ref = mean(referral_rate, na.rm = TRUE),
            sd_ref = sd(referral_rate, na.rm = TRUE)) %>%
  mutate(cov_arrests = sd_arr / mean_arr * 100,
         cov_referrals = sd_ref / mean_ref * 100)



# Add colors
color_fill_values <- c("WH" = "#c92d0e", "BL" = "#020684",
                       "TOTAL" = "#ff8f43", "HI" = "#0791b6")
color_fill_values2 <- c("White" = "#c92d0e", "Black" = "#020684",
                        "Total" = "#ff8f43", "Hispanic" = "#0791b6")

# Recode race
crdc_race_recode <- function(x) {
  x[x == "WH"] <- "White"
  x[x == "BL"] <- "Black"
  x[x == "TOTAL"] <- "Total"
  x[x == "HI"] <- "Hispanic"
  return(x)
}

plotdf$race_lab <- crdc_race_recode(plotdf$RACE)


p1 <- ggplot(plotdf[plotdf$RACE %in% c("BL", "WH", "TOTAL", "HI"),],
       aes(x = size, y = cov_arrests/100, color = race_lab, group = race_lab)) +
  geom_smooth(method = "loess", show.legend = FALSE) +
  geom_point(size = 4) +
  scale_color_manual(values = color_fill_values2) +
  scale_y_continuous(labels = scales::label_percent(big.mark = ","), limits = c(0, 25)) +
  civilytics::theme_civilytics(font_size = 14) +
  theme(legend.position = "bottom") +
  labs(x = "Total Enrollment Quintile",
       title = "Arrests",
       y = "CV (% scale)",
       color = "Race / Ethnicity")
