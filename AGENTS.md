# crdc-arrests — conventions

Small-area Bayesian estimates of school-based arrest rates from the federal Civil Rights
Data Collection (CRDC), published as a Hugging Face dataset
(`civilytics/crdc-school-arrest-rates`) and an API (`crdc-api.civilytics.org`). The
pipeline is an R `targets` project.

**This repository is public.** `origin` fetches from Gitea and pushes to both Gitea and
GitHub (`jknowles/crdc-arrests`), so everything committed here is published, including
`pm/` and `.agent/memory/`. Never commit client data, PII, secrets, or raw CRDC/CCD
files.

## Layout

- `_targets.R`: the pipeline. `crdc_data` (one row per CRDC wave) is expanded with
  `tar_map`, and this is the only place a wave is listed.
- `R/`: pipeline functions.
  - `funs.R`: CRDC ingest, reserve codes, LEA collapse, model data.
  - `postprocess.R`: draws.
  - `summarize_draws.R` / `build_api_artifacts.R`: API database.
  - `export_parquet.R` / `stage_artifacts.R`: published artifacts.
- `api/`: the plumber API, its tests and Dockerfile. `deploy/` and
  `.gitea/workflows/deploy.yml` deploy it.
- `docs/`: **human-facing documentation only**, covering the API, the data dictionary,
  models and data stages.
- `pm/`: project management. This holds `compass.toml`, `JOURNAL.md`, `decisions/`, the
  generated `STATUS.md`, and plans in `pm/plans/`. Plans and other PM artifacts never go
  in `docs/`.
- `white_paper.qmd`, `supplement.qmd`: pinned to release `2025.1` through `crdc_path()`.
  Do not re-point them at a newer release without asking.

## Data and machines

- Untracked data (`tmp/`, `export/`, `_targets/objects`, `_targets/workspaces`) is
  linked from Nextcloud by `ncdata`; see `.ncdata`. Raw CRDC files live on the share at
  `/mnt/smb/civilytics/datasets/ED/CRDC/<year>-crdc-data/`, with each wave's User's
  Manual and Appendix Workbook. Pipeline inputs are copied into `tmp/data/`.
- **Two phases on two machines.**
  - Ingest and prep, everything upstream of the models, run on efron.
  - Models, draws and the published artifacts run on euler (32 cores, 256 GB).
  - Commit and push `_targets/meta/meta` at the handoff, and let Nextcloud finish
    syncing `_targets/objects`.
- euler's services are session-scoped. Run long jobs in `tmux` under `caffeinate`, and
  use `ssh euler 'zsh -lic "<cmd>"'`, because a bare ssh gets no R on PATH.

## Data rules

These are also roborev guidelines; see `pm/compass.toml`.

- **Reserve codes.**
  - Negative CRDC values go through `crdc_sub()` / `crdc_sub_1516()`.
  - Only `-9` (not applicable or skipped) is a structural zero.
  - `-3`, `-5`, `-6`, `-7`, `-11` and `-13` are missing, and must never be summed into
    zero arrests.
  - `-10` (suppressed under EO 14168) appears only in nonbinary `_X` cells, which are
    dropped.
- **Before calling a CRDC coding pattern new**, compare it with the previous wave's
  manual, Appendix Workbook (sheet B) and school form.
- **One recent year.** `RECENT_YEAR` drives both the recent-year sample and the year
  stamped on m1/m2 draws. Do not hard-code wave strings anywhere else.
- **CRDC-to-CCD joins go through the Appendix K crosswalk.** A direct
  COMBOKEY = `ncessch` join drops New York City's schools.
- **Aggregate draw-wise.** State totals and the NYC citywide total are summed per draw,
  then summarized. Never sum medians or interval bounds.
- **Releases are immutable.** A change that moves published numbers gets a new
  `data_release` and HF tag; an existing tag is never reused or moved.
- **Log dropped rows.** A filter or join that drops rows logs how many, and why.
- **Reports read published artifacts** through `crdc_path()`, never `tar_read()`,
  `tar_load()` or the local DuckDB. `R/check_read_contract.R` enforces this.

## Tests

- `scripts/run-tests.sh [filter]` runs both suites, `tests/testthat` and
  `api/tests/testthat`. CI (`.gitea/workflows/test.yml`) runs them with `tar_validate()`
  and the read-contract check.
- Write the test first. A bug fix gets a test that fails without it.
- `scripts/smoke-pipeline.sh` fits one model in dev mode. Never run it in CI.
- **Never start a full `tar_make()` without asking.** It runs for a day or more.

## Work tracking (compass)

- Work lives in Gitea issues on `jared/crdc-arrests`, labeled `ws/<stream>` plus
  `type/`, and `needs/` or `horizon/` where they apply.
- Workstreams are `data`, `models`, `api`, `release` and `writing`; `pm/compass.toml`
  lists their paths.
- Decisions go through `/compass:decide` into `pm/decisions/`. Session ends go through
  `/compass:wrap`.
- `pm/STATUS.md` is generated. Never hand-edit it.
- `pm/JOURNAL.md` is append-only.

## Commit cadence

- **Commit each coherent unit of work as it lands**, not in a batch at the end of a
  session. Batched commits are how the journal ends up reconstructed weeks later.
- Format: `type(ws): subject (#N)`.
  - `type` is one of feat, fix, refactor, docs, test, chore, perf or ci.
  - `ws` is the workstream.
  - `#N` is the issue.
  - Example: `fix(data): keep -5/-6 arrest cells missing, not zero (#9)`.
- Keep commits to one workstream where you can.
- End commit messages with the attribution line the harness supplies.
- Push only when asked. A push publishes to GitHub as well as Gitea.
