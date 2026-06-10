# Reproducing the CRDC Arrests Pipeline

This document lets a newcomer reproduce the pipeline from source and sets honest
expectations about the compute involved.

## Toolchain

| Component | Version | Notes |
|-----------|---------|-------|
| R | 4.6.0 | pinned via `renv.lock` |
| R packages | see `renv.lock` | restored with `renv::restore()` |
| CmdStan | 2.37.0 | installed separately (renv cannot capture it) |
| Quarto CLI | ≥ 1.4 | installed separately; required to render any `.qmd` |
| Hardware (full run) | ≥ 24 cores, ≥ 128 GB RAM | see sizing below |

## System prerequisites

Several R packages compile C/C++/Fortran code against system libraries. Install
these before running `setup.R`. The list is derived from the compiled packages in
`renv.lock` (gdtools, sf, s2, igraph, mvtnorm, openssl, magick, …).

### macOS (Homebrew)

```bash
brew install pkg-config cairo gdal openssl gettext gcc
```

> **gfortran note:** Homebrew installs `gfortran` to `/opt/homebrew/bin/gfortran`,
> but R's build system expects it at `/opt/gfortran/bin/gfortran`. Add the
> following to `~/.R/Makevars` (create the file if it does not exist):
>
> ```makefile
> FC = /opt/homebrew/bin/gfortran -arch arm64
> F77 = /opt/homebrew/bin/gfortran -arch arm64
> FLIBS = -L/opt/homebrew/lib/gcc/current -lgfortran -lquadmath -lm
> LDFLAGS = -L/opt/homebrew/opt/gettext/lib
> ```

> **PKG_CONFIG_PATH note:** Homebrew installs keg-only packages (openssl, cairo)
> outside the default pkg-config search path. Add the following to `~/.Renviron`:
>
> ```
> PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig:/opt/homebrew/share/pkgconfig:/opt/homebrew/opt/openssl@3/lib/pkgconfig:/opt/homebrew/opt/cairo/lib/pkgconfig:/opt/homebrew/opt/gdal/lib/pkgconfig:/opt/homebrew/opt/gettext/lib/pkgconfig
> ```

### Linux (Ubuntu / Debian)

```bash
sudo apt install \
  pkg-config \
  libcairo2-dev \
  libgdal-dev libgeos-dev libproj-dev \
  libssl-dev \
  libfontconfig1-dev \
  libmagick++-dev \
  gfortran
```

> `libmagick++-dev` is optional — without it, `cv_apply_branding()` degrades to
> theme-only (no logo stamping on figures). All other packages are required.

### CmdStan compiler flags

Keep `$(cmdstanr::cmdstan_path())/make/local` **minimal**. The only non-default
setting the models need is threading:

```makefile
# Threading for reduce_sum / map_rect (brms fits with threads = threading(NTHREADS))
STAN_THREADS=true
CXXFLAGS += -Wno-deprecated-declarations
```

Then run `cmdstanr::rebuild_cmdstan()` once to recompile the CmdStan utilities.

> #### ⚠️ Do NOT add aggressive optimisation flags
>
> Hand-tuned "speed" flags caused **SIGSEGV crashes inside the NUTS sampler**
> (`generate_transitions`) on full-data runs, surfacing as
> `Fitting failed. Unable to retrieve the metadata.` All three of the following
> were tried on Apple Silicon and **each crashes** — remove them and rebuild:
>
> | Flag | Why it breaks |
> |------|---------------|
> | `-ffast-math` / `-Ofast` | Breaks the IEEE NaN/Inf semantics the sampler needs to reject divergent proposals. `-fno-finite-math-only` does **not** make it safe (it also enables unsafe reassociation, reciprocal-math, no-signed-zeros). |
> | `-march=native -mtune=native` | M-series codegen miscompiled the sampler's virtual dispatch → bad-pointer segfault. |
> | `STAN_CPP_OPTIMS=TRUE` | Enables `-flto=full -fstrict-vtable-pointers -fwhole-program-vtables`, which can corrupt vtables under LTO → same crash signature. |
>
> The stock CmdStan build is already `-O3` and is the configuration the Stan team
> tests. Prefer it. **A reduced smoke run does NOT catch this** — the crash only
> appears once full-data sampling reaches an extreme gradient during warmup
> (~6 min in), so always validate a real full-data fit, not just
> `CRDC_DEV_MODE=true`. If you want to chase M-series performance later, re-add
> **one** flag at a time and confirm a clean full fit after each.

### Quarto CLI

