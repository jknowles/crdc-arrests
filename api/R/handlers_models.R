# Static model registry (from models.md). Default = m2 (recent-year + referral_rate).
.NAT_BASE <- "ARRESTS|trials(stu_enroll) ~ RACE*SEX + (1|LEAID) + (1|LEA_STATE)"
.SG_BASE  <- "ARRESTS|trials(stu_enroll) ~ 1 + (1|LEAID) + (1|LEA_STATE)  [fit per RACE x SEX]"
.MODEL_REGISTRY <- list(
  list(model_id="unified_m1_mod", family="unified", sample="recent-year",
       formula=.NAT_BASE, is_default=FALSE),
  list(model_id="unified_m2_mod", family="unified", sample="recent-year",
       formula="ARRESTS|trials(stu_enroll) ~ RACE*SEX + referral_rate + (1|LEAID) + (1|LEA_STATE)", is_default=TRUE),
  list(model_id="unified_m3_mod", family="unified", sample="three-year",
       formula="ARRESTS|trials(stu_enroll) ~ YEAR + RACE*SEX + (1|LEAID) + (1|LEA_STATE)", is_default=FALSE),
  list(model_id="unified_m4_mod", family="unified", sample="three-year",
       formula="ARRESTS|trials(stu_enroll) ~ YEAR + RACE*SEX + referral_rate + (1|LEAID) + (1|LEA_STATE)", is_default=FALSE),
  list(model_id="unified_m5_mod", family="unified", sample="three-year",
       formula="ARRESTS|trials(stu_enroll) ~ YEAR + RACE*SEX + referral_rate + total_referrals + (1|LEAID) + (1|LEA_STATE)", is_default=FALSE),
  list(model_id="stratified_m1_mod", family="stratified", sample="recent-year",
       formula=.SG_BASE, is_default=FALSE),
  list(model_id="stratified_m2_mod", family="stratified", sample="recent-year",
       formula="ARRESTS|trials(stu_enroll) ~ referral_rate + (1|LEAID) + (1|LEA_STATE)  [per RACE x SEX]", is_default=TRUE),
  list(model_id="stratified_m3_mod", family="stratified", sample="three-year",
       formula="ARRESTS|trials(stu_enroll) ~ YEAR + (1|LEAID) + (1|LEA_STATE)  [per RACE x SEX]", is_default=FALSE),
  list(model_id="stratified_m4_mod", family="stratified", sample="three-year",
       formula="ARRESTS|trials(stu_enroll) ~ YEAR + referral_rate + (1|LEAID) + (1|LEA_STATE)  [per RACE x SEX]", is_default=FALSE),
  list(model_id="stratified_m5_mod", family="stratified", sample="three-year",
       formula="ARRESTS|trials(stu_enroll) ~ YEAR + referral_rate + total_referrals + (1|LEAID) + (1|LEA_STATE)  [per RACE x SEX]", is_default=FALSE)
)

handle_models <- function() ok_envelope(.MODEL_REGISTRY, meta = list(total = 10))
