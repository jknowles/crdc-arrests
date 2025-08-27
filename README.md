# CRDC Arrest Rates Analysis Pipeline

A [`targets`](https://books.ropensci.org/targets/) pipeline for analyzing arrest rates in US public schools using data from the Civil Rights Data Collection (CRDC). This project fits Bayesian hierarchical models to explore patterns in school-based arrests across three waves of CRDC data (2015-16, 2017-18, and 2021-22 school years).

## Overview

This project quantifies arrest rates at the school district level using national reported data from the U.S. Department of Education's Civil Rights Data Collection. The analysis employs Bayesian hierarchical models to account for the nested structure of students within districts and examines how arrest rates vary by demographic characteristics, time, and disciplinary referral patterns.

## Data Sources

The pipeline uses three waves of CRDC data:
- **2015-16 school year**: Baseline period
- **2017-18 school year**: Mid-period comparison
- **2021-22 school year**: Most recent available data

### Key Variables
- **Arrests**: Student arrests by demographic subgroups
- **Referrals**: Law enforcement referrals by demographic subgroups
- **Enrollment**: Student enrollment by demographic subgroups
- **Demographics**: Race/ethnicity (White, Black, American Indian, Hispanic) and sex (Male, Female)

## Project Structure

```
├── _targets.R              # Main targets pipeline configuration
├── R/
│   └── funs.R              # Custom functions for data processing and modeling
├── models/
│   ├── *.stan              # Stan model files for national-level analysis
│   └── demog/              # Stan models for demographic subgroup analysis
├── combined_eda.qmd        # Exploratory data analysis across all years
├── annual_descriptives_template.qmd  # Annual descriptive reports
└── models.md               # Model specifications and restrictions
```

## Models

The pipeline fits several hierarchical Bayesian models using [`brms`](https://paul-buerkner.github.io/brms/) and [`Stan`](https://mc-stan.org/):

### National Models (3-year data)
1. **Baseline temporal**: `ARRESTS ~ 1 + YEAR + (1|LEAID)`
2. **Demographic effects**: `ARRESTS ~ 1 + YEAR + RACE × SEX + (1|LEAID)`
3. **Referral adjustment**: `ARRESTS ~ 1 + YEAR + RACE × SEX + referral_rate + (1|LEAID)`
4. **Full model**: `ARRESTS ~ 1 + YEAR + RACE × SEX + referral_rate + total_referrals + (1|LEAID)`

### Recent Year Models (2021-22 only)
- Intercept-only model for most recent data: `ARRESTS ~ 1 + (1|LEAID)`

### Demographic Subgroup Models
- Separate models for each race/sex combination (8 subgroups total)
- Models include year effects and referral rate adjustments

All models use:
- **Binomial family** with enrollment as trials
- **District-level random effects** (LEAID)
- **Informative priors**: Normal(-8, 3) for intercept, Cauchy(1, 2) for random effect SDs

## Sample Restrictions

- **Minimum enrollment**: Districts must have ≥30 total students (≥2000 in development mode)
- **Data cleaning**: Arrests/referrals capped at enrollment when exceeding student counts
- **Demographic focus**: Analysis limited to White, Black, American Indian, and Hispanic students
- **Complete cases**: Only districts with data across specified years for longitudinal models

## Key Features

- **Reproducible pipeline** using the [`targets`](https://books.ropensci.org/targets/) framework
- **Parallel processing** with [`crew`](https://wlandau.github.io/crew/) for efficient model fitting
- **Bayesian inference** with full uncertainty quantification
- **Automated reporting** with [`Quarto`](https://quarto.org/) documents
- **Model comparison** across different specifications and time periods

## Requirements

### R Packages
```r
# Core pipeline
targets, tarchetypes, stantargets

# Data processing
dplyr, tidyr, tibble

# Modeling
brms, cmdstanr

# Reporting
quarto, knitr

# Utilities
qs2, educationdata
```

### System Requirements
- **Stan/CmdStanR**: For Bayesian model fitting
- **Multi-core system**: Recommended for parallel MCMC chains
- **Memory**: Sufficient RAM for large datasets

## Usage

### Setup
1. Install required R packages and CmdStan
2. Configure data paths in [`_targets.R`](_targets.R:39-63) to point to your CRDC data files
3. Adjust [`DEV_MODE`](_targets.R:33) and [`enroll_cap`](_targets.R:35-36) settings as needed

### Running the Pipeline
```r
# Load targets
library(targets)

# View pipeline
tar_visnetwork()

# Run entire pipeline
tar_make()

# Run specific targets
tar_make(combined_eda)
tar_make(national_3yr)
```

### Key Targets
- [`combined_model_data`](_targets.R:130-136): Merged data across all years
- [`three_year_data`](_targets.R:145-147): Modeling dataset with restrictions applied
- [`national_3yr`](_targets.R:249-262): National-level model fits
- [`demographic_3yr_models`](_targets.R:347-362): Subgroup-specific model fits
- [`combined_eda`](_targets.R:138-142): Exploratory data analysis report

## Outputs

- **Model fits**: Posterior samples and diagnostics for all fitted models
- **HTML reports**:
  - Combined EDA across all years
  - Annual descriptive statistics by year
- **Stan code**: Generated model files in [`models/`](models/) directory
- **Processed data**: Clean, analysis-ready datasets

## Model Interpretation

The models estimate:
- **Baseline arrest rates** by district (random effects)
- **Temporal trends** across the three time periods
- **Demographic disparities** in arrest rates
- **Impact of referral practices** on arrest likelihood
- **Uncertainty intervals** for all estimates

Results can inform policy discussions about:
- Disparities in school discipline practices
- Effectiveness of policy interventions over time
- District-level variation in arrest practices
- Relationship between referrals and arrests

## Development Notes

- Set [`DEV_MODE = FALSE`](_targets.R:33) for full analysis with all districts
- Models use threading for improved performance
- Pipeline includes extensive data validation steps
- See [`models.md`](models.md) for detailed model specifications

## Citation

When using this pipeline, please cite the Civil Rights Data Collection:
> U.S. Department of Education, Office for Civil Rights. (Year). Civil Rights Data Collection. Washington, DC.

## License

[Add appropriate license information]

## Contact

[Add contact information for questions or collaboration]