Every report in this project is a Quarto document (`.qmd`), and the pipeline's
render targets (`white_paper`, `supplement`, `social_media_posts`,
`model_descriptives_*`, `annual_report_*`) shell out to the **Quarto
command-line tool**. The `quarto` R package is only a thin wrapper — it does not
bundle the CLI — so without the standalone binary on `PATH` those targets fail
mid-pipeline with `Quarto command-line tools path not found`.

> **It is a hard prerequisite for `tar_make()`**, not just for standalone
> renders: the render targets are part of the default pipeline, so a missing
> Quarto CLI aborts the run after the (multi-day) modeling stage completes.
> `setup.R` checks for it and warns early; install it before running anything.

Install the standalone CLI (do **not** rely on the copy bundled inside an IDE
such as Positron/RStudio — that is not on the system `PATH` and other tools
won't find it):

```bash
# macOS
brew install quarto

# Linux (Debian/Ubuntu) — download the latest .deb from quarto.org
#   https://quarto.org/docs/get-started/
sudo dpkg -i quarto-*-linux-amd64.deb
```

Verify it resolves from both the shell and R:

```bash
quarto --version
Rscript -e 'quarto::quarto_path()'   # should print the binary path, not NULL
```

## One-time setup

```r
# from a fresh clone, in R at the project root:
source("setup.R")   # renv::restore() + install_cmdstan(2.37.0) + sanity checks
```

`setup.R` restores the locked package library, installs/points to CmdStan 2.37.0
(with the `-march=native` BLAS/LAPACK flags), and runs sanity checks (tarchetypes
loads, CmdStan resolves, DuckDB round-trips, and the Quarto CLI is found — a
missing Quarto warns here rather than failing the render targets mid-run).

## Obtaining the source data

See [`DOWNLOAD_GUIDE.md`](DOWNLOAD_GUIDE.md). `Rscript download_crdc_files.R --auto`
extracts the three CRDC waves to exactly the paths `_targets.R` expects (the
contract is asserted by `tests/testthat/test-download-paths.R`).

## Running

```r
library(targets)
tar_make()          # the FULL run — see the warning below
```

### ⚠️ The full run takes DAYS

Fitting every unified + stratified Bayesian model is enormous. On a **24-core /
128 GB** machine the full `tar_make()` takes on the order of **several days** of
continuous compute. (A hypothetical Model 6 was abandoned after 7 days.) Plan
accordingly, and prefer to validate your setup first:

```bash
scripts/smoke-pipeline.sh   # DEV_MODE: builds unified_m1_mod + upstream in minutes
```

### Sizing the run to your machine (MCMC parallelism × RAM)

Peak RAM ≈ (chains running in parallel) × (per-chain data + sampler footprint).
Tune via environment variables (no need to edit `_targets.R`):

| Env var | Default | Effect |
|---------|---------|--------|
| `CRDC_CORES` | physical cores | total cores the pipeline may use |
| `CRDC_NTHREADS` | 4 | threads **per chain** (raise to finish each chain faster with fewer running at once) |
| `CRDC_NCHAINS` | 4 | chains per model |
| `CRDC_DEV_MODE` | FALSE | `true` → reduced iters + high enrollment cap (smoke) |

Rough guidance:

| Cores | RAM | Suggested settings |
|-------|-----|--------------------|
| ≥ 24 | ≥ 128 GB | defaults (`NCHAINS=4`, `NTHREADS=4`) — full speed |
| 12-16 | 64 GB | `CRDC_NTHREADS=4`, expect fewer concurrent chains; watch RSS |
| 8 | 32 GB | `CRDC_NTHREADS=8 CRDC_NCHAINS=4` (1 chain at a time) or use `CRDC_DEV_MODE=true` |
| memory pressure | — | lower `CRDC_CORES`, raise `CRDC_NTHREADS`, or raise `enroll_cap` |

### Per-stage resource costs (post-modeling artifact build)

| Stage | Cost |
|-------|------|
| Draws DB (`posterior_db`) | ~69 GB DuckDB, ~1.14 B rows |
| Summary API DB (`api_db`) | ~15 min, bounded memory + spill |
| Parquet export (`draws_parquet`) | ~3.6 min, chunked per `model_id` |

The artifact-build targets bound DuckDB `memory_limit` (~70% of RAM), cap threads,
and spill to `tmp/duckdb_spill`, so they complete on a 63 GB box. They retain the
DuckDB driver for the connection lifetime (an anonymous driver can be garbage-
collected mid-job → "Invalid connection").

## Determinism

The global seed is **11213** (`tar_option_set(seed=)`) and every model sets
`seed = 11213`. Results are **statistically reproducible but not bit-for-bit**:
the models sample with threaded Stan (`threads = threading(NTHREADS)`), and
floating-point reduction order across threads varies, so exact draw values differ
run to run while posterior summaries are equivalent.

## Provenance & resuming

`targets` caches every step in the `_targets/` store, so an interrupted run
resumes where it stopped: re-run `tar_make()` and only stale/incomplete targets
rebuild. `tar_progress()` / `tar_meta()` report status; logs are under
`_targets/meta/`. The published data release tag is
`civilytics-crdc-arrests-2025.1` (written into the API DB `meta` table).

---

## Artifact reproduction (Subsystem 3)

The published documents — the white paper, results, applied examples, social
posts, EDA, and descriptive reports — can be rebuilt **without** the ~7-day model
run, the 18 GB `_targets/` store, or the 69 GB draws DB. They read a small set of
**published artifacts** instead.

### Where the docs read from — `crdc_path()` + `CRDC_ARTIFACTS`

Every in-scope `.qmd` resolves data through `crdc_path()` (`R/crdc_path.R`), which
returns a URI for a logical artifact path. The base is the `CRDC_ARTIFACTS` env
var:

- **Owner / local:** `export CRDC_ARTIFACTS=export` → reads `export/stages/…` and
  `export/parquet/…` directly (no network, no cache).
- **New user (default):** `hf://datasets/civilytics/crdc-school-arrest-rates@civilytics-crdc-arrests-2025.1`
  → small artifacts read directly; **big** ones (the draws parquet tree, the
  `stages/models/unified_m*.qs2` fits) cache once into `CRDC_CACHE`
  (default `tools::R_user_dir("crdc-arrests","cache")`) so later renders don't
  re-download.

Reads are native (DuckDB `read_parquet`, `qs2::qs_read`); `crdc_path()` only
resolves a path and lazily caches — it does not wrap the read. The docs are
therefore **standalone-renderable**: `quarto render supplement.qmd` works on a clean
clone with no targets store. They are also wrapped as `cue = "never"` render
targets for pipeline integration.

### One-command render

```bash
scripts/cache-artifacts.sh      # (new user) mirror the big artifacts locally, once
scripts/render-artifacts.sh     # render all in-scope docs (or pass specific .qmd)
```

### Per-wave reports render in isolation (parallel-safety)

`model_descriptives_*` and `annual_report_*` are `tar_map` targets that render
the **same** template (`model_descriptives_template.qmd` /
`annual_descriptives_template.qmd`) once per CRDC wave. `targets` dispatches
those branches **concurrently**, and a shared source file is not safe to render
in parallel:

- **Figure outputs** — each template namespaces its figures by wave via
  `knitr::opts_chunk$set(fig.path = ".../<doc>-<suffix>-")` in the setup chunk.
  Without this, every wave wrote the same `export/figures/*.png` and concurrent
  writes produced corrupt PNGs (`IDAT: CRC error`).
- **Quarto intermediates** — Quarto names its intermediates (`<input>.knit.md`,
  `<input>_files/`) after the input file. `render_year_doc()` (`R/paper_figures.R`)
  therefore renders each wave from a per-wave **copy** of the template (kept in
  the project root so relative `source()`/`export/` paths still resolve) and
  cleans the copy up afterward, so the branches never collide.

> **Lesson:** when a `tar_map` (or any parallel loop) renders one shared `.qmd`,
> isolate **both** the figure outputs and Quarto's source-named intermediates per
> branch. Don't serialize the renders to work around it — isolation keeps the
> parallelism. Verify by rendering ≥2 waves concurrently, not one in isolation.

### Cleaning up after a failed run

A crashed `tar_make()` can leave orphaned Stan sampler chains
(`model_<hash>` processes pinning CPU) and half-written figures. Run:

```bash
scripts/kill-stan-chains.sh             # kill orphaned chains + delete corrupt PNGs
scripts/kill-stan-chains.sh --dry-run   # report only, change nothing
```

### Branding on figures

`cv_apply_branding()` (`R/paper_figures.R`) sets the Civilytics ggplot theme
globally and, when **`magick`** is installed (system `libmagick++-dev`), stamps
the Civilytics logo onto every output figure via a knitr `fig.process` hook.
Without `magick` it degrades to theme-only.

### Determinism

Figures inherit the pipeline's global seed (`11213`) and are **statistically
reproducible, not bit-for-bit** (threaded Stan): estimates/intervals match to
floating-point, figure pixels may differ trivially. Figure dimensions/DPI are
pinned in each doc's YAML.

### Download sizes

| What | Size |
|---|---|
| Core (all docs; diagnostics from the table) | **~1.7 GB** (`stages/` <300 MB + `parquet/` 1.4 GB) |
| + live unified-model diagnostics | **~4.6 GB** (adds `stages/models/` ~2.9 GB) |

See [`docs/data-stages.md`](docs/data-stages.md) for the per-artifact provenance map.
