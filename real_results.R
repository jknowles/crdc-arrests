
library(targets)
library(brms)
library(dplyr)
library(ggplot2)
library(ggdist)
library(marginaleffects)
library(tidybayes)
library(ggridges)


# Generate database of draws
# Do once
# Do once
# source("R/postprocess.R")
# process_all_targets(ndraws = 500, db_path = "export/db/crdc_arrests.duckdb")


library(duckdb)
con <- DBI::dbConnect(duckdb::duckdb(), "export/db/crdc_arrests.duckdb")

tydata <- targets::tar_read(three_year_data)$data
rdata <- targets::tar_read(recent_data)$data

source("R/funs.R")


# Calculate corrected intervals for number of arrests
rdata |>
  filter(YEAR == "21-22") |>
  filter(stu_enroll > 0) |>
  mutate(phat = (2+ARRESTS) / (4+stu_enroll)) |> # agcouli approximation ARRESTS +2 and stu_enroll + 4
  mutate(phat_se = sqrt((phat * (1-phat)/(4+stu_enroll)))) |> # same phat but stu_enroll + 4 here
  mutate(sd = phat_se * (4 + stu_enroll)) |> # calculate rate standard error to arrest scale
  mutate(fitted_value = ARRESTS) |>
  mutate(CVp = 100 * sqrt(((1-phat)/(phat*(4+stu_enroll))))) |> # express CVp as percentage, this is a biased estimator in rare events
  # agresti-coull confidence interval for arrests using the adjusted arrest rate
  mutate(ci_upper = (phat + (1.96*phat_se)) * (4 + stu_enroll),
        ci_lower = (phat - (1.96*phat_se)) * (4 + stu_enroll)) |>
            # add rule of three correction
  mutate(ci_upper = ifelse(ARRESTS == 0, 3, ci_upper),  # add 3
        ci_lower = ifelse(ARRESTS == 0, 0, ci_lower)) |>
  mutate(ci_lower = ifelse(ci_lower < 0, 0, ci_lower)) |>
  mutate(model_id = "observed") -> obsv_data

dist_test <- get_prediction_summary(con, confidence_level = 0.95,
      central_tendency = "median", YEAR = "21-22")
dist_test <- dist_test |> mutate(CVp = 100 * (sd / fitted_value)) # express CVp as percentage
dist_test <- dist_test |> select(model_id, LEAID, LEA_STATE, YEAR, RACE, SEX, fitted_value, sd, CVp, ci_lower, ci_upper)

# what to do when all draws from our model are 0 so the standard deviation is 0

plotdf <- inner_join(dist_test, obsv_data |> select(LEA_STATE:stu_enroll, sd, CVp, ci_upper, ci_lower) |>
                                  rename(obsv_sd = sd, obsv_CVP = CVp, obs_upper = ci_upper, obs_lower = ci_lower),
                           by = join_by(LEAID, LEA_STATE, RACE, SEX))

plotdf <- plotdf |>
  mutate(
      fitted_constant = ifelse(sd ==0, 1, 0),
      sd = ifelse(sd == 0, {
    phat <- (fitted_value + 2) / (stu_enroll+4)
    phat_se <- sqrt((phat * (1-phat)/(4+stu_enroll)))
    phat_se * (4 + stu_enroll)
  }, sd)) |>
  mutate(CVp = 100 * (sd / fitted_value)) |>
  mutate(CVp = ifelse(!is.finite(CVp),
        {
          phat <- (fitted_value + 2)  / (stu_enroll+4)
          100 * sqrt(((1-phat)/(phat*(4+stu_enroll))))
        }, CVp))

# spot check non-zero sd and 0 ci by getting draws
get_prediction_draws(con, LEAID = "0100005", RACE = "BL", SEX = "M", YEAR = "21-22", model = "nat_m1_mod")
# TODO: Update to use the median for precision and central tendency throughout
plotdf <- plotdf |>
  mutate(fitted_value = fitted_value / (stu_enroll/1000),
        sd = sd / (stu_enroll/1000),
        obsv_sd = obsv_sd / (stu_enroll / 1000),
      ci_lower = ci_lower / (stu_enroll / 1000),
       ci_upper = ci_upper / (stu_enroll/1000),
      arrest_rate = ARRESTS / (stu_enroll / 1000),
     obs_upper = obs_upper / (stu_enroll / 1000),
    obs_lower = obs_lower /(stu_enroll / 1000)) |> # CVP is not transformed by this
  mutate(covered = if_else(ci_lower <= arrest_rate & ci_upper >= arrest_rate, 1, 0),
        improved_cv = ifelse(CVp < obsv_CVP & is.finite(obsv_CVP), 1, 0),
        obsv_precision = 1 / obsv_sd^2,
        fit_precision = 1 / sd^2 ) |>
        #obsv_precision = 0.0001/((obsv_sd/stu_enroll)^2),
        #fit_precision = 0.0001/((sd/stu_enroll)^2)) |>
  mutate(improved_precision = ifelse(obsv_precision > fit_precision, 0, 1),
        narrower_interval = ifelse((ci_upper - ci_lower) < (obs_upper - obs_lower), 1, 0))

