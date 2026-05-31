FROM rocker/r-ver:4.6.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev libssl-dev libz-dev curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN install2.r --error --skipinstalled \
    plumber DBI duckdb jsonlite

WORKDIR /app
COPY R/ /app/R/
COPY plumber.R /app/plumber.R
COPY llms.txt /app/llms.txt
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Data is fetched at build/first-run from the pinned data_release artifact,
# never committed. DATA_URL is provided at build/run.
ARG DATA_URL=""
ENV API_DB_PATH=/app/data/crdc_api.duckdb
ENV DATA_URL=${DATA_URL}

EXPOSE 8000
ENTRYPOINT ["/app/entrypoint.sh"]
