# Build the LEA-level dimension table (names + geography) used for lookup and
# joined into the API summaries. Source: CCD school-district directories.

# FIPS state code -> USPS abbreviation. Minimal map; extend as needed.
.fips_to_state <- c(
  "01"="AL","02"="AK","04"="AZ","05"="AR","06"="CA","08"="CO","09"="CT",
  "10"="DE","11"="DC","12"="FL","13"="GA","15"="HI","16"="ID","17"="IL",
  "18"="IN","19"="IA","20"="KS","21"="KY","22"="LA","23"="ME","24"="MD",
  "25"="MA","26"="MI","27"="MN","28"="MS","29"="MO","30"="MT","31"="NE",
  "32"="NV","33"="NH","34"="NJ","35"="NM","36"="NY","37"="NC","38"="ND",
  "39"="OH","40"="OK","41"="OR","42"="PA","44"="RI","45"="SC","46"="SD",
  "47"="TN","48"="TX","49"="UT","50"="VT","51"="VA","53"="WA","54"="WV",
  "55"="WI","56"="WY"
)

.state_names <- c(
  AL="Alabama",AK="Alaska",AZ="Arizona",AR="Arkansas",CA="California",
  CO="Colorado",CT="Connecticut",DE="Delaware",DC="District of Columbia",
  FL="Florida",GA="Georgia",HI="Hawaii",ID="Idaho",IL="Illinois",IN="Indiana",
  IA="Iowa",KS="Kansas",KY="Kentucky",LA="Louisiana",ME="Maine",MD="Maryland",
  MA="Massachusetts",MI="Michigan",MN="Minnesota",MS="Mississippi",MO="Missouri",
  MT="Montana",NE="Nebraska",NV="Nevada",NH="New Hampshire",NJ="New Jersey",
  NM="New Mexico",NY="New York",NC="North Carolina",ND="North Dakota",OH="Ohio",
  OK="Oklahoma",OR="Oregon",PA="Pennsylvania",RI="Rhode Island",
  SC="South Carolina",SD="South Dakota",TN="Tennessee",TX="Texas",UT="Utah",
  VT="Vermont",VA="Virginia",WA="Washington",WV="West Virginia",WI="Wisconsin",
  WY="Wyoming"
)

#' Build the district dimension table from a list of per-year CCD directories.
#'
#' @param ccd_list list of data frames (one per CRDC year) from the CCD
#'   school-districts directory. Each must have: leaid, lea_name, fips,
#'   latitude, longitude, enrollment, year.
#' @return data.frame with one row per LEAID: LEAID, lea_name, LEA_STATE,
#'   state_name, lat, lon, enrollment. Latest available year's name/geo wins.
build_district_dim <- function(ccd_list) {
  stopifnot(
    is.list(ccd_list),
    length(ccd_list) > 0,
    all(vapply(ccd_list, is.data.frame, logical(1)))
  )
  combined <- do.call(rbind, lapply(ccd_list, function(d) {
    data.frame(
      LEAID      = formatC(as.integer(d$leaid), width = 7, flag = "0"),
      lea_name   = as.character(d$lea_name),
      fips       = formatC(as.integer(d$fips),  width = 2, flag = "0"),
      lat        = as.numeric(d$latitude),
      lon        = as.numeric(d$longitude),
      enrollment = as.integer(d$enrollment),
      year       = as.integer(d$year),
      stringsAsFactors = FALSE
    )
  }))
  # latest year per LEAID wins
  combined <- combined[order(combined$LEAID, -combined$year), ]
  district_dim_df <- combined[!duplicated(combined$LEAID), ]
  district_dim_df$LEA_STATE  <- unname(.fips_to_state[district_dim_df$fips])
  if (any(is.na(district_dim_df$LEA_STATE))) {
    warning("Unmapped FIPS code(s) -> NA LEA_STATE; extend .fips_to_state if needed.")
  }
  district_dim_df$state_name <- unname(.state_names[district_dim_df$LEA_STATE])
  district_dim_df <- district_dim_df[, c("LEAID", "lea_name", "LEA_STATE", "state_name",
                                         "lat", "lon", "enrollment")]
  rownames(district_dim_df) <- NULL
  district_dim_df
}
