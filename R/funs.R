# Code

# CRDC collapse

intersect_crdc_ccd <- function(crdc, ccd) {
  ccd$COMBOKEY <- stringr::str_pad(ccd$ncessch_num, width = 12,
                                  side = "left", pad = "0")
  ccd <- ccd |> select(COMBOKEY, highest_grade_offered, lowest_grade_offered, latitude, longitude, enrollment)
  outdf <- inner_join(crdc, ccd, by = join_by(COMBOKEY))
  return(outdf)
}

generate_subset_data <- function(data, race_val, sex_val) {
  subset_data <- data %>%
    filter(RACE == race_val, SEX == sex_val)

  # Ensure all required variables are present and properly formatted
  subset_data <- subset_data %>%
    filter(!is.na(ARRESTS), !is.na(stu_enroll), !is.na(referral_rate), !is.na(total_referrals)) %>%
    filter(stu_enroll > 0) %>%  # Ensure we have valid denominators
    droplevels()  # Remove unused factor levels

  # Convert YEAR to factor if it isn't already, and ensure it has proper levels
  if (!is.factor(subset_data$YEAR)) {
    subset_data$YEAR <- as.factor(subset_data$YEAR)
  }

  # Ensure LEAID is properly formatted for random effects
  if (!is.factor(subset_data$LEAID)) {
    subset_data$LEAID <- as.factor(subset_data$LEAID)
  }

  stan_list <- brms::make_standata(
    ARRESTS | trials(stu_enroll) ~ 1 + YEAR + referral_rate + total_referrals + (1|LEAID),
    family = "binomial",
    data = subset_data,
    threads = brms::threading(2)
  )
  return(stan_list)
}

# Function for stantargets that generates data for each demographic subset
generate_demographic_data <- function(formula, data, n = 1L, threading = 2L) {
  # Define the race/sex combinations
  race_vals <- c("WH", "BL", "AM", "HI")
  sex_vals <- c("M", "F")
  combinations <- expand.grid(race = race_vals, sex = sex_vals, stringsAsFactors = FALSE)

  # Get the combination for this rep (n should be 1-8)
  if (n < 1 || n > nrow(combinations)) {
    stop("n must be between 1 and ", nrow(combinations))
  }

  race_val <- combinations$race[n]
  sex_val <- combinations$sex[n]

  # Filter data for this demographic subset
  subset_data <- data %>%
    filter(RACE == race_val, SEX == sex_val)

  # Ensure all required variables are present and properly formatted
  subset_data <- subset_data %>%
    filter(!is.na(ARRESTS), !is.na(stu_enroll), !is.na(referral_rate), !is.na(total_referrals)) %>%
    filter(stu_enroll > 0) %>%  # Ensure we have valid denominators
    droplevels()  # Remove unused factor levels

  # Convert YEAR to factor if it isn't already, and ensure it has proper levels
  if (!is.factor(subset_data$YEAR)) {
    subset_data$YEAR <- as.factor(subset_data$YEAR)
  }

  # Ensure LEAID is properly formatted for random effects
  if (!is.factor(subset_data$LEAID)) {
    subset_data$LEAID <- as.factor(subset_data$LEAID)
  }

    stan_list <- brms::make_standata(
    formula,
    family = "binomial",
    data = subset_data,
    threads = brms::threading(4)
  )
  # Add metadata for tracking which demographic group this is
  stan_list$.join_data <- paste(race_val, sex_val, sep = "_")

  return(stan_list)
}

