# CRDC Arrest API — Data Dictionary

## Tables
### arrest_summary (LEA grain)
| column | meaning |
|--------|---------|
| LEAID | NCES local education agency id (7-char) |
| lea_name, state_name, lat, lon | from CCD district directory |
| LEA_STATE | USPS state abbreviation |
| YEAR | 15-16 / 17-18 / 21-22 |
| RACE | AM, BL, HI, WH |
| SEX | F, M |
| model_id | nat_m1..nat_m5 / sg_m1..sg_m5 (+ "_mod") |
| subgroup_id | national: == model_id; subgroup: RACE_SEX (e.g. BL_M) |
| n_draws | posterior draws summarized |
| stu_enroll | binomial denominator (enrollment in cell) |
| observed_arrests | raw CRDC arrests (reference) |
| count_median/mean/sd | posterior predicted arrest COUNT |
| count_lower_{50,80,95}/upper | HPD interval bounds (counts) |
| rate_median/mean | count / stu_enroll |
| rate_lower_{50,80,95}/upper | count bounds / stu_enroll |

### state_summary (state grain)
As above, keyed by LEA_STATE (no LEAID/geo). Computed by **draw-wise population
aggregation**: within each draw, sum counts and enrollment across LEAs, compute
the rate, then summarize across draws. NOT the (1|LEA_STATE) random effect.

## Codes
- RACE: AM=American Indian/Alaska Native, BL=Black, HI=Hispanic, WH=White.
- SEX: F, M.
- Models: see /models. Default nat_m2 (national) / sg_m2 (subgroup), both
  most-recent-year + referral_rate.

## National vs. subgroup
National `nat_m*` fit all groups jointly (RACE*SEX); a row is the national model's
prediction for that cell. Subgroup `sg_m*` fit each RACE×SEX separately; query by
race/sex resolves to that group's fit (subgroup_id=RACE_SEX).

## Intervals
HPD (smallest-width) at the requested mass (50/80/95). Rate bounds are count
bounds divided by enrollment.

## Sample restrictions (from models.md)
Total enrollment >= 30; highest grade > 7; arrests/referrals capped at enrollment;
RACE in {AM,BL,HI,WH}; TOTAL not modeled for subgroups; PR excluded.

## Citation
Knowles, J. & Miller, H. (2025). Equity Analysis at a Large Scale. Civilytics.
Data release: civilytics-crdc-arrests-2025.1.
