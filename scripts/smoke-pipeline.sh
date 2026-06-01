#!/usr/bin/env bash
# DEV_MODE smoke: prove the toolchain + dependency graph end-to-end on a small
# build (reduced iterations + high enrollment cap) WITHOUT the multi-day run.
# Builds nat_m1_mod and its upstream data-prep targets. Requires CmdStan (run
# setup.R first). NEVER run this in CI — it fits a model.
set -euo pipefail
cd "$(dirname "$0")/.."

export CRDC_DEV_MODE=true
echo "== DEV_MODE smoke: building nat_m1_mod (+ upstream) with reduced iters/enroll cap =="
echo "   (expect a few minutes once CmdStan is set up; this proves the pipeline runs)"
Rscript -e 'targets::tar_make(names = "nat_m1_mod")'
echo "== Smoke build complete. Inspect with: Rscript -e 'targets::tar_read(nat_m1_mod)' =="