crdc_lea_collapse <- function(combined_data) {

  combined_data <- combined_data |> filter(highest_grade_offered >= 7)

  combined_data |>
  select(LEAID, LEA_NAME, YEAR) |>
  distinct_all() |>
  group_by(LEAID) |>
  mutate(last_name = ifelse(any(YEAR == "21-22"),
                            LEA_NAME[YEAR == "21-22"],
                            ifelse(any(YEAR == "17-18"),
                            LEA_NAME[YEAR == "17-18"],
                            LEA_NAME[YEAR == "15-16"]))) |>
  ungroup() |>
  select(LEAID, last_name) |>
  distinct_all() -> lea_names_canonical

combined_data <- left_join(combined_data |> select(-LEA_NAME),
                          lea_names_canonical |>
                            rename(LEA_NAME = last_name),
                          by = join_by(LEAID))

rm(lea_names_canonical)

# Where there are more arrests than students we reduce
  # arrests to be equal to the number of students enrolled
  combined_data$ARRESTS[combined_data$ARRESTS > combined_data$stu_enroll] <-
    combined_data$stu_enroll[combined_data$ARRESTS > combined_data$stu_enroll]
  combined_data$REFERRALS[combined_data$REFERRALS  > combined_data$stu_enroll] <-
    combined_data$stu_enroll[combined_data$REFERRALS  > combined_data$stu_enroll]

# Collapse to district
dist_ref_arr <- combined_data %>%
  group_by(YEAR, LEA_STATE, LEAID, LEA_NAME, RACE, SEX) %>%
  summarize(ARRESTS = sum(ARRESTS),
            REFERRALS = sum(REFERRALS),
            stu_enroll = sum(stu_enroll)) %>%
  mutate(arrest_rate = scaled_rate(ARRESTS, stu_enroll, scale_factor = 1000),
         referral_rate = scaled_rate(REFERRALS, stu_enroll, scale_factor = 1000)) %>%
  group_by(LEA_STATE, LEAID, LEA_NAME) |>
  mutate(total_enroll = sum(stu_enroll[RACE != "TOTAL" &
                                         SEX != "TOTAL"]),
         total_referrals = sum(REFERRALS[RACE != "TOTAL" &
                                         SEX != "TOTAL"]))

}



scaled_rate <- function(numerator, denominator, scale_factor) {
  result <- rep(NA_real_, length(numerator))
  valid <- denominator != 0
  result[valid] <- numerator[valid] / (denominator[valid] /scale_factor)
  zero_denom <- denominator == 0
  result[zero_denom & numerator == 0] <- 0
  result[zero_denom & numerator > 0] <- NA_real_
  result
}

restrict_model_data <- function(data, enrollment_cap = 30, dev_mode = FALSE, year = NULL) {

  if (is.null(year)) {
    data <- data |> filter(RACE %in% c("WH", "BL", "AM", "HI", "TOTAL"))
    data <- data |> filter(total_enroll >= enrollment_cap)
  } else {
    data <- data |> filter(RACE %in% c("WH", "BL", "AM", "HI", "TOTAL")) |>
                     filter(YEAR == year) |>
                    filter(total_enroll >= enrollment_cap)
  }

  # Global filters
  data <- data |> filter(LEA_STATE != "PR")

  if (dev_mode) {
      sampled_leaids <- data |>
      select(LEA_STATE, LEAID) |>
      distinct() |>
      group_by(LEA_STATE) |>
      slice_sample(n = 15) |>  # Sample up to 10, or all if fewer than 10
      pull(LEAID)

    # Filter to only include rows with the sampled LEAIDs
    data <- data |> filter(LEAID %in% sampled_leaids)
  }

  # Shuffle data for better performance parallelizing
  data <- data[sample(nrow(data)),]

  # Where there are more arrests than students we reduce
  # arrests to be equal to the number of students enrolled
  data$ARRESTS[data$ARRESTS > data$stu_enroll] <- data$stu_enroll[data$ARRESTS > data$stu_enroll]
  data$REFERRALS[data$REFERRALS  > data$stu_enroll] <- data$stu_enroll[data$REFERRALS  > data$stu_enroll]

  return(data)

}

make_arrest_priors <- function() {
  wi_priors <- prior(normal(-8, 3), class = "Intercept") +
  prior(cauchy(1, 2), class = "sd", group = "LEAID")


  wi_priors
}
#' Zero out missing values
#'
#' @param x a numeric vector with missing values
#'
#' @return a numeric vector with missing values replaced by 0
#' @export
#'
#' @examples
#' na_zero(1:10)
#' na_zero(c(NA, NA, 2:10))
na_zero <- function(x) {
  x[is.na(x)] <- 0
  return(x)
}


