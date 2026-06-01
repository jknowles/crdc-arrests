# CRDC Data Download Guide

This guide explains how to download Civil Rights Data Collection (CRDC) files for this analysis pipeline.

## Quick Start

### Automated Download (Recommended)

```bash
# 1. Install required package
Rscript -e "install.packages('httr2')"

# 2. Run automated download
Rscript download_crdc_files.R --auto
```

This will automatically download and extract all three years of data (2021-22, 2017-18, 2015-16).

## Detailed Instructions

### Option 1: Fully Automated Download

The automated download function attempts to download files directly from the CRDC website.

**Requirements:**
- R package: `httr2`
- Internet connection
- ~3GB free disk space
- 30-60 minutes for all downloads (depending on connection speed)

**Usage in R:**

```r
# Load functions
source("R/funs.R")

# Download a single year
auto_download_crdc_data(
  year = "2021-22",
  dest_dir = "tmp/data",
  accept_terms = TRUE
)

# Download all years
for (year in c("2021-22", "2017-18", "2015-16")) {
  auto_download_crdc_data(
    year = year,
    dest_dir = "tmp/data",
    accept_terms = TRUE
  )
}
```

**Command Line:**

```bash
# Automatic mode
Rscript download_crdc_files.R --auto

# Manual mode (if you've already downloaded files)
Rscript download_crdc_files.R --manual
```

### Option 2: Manual Download

If automated download fails (due to changed URLs, network issues, etc.):

1. **Visit the CRDC website:**
   - Go to: https://civilrightsdata.ed.gov/data

2. **Download each year:**
   - Select year: 2021-22
   - Click "Download CSV" for public use files
   - Save to `~/Downloads/2021-22-crdc-data.zip`
   - Repeat for 2017-18 and 2015-16

3. **Extract files:**
   ```r
   source("R/funs.R")

   download_crdc_data(
     year = "2021-22",
     zip_file = "~/Downloads/2021-22-crdc-data.zip",
     dest_dir = "tmp/data"
   )
   ```

## File Information

### File Sizes
- **2021-22**: ~500 MB (compressed)
- **2017-18**: ~800 MB (compressed)
- **2015-16**: ~1.5 GB (compressed)

### Expected Directory Structure

After extraction, you should have:

```
tmp/data/
├── 2021-22-crdc-data/
│   └── SCH/
│       ├── Enrollment.csv
│       └── Referrals and Arrests.csv
├── 2017-18-crdc-data-corrected-05242021/
│   └── 2017-18 Public-Use Files/
│       └── Data/SCH/CRDC/CSV/
│           ├── Enrollment.csv
│           └── Referrals and Arrests.csv
└── 2015-16-crdc-data/
    └── Data Files and Layouts/
        └── CRDC 2015-16 School Data.csv
```

> The automated `download_crdc_data()` extracts to exactly these paths, which match `_targets.R`. If a future CRDC re-release changes the folder names, update `crdc_expected_paths()` in `R/funs.R` and the `crdc_data` tibble in `_targets.R` together.

## Function Reference

### `auto_download_crdc_data()`

Automatically downloads and extracts CRDC data files.

**Parameters:**
- `year`: Character string - "2021-22", "2017-18", or "2015-16"
- `dest_dir`: Destination directory (default: "tmp/data")
- `accept_terms`: Must be TRUE to proceed (default: FALSE)
- `overwrite`: Overwrite existing files (default: FALSE)
- `timeout`: Download timeout in seconds (default: 3600)

**Returns:**
List with `enrollment_path` and `le_path`

**Example:**
```r
result <- auto_download_crdc_data(
  year = "2021-22",
  accept_terms = TRUE
)
print(result$enrollment_path)
```

### `download_crdc_data()`

Extracts already-downloaded CRDC zip files.

**Parameters:**
- `year`: Character string - "2021-22", "2017-18", or "2015-16"
- `zip_file`: Path to downloaded zip file
- `dest_dir`: Destination directory (default: "tmp/data")
- `overwrite`: Overwrite existing files (default: FALSE)

**Returns:**
List with `enrollment_path` and `le_path`

**Example:**
```r
result <- download_crdc_data(
  year = "2021-22",
  zip_file = "~/Downloads/2021-22-crdc-data.zip"
)
```

## Troubleshooting

### Automated Download Fails

**Problem:** `auto_download_crdc_data()` returns an error

**Solutions:**
1. Check internet connection
2. Verify `httr2` package is installed: `install.packages("httr2")`
3. Try increasing timeout: `timeout = 7200` (2 hours)
4. Use manual download instead

### URL Not Found (404 Error)

**Problem:** Download URLs have changed

**Solution:** The CRDC website may have updated their URL structure. Use manual download:
1. Visit https://civilrightsdata.ed.gov/data
2. Download files manually
3. Use `download_crdc_data()` to extract

### File Corruption

**Problem:** Downloaded file is corrupt or incomplete

**Solutions:**
1. Delete the partial download: `file.remove("tmp/data/[filename].zip")`
2. Try downloading again with `overwrite = TRUE`
3. Use manual download from website

### Insufficient Disk Space

**Problem:** Not enough space for downloads

**Solution:** You need ~3GB free space. Clear space or use a different `dest_dir`:
```r
auto_download_crdc_data(
  year = "2021-22",
  dest_dir = "/path/to/larger/drive/crdc_data",
  accept_terms = TRUE
)
```

### Network Timeout

**Problem:** Download times out on slow connections

**Solution:** Increase timeout parameter:
```r
auto_download_crdc_data(
  year = "2021-22",
  timeout = 7200,  # 2 hours
  accept_terms = TRUE
)
```

## Terms of Use

By downloading and using CRDC data, you agree to:
- Proper attribution of the data source
- Compliance with all applicable privacy and data protection laws
- The CRDC terms of use available at: https://civilrightsdata.ed.gov/data

## Support

For issues with:
- **This pipeline**: Open an issue on GitHub
- **CRDC data itself**: Contact the Office for Civil Rights at https://civilrightsdata.ed.gov/

## Citation

When using this data, cite:

> U.S. Department of Education, Office for Civil Rights. (Year). *Civil Rights Data Collection*. Washington, DC.

Replace (Year) with the appropriate data year (2022, 2018, or 2016).
