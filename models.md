## Sample restrictions

Total enrollment must be greater than or equal to 30, minimum enrollment in the 21-22 arrest rate top 10
Where there are more referrals or arrests than students, we reduce arrests/referrals to be the number of students
Only fitting for RACE %in% c("WH", "BL", "AM", "HI", "TOTAL")
For subgroup specific models we do not fit for TOTAL


## Models to run

### Full Samples - 3 year

1. Intercept  + YEAR + (1|LEAID)
- Baseline model with multiple years
2. Intercept + YEAR + RACE X SEX fixed effects + (1|LEAID)
- Baseline model with multiple years with global varying risk rates
3. Intercept + YEAR + RACE x SEX fixed effects + REFERRALS + (1|LEAID)
- Baseline model with multiple years with adjustment for number of referrals
4. Intercept + YEAR + RACE x SEX fixed effects + REFERRALS + total_referrals + (1|LEAID)
- Baseline model with multiple years with adjustment for number of referrals for specific group and total referral-ness of the entire LEAID

### Full Samples - 1 year (most recent)

1. Intercept + (1|LEAID)
- Baseline model
2. Intercept + RACE X SEX fixed effects + (1|LEAID)
- Baseline model with global varying risk rates
3. Intercept + RACE x SEX fixed effects + REFERRALS + (1|LEAID)
- Baseline model with adjustment for number of referrals
4. Intercept + RACE x SEX fixed effects + REFERRALS + total_referrals + (1|LEAID)
- Baseline model with adjustments for number of referrals for specific group and total referral-ness of the entire LEAID

### Subset models

1. Intercept + YEAR only
2. Intercept + YEAR + REFERRALS
3. Intercept + YEAR + REFERRALS + STATE?