reshape_le_rate_long <- function(sch_referrals, year = "2021-22") {
  # Remove disability categories we won't use
    sch_referrals <- sch_referrals %>%
      select(COMBOKEY:SEX, ARRESTS:stu_enroll)

    sch_referrals_long <- sch_referrals %>%
    mutate(stu_enroll = na_zero(stu_enroll),
          ARRESTS = na_zero(ARRESTS),
          REFERRALS = na_zero(REFERRALS))  %>%
    mutate(arrest_rate = scaled_rate(ARRESTS, stu_enroll, scale_factor = 1000),
          referral_rate = scaled_rate(REFERRALS, stu_enroll, scale_factor = 1000))

    # Aggregate the total for each race across both sexes
  sch_referrals_long_sex <- sch_referrals_long %>%
    mutate(SEX = "TOTAL") %>%
    group_by(COMBOKEY, RACE, SEX) %>%
    summarise(stu_enroll = sum(stu_enroll, na.rm = TRUE),
              ARRESTS = sum(ARRESTS, na.rm = TRUE),
              REFERRALS = sum(REFERRALS, na.rm = TRUE)) %>%
    mutate(arrest_rate = scaled_rate(ARRESTS, stu_enroll, scale_factor = 1000),
          referral_rate = scaled_rate(REFERRALS, stu_enroll, scale_factor = 1000))


  # Aggregate the total for each sex across all races
  sch_referrals_long_race <- sch_referrals_long %>%
    mutate(RACE = "TOTAL") %>%
    group_by(COMBOKEY, RACE, SEX) %>%
    summarise(stu_enroll = sum(stu_enroll, na.rm = TRUE),
              ARRESTS = sum(ARRESTS, na.rm = TRUE),
              REFERRALS = sum(REFERRALS, na.rm = TRUE)) %>%
    mutate(arrest_rate = scaled_rate(ARRESTS, stu_enroll, scale_factor = 1000),
          referral_rate = scaled_rate(REFERRALS, stu_enroll, scale_factor = 1000))

  # Aggregate the total for each school across all races and sexes
  sch_referrals_long_total <- sch_referrals_long %>%
    mutate(RACE = "TOTAL") %>%
    mutate(SEX = "TOTAL") %>%
    group_by(COMBOKEY,
            RACE, SEX) %>%
    summarise(stu_enroll = sum(stu_enroll, na.rm = TRUE),
              ARRESTS = sum(ARRESTS, na.rm = TRUE),
              REFERRALS = sum(REFERRALS, na.rm = TRUE)) %>%
    mutate(arrest_rate = scaled_rate(ARRESTS, stu_enroll, scale_factor = 1000),
          referral_rate = scaled_rate(REFERRALS, stu_enroll, scale_factor = 1000))

  # Stack all of these combinations together
  sch_referrals_long <- bind_rows(
    sch_referrals_long,
    sch_referrals_long_race,
    sch_referrals_long_sex,
    sch_referrals_long_total
  )

  rm(sch_referrals_long_race, sch_referrals_long_sex,
    sch_referrals_long_total)

  # Add a year variable
  sch_referrals_long$YEAR <- year
  sch_referrals_long <- sch_referrals_long %>% group_by(COMBOKEY) %>%
  mutate(total_arrests = ARRESTS[RACE == "TOTAL" & SEX == "TOTAL"],
         total_referrals = REFERRALS[RACE == "TOTAL" & SEX == "TOTAL"],
         total_enroll = stu_enroll[RACE == "TOTAL" & SEX == "TOTAL"])

    return(sch_referrals_long)

}

