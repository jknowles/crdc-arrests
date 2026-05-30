#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$(dirname "$API_DB_PATH")"
if [ ! -f "$API_DB_PATH" ]; then
  if [ -z "${DATA_URL:-}" ]; then
    echo "ERROR: API_DB missing and DATA_URL unset." >&2; exit 1
  fi
  echo "Fetching summary DB ..."
  curl -fSL "$DATA_URL" -o "$API_DB_PATH"
fi

exec Rscript -e "plumber::pr_run(plumber::pr('plumber.R'), host='0.0.0.0', port=as.integer(Sys.getenv('PORT','8000')))"
