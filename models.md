## Sample restrictions

Total enrollment must be greater than or equal to 30, minimum enrollment in the 21-22 arrest rate top 10
Where there are more referrals or arrests than students, we reduce arrests/referrals to be the number of students
Only fitting for RACE %in% c("WH", "BL", "AM", "HI")
For subgroup specific models we do not fit for TOTAL

Remove all schools where highest grade <= 7
log1p referrals and referral rate

## Models to run

### Unified

For the national sample we fit:

1. most recent year + RACE x SEX + (1|LEAID) + (1|STATE)
2. most recent year + RACE x SEX + referral_rate + (1|LEAID) + (1|STATE)
3. Three year + YEAR + RACE x SEX + (1|LEAID) + (1|STATE)
4. three year data + YEAR + RACE x SEX + referral_rate + (1|LEAID) + (1|STATE)
5. three year data + YEAR + RACE x SEX + referral_rate + total_referrals + (1|LEAID) + (1|STATE)


### Stratified

For stratfied by subgroup we fit:

1. Most recent year + (1|LEAID) + (1|STATE)
2. Most recent year + referral_rate + (1|LEAID) + (1|STATE)
3. Three year + YEAR + (1|LEAID) + (1|STATE)
4. Three year + YEAR + referral_rate + (1|LEAID) + (1|STATE)
5. Three year + YEAR + referral_rate + total_referrals +  (1|LEAID) + (1|STATE)




## Postprocessing

It is faster and easier to load predicted draws from the models into a database
for analysis. To do this, we run:

```r
source("R/postprocess.R")
process_all_targets(ndraws = 500, db_path = "export/db/crdc_arrests.duckdb")
```

This will load the results of the successful model runs into the DuckDB database.
We can then use the predicted draws for analysis.