# TODO improve validations
validate_le <- function(sch_referrals_long, year = "21-22") {
  if (year == "21-22"){
    all(table(sch_referrals_long$RACE, sch_referrals_long$SEX) == 98010)
    sum(sch_referrals_long$ARRESTS[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"]) == 34846
    sum(sch_referrals_long$REFERRALS[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"]) == 209353
    sum_a <- sum(sch_referrals_long$stu_enroll[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"])
    sum_b <- sum(sch_referrals_long$total_enroll)/24 # 24 subgroup combinations
    sum_a == sum_b
    sum_a <- sum(sch_referrals_long$ARRESTS[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"])
    sum_b <- sum(sch_referrals_long$total_arrests)/24 # 24 subgroup combinations
    sum_a == sum_b
    sum_a <- sum(sch_referrals_long$REFERRALS[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"])
    sum_b <- sum(sch_referrals_long$total_referrals)/24 # 24 subgroup combinations
    sum_a == sum_b
  } else if(year == "17-18") {
    table(sch_referrals_long$RACE, sch_referrals_long$SEX)
    # Check that we did our sums correctly
    # These are our totals from above
    sum(sch_referrals_long$stu_enroll[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"])
    sum(sch_referrals_long$ARRESTS[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"]) == 52300
    sum(sch_referrals_long$REFERRALS[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"]) == 221303
    # Enroll
    sum_a <- sum(sch_referrals_long$stu_enroll[sch_referrals_long$RACE == "TOTAL" & sch_referrals_long$SEX == "TOTAL"])
    sum_b <- sum(sch_referrals_long$total_enroll)/24 # 24 subgroup combinations
    sum_a == sum_b

  } else if(year == "15-16"){

  }
  return(TRUE)

}

incomplete_referrals <- function(sch_ref, year){
    sch_ref <- sch_ref %>% select(COMBOKEY:last_col())
    names(sch_ref) <- gsub("_IDEA_", "_", names(sch_ref))

  incomplete_referrals <- sch_ref %>% select(!matches("TOT_")) %>%
  select(!matches("_504_")) %>%
  # select(!matches("_IDEA_")) %>%
  select(!matches("_LEP_")) %>%
  pivot_longer(cols = matches("SCH_DIS"), names_prefix = "SCH_",
               names_to = c("DISAB", "REF_TYPE", "RACE", "SEX"),
               names_sep = "_")


  if (year == "21-22"){
    incomplete_referrals$RESERVE_CODE <- crdc_missing_code_2122(incomplete_referrals$value)
  } else if (year == "17-18") {
        incomplete_referrals$RESERVE_CODE <- crdc_missing_code(incomplete_referrals$value)
  } else {
      incomplete_referrals$RESERVE_CODE <- crdc_missing_code_1516(incomplete_referrals$value)
    }

    incomplete_referrals <- incomplete_referrals |>
      filter(!RESERVE_CODE  %in% c("Not Missing", "Not Applicable / Skipped"))
    return(incomplete_referrals)
}

reshape_le <- function(sch_ref, year = "21-22") {
  if (year == "15-16") {
    sch_ref$LEAID <-   stringr::str_pad(sch_ref$LEAID,
      width = 7, side = "left", pad = "0")
    sch_ref$COMBOKEY <- fix_1516_crdc_combokey(sch_ref$LEAID,
                                            sch_ref$SCHID)
    sch_ref <- sch_ref %>% select(LEA_STATE:COMBOKEY,
         matches("SCH_DISCWODIS_REF"),
         matches("SCH_DISCWDIS_REF"),
         matches("SCH_DISCWODIS_ARR"),
         matches("SCH_DISCWDIS_ARR"))

  }


  # Drop non COMBOKEY identifier columns
  sch_ref <- sch_ref %>% select(COMBOKEY:last_col())
  names(sch_ref) <- gsub("_IDEA_", "_", names(sch_ref))
  # Do the same thing as above, but overwrite the reserve values with NA and keep all schools
  sch_ref %>% select(!matches("TOT_")) %>%
    select(!matches("_504_")) %>%
    select(!matches("_LEP_")) %>%
    select(!matches("_EL_")) %>%
    pivot_longer(cols = matches("SCH_DIS"), names_prefix = "SCH_",
                names_to = c("DISAB", "REF_TYPE", "RACE", "SEX"),
                names_sep = "_") %>%
    group_by(COMBOKEY, DISAB, REF_TYPE, RACE, SEX) %>%
    summarize(referrals = sum(crdc_sub(value), na.rm = TRUE)) -> sch_referrals
  # status are wide
  sch_referrals %>% pivot_wider(names_from = c(DISAB, REF_TYPE),
                                values_from = referrals,
                                names_sep = "_") -> sch_referrals

  # Sum arrests/referrals across disability categories
  sch_referrals$ARRESTS <- sch_referrals$DISCWDIS_ARR + sch_referrals$DISCWODIS_ARR
  sch_referrals$REFERRALS <- sch_referrals$DISCWDIS_REF + sch_referrals$DISCWODIS_REF

  # Create a school-level total for all arrests and all referrals
  sch_referrals %>%
    group_by(COMBOKEY) %>%
    mutate(total_arrests = sum(ARRESTS),
          total_referrals = sum(REFERRALS)) -> sch_referrals

  return(sch_referrals)

}

validate_enrollments <- function(data, year) {
  # TODO: Increase the resolution of this validation
  sch_pops <- data
  good_val <- sum(sch_pops$stu_enroll, na.rm = TRUE)
  sch_pops <- na.omit(sch_pops)
    #summary(sch_pops$stu_enroll)
    sch_pops %>% group_by(COMBOKEY) %>%
      mutate(total_enroll = sum(stu_enroll, na.rm = TRUE)) -> sch_pops

  if (year != "17-18"){
    stopifnot(good_val == sum(sch_pops$stu_enroll))
  } else {
    stopifnot(sum(sch_pops$total_enroll) / 14 == sum(sch_pops$stu_enroll, na.rm = TRUE))
  }
}

incomplete_enrollments <- function(data, year) {
  enrollment <- data
    if (year == "15-16") {
    enrollment$COMBOKEY <- fix_1516_crdc_combokey(enrollment$LEAID,
                                            enrollment$SCHID)
      enrollment <- enrollment %>%
        select(LEA_STATE:COMBOKEY, matches("SCH_ENR"))
  }
    enrollment <- enrollment %>% select(COMBOKEY:last_col())

    # Now we exclude counts that will lead to duplication for features we will not use.
    # We want to only retain student counts by SEX and RACE and then pivot the data long
    # so each school has a row for each combination of SEX and RACE
    enrollment %>% select(!matches("TOT_")) %>%
      select(!matches("JJ")) %>%
      select(!matches("_504")) %>%  # drop in all years to avoid double counting
      select(!matches("PSENR")) %>%
      select(!matches("_PS504ENR")) |> #drop in 2021-22
      select(!matches("LEPENR")) %>% select(!matches("LEPPROGENR")) %>%
      select(!matches("_ELENR_")) |> #drop in 2021-22
      select(!matches("_ENR_EL_")) |>
      select(!matches("_PSELPROGENR")) |> #drop in 2021-22
      select(!matches("_ELPROGENR")) |> #drop in 2021-22
      select(!matches("PSELENR_")) |> #drop in 2021-22
      select(!matches("IDEAENR")) %>%
      select(!matches("ENR_IDEA")) %>%
      select(!matches("_LEP_")) %>%
      tidyr::pivot_longer(cols = matches("SCH_ENR_"), names_prefix = "SCH_ENR_",
                  names_to = c("RACE", "SEX"),
                  names_sep = "_") %>% as.data.frame -> sch_pops

  if (year == "21-22"){
      sch_pops <- sch_pops |> filter(SEX != "X")
      incomplete_enrollment <- sch_pops[crdc_missing_code_2122(sch_pops$value) != "Not Missing",]
      incomplete_enrollment$RESERVE_CODE <- crdc_missing_code_2122(incomplete_enrollment$value)
  } else if (year == "17-18") {
      incomplete_enrollment <- sch_pops[crdc_missing_code(sch_pops$value) != "Not Missing",]
      incomplete_enrollment$RESERVE_CODE <- crdc_missing_code(incomplete_enrollment$value)
  } else {
      incomplete_enrollment <- sch_pops[crdc_missing_code_1516(sch_pops$value) != "Not Missing",]
      incomplete_enrollment$RESERVE_CODE <- crdc_missing_code_1516(incomplete_enrollment$value)
  }
  return(incomplete_enrollment)

}

# Recode race
crdc_race_recode <- function(x) {
  x[x == "WH"] <- "White"
  x[x == "BL"] <- "Black"
  x[x == "TOTAL"] <- "Total"
  x[x == "HI"] <- "Hispanic"
  x[x == "AM"] <- "Amer. Ind."
  return(x)
}

fix_1516_crdc_combokey <- function(LEAID, SCHID) {
  # Pad to the left
  LEAID <- stringr::str_pad(LEAID, width = 7, side = "left", pad = "0")
  #table(nchar(sch_crdc$SCHID))
  # Pad schid to the left
  SCHID <- stringr::str_pad(SCHID, width = 5, side = "left", pad = "0")
  COMBOKEY2 <- paste0(LEAID, SCHID)
  stopifnot(all(nchar(COMBOKEY2) == 12))
  return(COMBOKEY2)
}

sch_denom_enroll <- function(enrollment, year = "21-22") {
  if (year == "15-16") {
     enrollment$COMBOKEY <- fix_1516_crdc_combokey(enrollment$LEAID,
                                            enrollment$SCHID)
    enrollment$LEAID <-   stringr::str_pad(enrollment$LEAID, width = 7, side = "left", pad = "0")
      enrollment <- enrollment %>%
        select(LEA_STATE:COMBOKEY, matches("SCH_ENR"))

  }
  enrollment <- enrollment %>% select(COMBOKEY:last_col())

  # Now we exclude counts that will lead to duplication for features we will not use.
  # We want to only retain student counts by SEX and RACE and then pivot the data long
  # so each school has a row for each combination of SEX and RACE
  enrollment %>% select(!matches("TOT_")) %>%
    select(!matches("JJ")) %>%
    select(!matches("_504")) %>%  # drop in all years to avoid double counting
    select(!matches("PSENR")) %>%
    select(!matches("_PS504ENR")) |> #drop in 2021-22
    select(!matches("LEPENR")) %>% select(!matches("LEPPROGENR")) %>%
    select(!matches("_ELENR_")) |> #drop in 2021-22
    select(!matches("_ENR_EL_")) |>
    select(!matches("_PSELPROGENR")) |> #drop in 2021-22
    select(!matches("_ELPROGENR")) |> #drop in 2021-22
    select(!matches("PSELENR_")) |> #drop in 2021-22
    select(!matches("IDEAENR")) %>%
    select(!matches("ENR_IDEA")) %>%
    select(!matches("_LEP_")) %>%
    tidyr::pivot_longer(cols = matches("SCH_ENR_"), names_prefix = "SCH_ENR_",
                names_to = c("RACE", "SEX"),
                names_sep = "_") %>% as.data.frame -> sch_pops


  # Replace missing data/reserve codes with an NA
  if (year == "15-16") {
    sch_pops$stu_enroll <- crdc_sub_1516(sch_pops$value)
  } else {
    sch_pops$stu_enroll <- crdc_sub(sch_pops$value)
  }

  sch_pops$value <- NULL

  xval <- sum(sch_pops$stu_enroll[sch_pops$SEX == "X"], na.rm = TRUE)
  cli::cli_alert("Removing {xval} students with non-binary sex.")

  sch_pops <- sch_pops |>
    filter(SEX != "X")

  # TODO: for 2015-16 we need to do a lot more data massaging

  return(sch_pops)

}

get_crdc_sch_data <- function(enrollment, year = NULL) {
  sch_join_data <- enrollment %>% select(LEA_STATE, LEAID, LEA_NAME,
                                       SCHID, SCH_NAME, COMBOKEY, JJ) %>%
  distinct(.keep_all = TRUE)
   if (year == "15-16") {
     sch_join_data$LEAID <-   stringr::str_pad(sch_join_data$LEAID, width = 7,
      side = "left", pad = "0")
    sch_join_data$COMBOKEY <- fix_1516_crdc_combokey(enrollment$LEAID,
                                            enrollment$SCHID)
   }
  return(sch_join_data)

}
# SKip and reserve codes for CRDC
# Public Use Data File User's Manual
# https://ocrdata.ed.gov/assets/downloads/2017-18%20CRDC%20Public-Use%20Data%20File%20Manual.pdf
crdc_sub <- function(x) {
  # These are truly missing
  x[x == -4] <- NA
  x[x == -5] <- NA
  x[x == -6] <- NA
  # For arrests and referrals these skip patterns occur
  # -9 is most common, NotApplicable/Skipped
  x[x == -9] <- NA
  # -3 is least common and represents a specific failure in skip logic for the arrest/referral (ARRS) module
  x[x == -3] <- NA
  # 11 and 12 represent suppression
  x[x == -11] <- NA # suppressed in 2017-18
  x[x == -12] <- NA # suppressed in 2021-22
  x[x == -13] <- NA
  return(x)
}

# 2015-16 skip and reserve codes
crdc_sub_1516 <- function(x) {
  # These are truly missing
  x[x == -8] <- NA
  x[x == -9] <- NA
  # System error
  x[x == -7] <- NA
  # Action plan and force certified
  x[x == -6] <- NA
  x[x == -5] <- NA
  # Suppressed values
  x[x == -2] <- NA
  return(x)
}

fix_1516_crdc_combokey <- function(LEAID, SCHID) {
  # Pad to the left
  LEAID <- stringr::str_pad(LEAID, width = 7, side = "left", pad = "0")
  #table(nchar(sch_crdc$SCHID))
  # Pad schid to the left
  SCHID <- stringr::str_pad(SCHID, width = 5, side = "left", pad = "0")
  COMBOKEY2 <- paste0(LEAID, SCHID)
  stopifnot(all(nchar(COMBOKEY2) == 12))
  return(COMBOKEY2)
}


na_sum <- function(x) {
  x[is.na(x)] <- 0
  return(sum(x))
}


match_test <- function(x, y, distinct = TRUE) {
  if (distinct) {
    x <- unique(x)
    y <- unique(y)
    cat("**** Distinct Matches ****")
    cat("\n")

  }

  xiny <- sum(x %in% y)
  total_x <- length(x)

  yinx <- sum(y %in% x)
  total_y <- length(y)

  cat("**** Match Summary ****")
  cat("\n")
  cat("X in Y")
  cat("\n")
  cat(paste0("Of the ", total_x, " X values, ", xiny, " (",
             100*round(xiny/total_x, 2), "%) were matched."))
  cat("\n")
  cat("********************************************")
  cat("\n")
  cat("Y in X")
  cat("\n")
  cat(paste0("Of the ", total_y, " Y values, ", yinx, " (",
             100*round(yinx/total_y, 2), "%) were matched."))
  cat("\n")
  cat("******************************************")

}

crdc_missing_code <- function(x) {
  y <- rep("Not Missing", length(x))
  y[x == -3] <- "Skip Logic Failure"
  y[x == -4] <- "Missing Optional Data"
  # What is an action plan?
  y[x == -5] <- "Action Plan"
  # Action plans provide steps on how LEA will collect this in the next
  # administration. Force certified submission do not have action plans.
  # LEAs that are force certified are found in Public-Use Data File User's Manual
  y[x == -6] <- "Force Certified"
  y[x == -8] <- "EdFacts Missing Data"
  y[x == -9] <- "Not Applicable / Skipped"
  y[x == -13] <- "Missing DIND skip logic"

  y[x == -11] <- "Suppressed Data"
  return(y)


}

crdc_missing_code_2122 <- function(x) {
  y <- rep("Not Missing", length(x))
  y[x == -3] <- "Skip Logic Failure"
  y[x == -4] <- "Missing Optional Data"
  # What is an action plan?
  y[x == -5] <- "Action Plan"
  # Action plans provide steps on how LEA will collect this in the next
  # administration. Force certified submission do not have action plans.
  # LEAs that are force certified are found in Public-Use Data File User's Manual
  y[x == -6] <- "Force Certified"
  y[x == -8] <- "EdFacts Missing Data"
  y[x == -9] <- "Not Applicable / Skipped"
  y[x == -13] <- "Missing DIND skip logic"
  y[x == -12] <- "Suppressed Data"
  return(y)


}


crdc_missing_code_1516 <- function(x) {
  y <- rep("Not Missing", length(x))
  y[x == -2] <- "Small Cell Suppression"
  # What is an action plan?
  y[x == -5] <- "Action Plan"
  # Action plans provide steps on how LEA will collect this in the next
  # administration. Force certified submission do not have action plans.
  # LEAs that are force certified are found in Public-Use Data File User's Manual
  y[x == -6] <- "Force Certified"
  y[x == -7] <- "System Error"
  y[x == -8] <- "EdFacts Missing Data"
  y[x == -9] <- "Not Applicable / Skipped"
  return(y)
}

# https://stackoverflow.com/questions/4993837/r-invalid-multibyte-string
find_offending_character <- function(x, maxStringLength=256){
  print(x)
  for (c in 1:maxStringLength){
    offendingChar <- substr(x,c,c)
    print(offendingChar) #uncomment if you want the indiv characters printed
    #the next character is the offending multibyte Character
  }
}

parse_model_name <- function(x, prefix, suffix, split = "_") {
  if(length(prefix) > 1) {
    prefix <- paste0(prefix, collapse = "|")
  }
  if(length(suffix) > 1) {
    suffix <- paste0(suffix, collapse = "|")
  }
  x <- gsub(prefix, "", x)
  x <- gsub(suffix, "", x)
  x <- stringr::str_split(x, pattern = split, simplify = TRUE)
  return(x)


}