# Makde summary by model
plotdf |>
  group_by(model_id, YEAR) |>
  summarize(count = n(),
            meanCVP = mean(obsv_CVP[is.finite(obsv_CVP)], na.rm = TRUE),
            meanfitCVP = mean(CVp[is.finite(CVp)], na.rm = TRUE),
            obsv_precision = mean(obsv_precision),
            fit_precision = mean(fit_precision),
            #finite = sum(is.finite(obsv_CVP)),
            improved_cv = sum(improved_cv),
            improved_precision = sum(improved_precision),
            improved_interval = sum(narrower_interval),
            covered = sum(covered)) |>
  mutate(per_covered = covered/count, per_improved_cv = improved_cv / count,
      per_narrower = improved_interval / count,
    per_improved_pre = improved_precision / count)


# Let's spotcheck this


table(plotdf$narrower_interval, plotdf$improved_precision)
table(plotdf$narrower_interval, plotdf$improved_cv)

# A lot of the improvement in narrower intervals comes from confidently bounding the upper interval
plotdf |> filter(narrower_interval == 1) |>
      sample_n(10)

# A lot of the improvement in narrower intervals comes from confidently bounding the upper interval
plotdf |> filter(narrower_interval == 1 & ci_upper > 0) |>
      sample_n(10)

# A lot of improvement occurs because when the fitted value sd is 0, we apply the same correction to
# fitted and observed results
plotdf |> filter(narrower_interval == 1 & ci_upper > 0 & fitted_constant == 0) |>
      sample_n(10)

plotdf |> filter(narrower_interval == 1 &  fitted_constant == 1) |>
      sample_n(10)

table(plotdf$narrower_interval[plotdf$fitted_constant == 0], plotdf$improved_precision[plotdf$fitted_constant == 0])
table(plotdf$fitted_constant) |> prop.table()

# Let's look at performance where the model is not a constant
plotdf |>
      filter(fitted_constant == 0) |>
  group_by(model_id, YEAR) |>
  summarize(count = n(),
            meanCVP = mean(obsv_CVP[is.finite(obsv_CVP)], na.rm = TRUE),
            meanfitCVP = mean(CVp[is.finite(CVp)], na.rm = TRUE),
            obsv_precision = mean(obsv_precision),
            fit_precision = mean(fit_precision),
            #finite = sum(is.finite(obsv_CVP)),
            improved_cv = sum(improved_cv),
            improved_precision = sum(improved_precision),
            improved_interval = sum(narrower_interval),
            covered = sum(covered)) |>
  mutate(per_covered = covered/count, per_improved_cv = improved_cv / count,
      per_narrower = improved_interval / count,
    per_improved_pre = improved_precision / count) |>
  select(-meanCVP, -meanfitCVP, -improved_cv, -improved_precision, -improved_interval)

# Let's look at performance where arrests are not 0
plotdf |>
      filter(ARRESTS > 0) |>
  group_by(model_id, YEAR) |>
  summarize(count = n(),
            meanCVP = mean(obsv_CVP[is.finite(obsv_CVP)], na.rm = TRUE),
            meanfitCVP = mean(CVp[is.finite(CVp)], na.rm = TRUE),
            obsv_precision = mean(obsv_precision),
            fit_precision = mean(fit_precision),
            #finite = sum(is.finite(obsv_CVP)),
            improved_cv = sum(improved_cv),
            improved_precision = sum(improved_precision),
            improved_interval = sum(narrower_interval),
            covered = sum(covered)) |>
  mutate(per_covered = covered/count, per_improved_cv = improved_cv / count,
      per_narrower = improved_interval / count,
    per_improved_pre = improved_precision / count) |>
  select(-meanCVP, -meanfitCVP, -improved_cv, -improved_precision, -improved_interval)


