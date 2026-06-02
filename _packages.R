# Dependency declarations for renv discovery ONLY (not executed by the pipeline).
# _targets.R loads several packages via tar_option_set(packages=) as bare strings,
# and uses cmdstanr only as backend="cmdstanr" — renv's static scan misses those.
# Listing them here ensures renv.lock captures the full runtime closure.
library(targets)
library(tarchetypes)
library(tibble)
library(dplyr)
library(tidyr)
library(knitr)
library(qs2)
library(quarto)
library(brms)
library(cmdstanr)
library(crew)
library(future.callr)
library(educationdata)
library(DBI)
library(duckdb)
library(posterior)
library(tidybayes)
