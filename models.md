## Sample restrictions

Total enrollment must be greater than or equal to 30, minimum enrollment in the 21-22 arrest rate top 10
Where there are more referrals or arrests than students, we reduce arrests/referrals to be the number of students
Only fitting for RACE %in% c("WH", "BL", "AM", "HI", "TOTAL")
For subgroup specific models we do not fit for TOTAL

Remove all schools where highest grade <= 5
Filter out enrollment < grade 6 and prorate enrollment by % < grade 6


## Models to run

### Full Samples - 3 year

1. Intercept  + YEAR + RACE X SEX fixed effects + (1|LEAID)
- Baseline model with multiple years
2. Intercept + YEAR + RACE X SEX fixed effects + (1|LEAID)  + (1|LEA_STATE)
- Baseline model with multiple years with global varying risk rates
3. Intercept + YEAR + RACE x SEX fixed effects + REFERRALS + (1|LEAID)  + (1|LEA_STATE)
- Baseline model with multiple years with adjustment for number of referrals
4. Intercept + YEAR + RACE x SEX fixed effects + REFERRALS + total_referrals + (1|LEAID)  + (1|LEA_STATE)
- Baseline model with multiple years with adjustment for number of referrals for specific group and total referral-ness of the entire LEAID

### Full Samples - 1 year (most recent)

1. Intercept + RACE X SEX fixed effects + (1|LEAID)
- Baseline model
2. Intercept + RACE X SEX fixed effects + (1|LEAID)  + (1|LEA_STATE)
- Baseline model with global varying risk rates
3. Intercept + RACE x SEX fixed effects + REFERRALS + (1|LEAID)  + (1|LEA_STATE)
- Baseline model with adjustment for number of referrals
4. Intercept + RACE x SEX fixed effects + REFERRALS + total_referrals + (1|LEAID)  + (1|LEA_STATE)
- Baseline model with adjustments for number of referrals for specific group and total referral-ness of the entire LEAID

We don't need to explicilty nest LEAID within LEA_STATE because the identifiers
are unique within states.

### Subset models (fit 3 year only version)

1. Intercept + YEAR only + (1|LEAID) # equivalent to 1 above)
2. Intercept + YEAR + (1|LEAID) + (1|LEA_STATE) # equivalent to 2 above)
3. Intercept + YEAR + REFERRALS + (1|LEAID) + (1|LEA_STATE) equivalent to 3 above
4. Intercept + YEAR + REFERRALS + total referrals + (1|LEAID) + (1|LEA_STATE) equiavlent to 4 above


# TODO:

Test state specification

So method 1 from Dixon we don't use explicitly but we could demonstrate as
an example

Method 2 - stratification, we do by race/sex and state

Method 3 -  we incorporate covariates (REFERRALS) and we use information from
other subgroups in the same LEA in the full model case

Method 4 - We use total referrals for all subgroups as a conditioning variable

In addition to Dixon et al's work, we are using the strength of mixed effect
models to "shrink" our estimates in accordance with information learned from
the rest of the country


## Updates:

For the national sample we fit:

1. most recent year + RACE x SEX + (1|LEAID) + (1|STATE)
2. three year data + RACE x SEX + referral_rate + total_referrals + (1|LEAID) + (1|STATE)


For stratfied by subgroup we fit:

1. Most recent year + (1|LEAID) + (1|STATE)
2. Three year + (1|LEAID) + (1|STATE)
3. Most recent year + referral_rate + (1|LEAID) + (1|STATE)
4. Most recent year + referral_rate + total_referrals +  (1|LEAID) + (1|STATE)
5. Three year + referral_rate + total_referrals +  (1|LEAID) + (1|STATE)