sg_m4 <- targets::tar_read("sg_m2_mod")
nat_m2 <- targets::tar_read("nat_m2_mod")




# Get subset
## TODO: Define the 100 largest LEAs

rdata |> group_by(LEA_STATE, LEAID, LEA_NAME) |>
      summarize(total_enroll = sum(stu_enroll),
            total_arrests = sum(ARRESTS)) |>
      arrange(desc(total_enroll)) |>
      ungroup() |>
      slice_head(n= 100) -> big100


rdata |> group_by(LEA_STATE, LEAID, LEA_NAME) |>
      summarize(total_enroll = sum(stu_enroll),
            total_arrests = sum(ARRESTS)) |>
      filter(total_arrests == 0) |>
      arrange(desc(total_enroll)) |>
      ungroup() |>
      slice_head(n= 100) -> big0

bigarresters <- rdata |>
  group_by(LEA_STATE, LEAID, LEA_NAME) |>
      summarize(total_enroll = sum(stu_enroll),
            total_arrests = sum(ARRESTS)) |>
      arrange(desc(total_arrests)) |>
      ungroup() |>
      slice_head(n= 100)


# Summaries for big 100
plotdf |>
      filter(LEAID %in% big100$LEAID) |>
  group_by(model_id, YEAR) |>
  summarize(count = n(),
       #     meanCVP = mean(obsv_CVP[is.finite(obsv_CVP)], na.rm = TRUE),
        #    meanfitCVP = mean(CVp[is.finite(CVp)], na.rm = TRUE),
            obsv_precision = mean(obsv_precision),
            fit_precision = mean(fit_precision),
            #finite = sum(is.finite(obsv_CVP)),
            #Eimproved_cv = sum(improved_cv),
            improved_precision = sum(improved_precision),
            improved_interval = sum(narrower_interval),
            covered = sum(covered)) |>
  mutate(per_covered = covered/count,
      # per_improved_cv = improved_cv / count,
      per_narrower = improved_interval / count,
    per_improved_pre = improved_precision / count)

# summaries for big arresters

plotdf |>
      filter(LEAID %in% bigarresters$LEAID) |>
  group_by(model_id, YEAR) |>
  summarize(count = n(),
       #     meanCVP = mean(obsv_CVP[is.finite(obsv_CVP)], na.rm = TRUE),
        #    meanfitCVP = mean(CVp[is.finite(CVp)], na.rm = TRUE),
            obsv_precision = mean(obsv_precision),
            fit_precision = mean(fit_precision),
            #finite = sum(is.finite(obsv_CVP)),
            #Eimproved_cv = sum(improved_cv),
            improved_precision = sum(improved_precision),
            improved_interval = sum(narrower_interval),
            covered = sum(covered)) |>
  mutate(per_covered = covered/count,
      # per_improved_cv = improved_cv / count,
      per_narrower = improved_interval / count,
    per_improved_pre = improved_precision / count)

# Summaries for big 0


expected_rate<- mean(big100$total_arrests / big100$total_enroll)
plotdf |>
       filter(LEAID %in% big0$LEAID) |>
        ungroup() |>
      group_by(LEAID, LEA_STATE, YEAR, model_id, RACE, SEX) |>
         mutate(expected_value = expected_rate * stu_enroll) |>
      group_by(model_id, YEAR) |>
      summarize(count = n(),
                  model_fitted = sum(fitted_value),
                  model_min = sum(ci_lower),
                  model_max = sum(ci_upper),
                  expected = sum(expected_value)
                  )


# Computation time -------------------------------------------------------
calculate_model_stats(targets::tar_read("nat_m1_mod"))
calculate_model_stats(targets::tar_read("nat_m2_mod"))
calculate_model_stats(targets::tar_read("nat_m3_mod"))
calculate_model_stats(targets::tar_read("nat_m4_mod"))
calculate_model_stats(targets::tar_read("nat_m5_mod"))


#calculate_model_stats(targets::tar_read("sg_m1_mod"))

calculate_model_stats(targets::tar_read("sg_m1_mod")) |>
  summarize(runtime = sum(runtime_minutes),
            parameters = sum(parameters),
            data_rows = sum(data_rows))

calculate_model_stats(targets::tar_read("sg_m2_mod")) |>
  summarize(runtime = sum(runtime_minutes),
            parameters = sum(parameters),
            data_rows = sum(data_rows))

calculate_model_stats(targets::tar_read("sg_m3_mod")) |>
  summarize(runtime = sum(runtime_minutes),
            parameters = sum(parameters),
            data_rows = sum(data_rows))


calculate_model_stats(targets::tar_read("sg_m4_mod")) |>
  summarize(runtime = sum(runtime_minutes),
            parameters = sum(parameters),
            data_rows = sum(data_rows))

calculate_model_stats(targets::tar_read("sg_m5_mod")) |>
  summarize(runtime = sum(runtime_minutes),
            parameters = sum(parameters),
            data_rows = sum(data_rows))


# For states -------------------------------------------------------------

state_test <- get_state_prediction_summary(con)
state_test <- state_test |> mutate(CVp = 100 * (sd / fitted_value)) # express CVp as percentage
state_test <- state_test |> select(model_id, LEA_STATE, YEAR, RACE, SEX, fitted_value, sd, CVp, ci_lower, ci_upper)

rdata |>
  filter(YEAR == "21-22") |>
  #filter(LEA_STATE %in% c("KS", "OK") & RACE %in% c("BL", "WH")) |>
  group_by(LEA_STATE, YEAR, RACE, SEX) |>
  summarize(ARRESTS = sum(ARRESTS),
            stu_enroll = sum(stu_enroll)) |>
  mutate(phat = (2+ARRESTS) / (4+stu_enroll)) |> # agcouli would be ARRESTS +2 and stu_enroll + 4
  mutate(phat_se = sqrt((phat * (1-phat)/(4+stu_enroll)))) |> # same phat but stu_enroll + 4 here
  mutate(sd = phat_se * (4+stu_enroll)) |> # stu_enroll + 4
  mutate(fitted_value = ARRESTS) |>
  mutate(CVp = 100 * sqrt(((1-phat)/(phat*(4+stu_enroll))))) |> # express CVp as percentage, this is a biased estimator in rare events, should we address that? # stu_enroll+ 4
  mutate(ci_upper = (phat + (1.96*phat_se)) * stu_enroll,
        ci_lower = (phat - (1.96*phat_se)) * stu_enroll) |>
  mutate(ci_upper = ifelse(ARRESTS == 0, 3/stu_enroll, ci_upper),
        ci_lower = ifelse(ARRESTS ==0, 0, ci_lower)) |>
  mutate(model_id = "observed") -> obsv_data



plotdf <- left_join(state_test, obsv_data |> select(LEA_STATE:stu_enroll, sd, CVp, ci_upper, ci_lower) |>
                                  rename(obsv_sd = sd, obsv_CVP = CVp, obs_upper = ci_upper, obs_lower = ci_lower),
                           by = join_by(LEA_STATE, YEAR, RACE, SEX))
plotdf |> filter(YEAR == "21-22") |>
  mutate(fitted_value = fitted_value / (stu_enroll/1000),
        sd = sd / (stu_enroll/1000),
        obsv_sd = obsv_sd / (stu_enroll / 1000),
      ci_lower = ci_lower / (stu_enroll / 1000),
       ci_upper = ci_upper / (stu_enroll/1000),
      arrest_rate = ARRESTS / (stu_enroll / 1000),
     obs_upper = obs_upper / (stu_enroll / 1000),
    obs_lower = obs_lower /(stu_enroll / 1000)) |> # CVP is not transformed by this
  mutate(covered = if_else(ci_lower <= arrest_rate & ci_upper >= arrest_rate, 1, 0),
        improved_cv = ifelse(CVp < obsv_CVP & is.finite(obsv_CVP), 1, 0),
        obsv_precision = 1 / obsv_sd^2,
        fit_precision = 1 / sd^2 ) |>
        #obsv_precision = 0.0001/((obsv_sd/stu_enroll)^2),
        #fit_precision = 0.0001/((sd/stu_enroll)^2)) |>
  mutate(improved_precision = ifelse(obsv_precision > fit_precision, 0, 1)) |>
  group_by(model_id, YEAR) |>
  summarize(count = n(),
            meanCVP = mean(obsv_CVP[is.finite(obsv_CVP)], na.rm = TRUE),
            meaanfitCVP = mean(CVp[is.finite(CVp)], na.rm = TRUE),
            obsv_precision = mean(obsv_precision),
            fit_precision = mean(fit_precision),
            #finite = sum(is.finite(obsv_CVP)),
            improved_cv = sum(improved_cv),
            improved_precision = sum(improved_precision),
            covered = sum(covered)) |>
  mutate(per_covered = covered/count, per_improved_cv = improved_cv / count, per_improved_pre = improved_precision / count)
