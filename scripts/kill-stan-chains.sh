#!/usr/bin/env bash
# Clean up after a failed pipeline run:
#   1. Kill orphaned Stan sampler chains (model_<hex> processes in temp dirs)
#   2. Remove partially-written PNG figures that have CRC errors
#
# Usage:
#   scripts/kill-stan-chains.sh            # kill chains + remove corrupt PNGs
#   scripts/kill-stan-chains.sh --dry-run  # print what would be done, no changes

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

CD="$(cd "$(dirname "$0")/.." && pwd)"

# --- 1. Stan sampler chains ------------------------------------------------
PIDS=$(pgrep -f '\./model_[0-9a-f]{32}' 2>/dev/null || true)

if [[ -z "$PIDS" ]]; then
  echo "Stan chains: none running."
else
  COUNT=$(echo "$PIDS" | wc -w | tr -d ' ')
  echo "Stan chains: found $COUNT running (PIDs: $(echo $PIDS | tr '\n' ' '))"
  if [[ "$DRY_RUN" == false ]]; then
    # shellcheck disable=SC2086
    kill $PIDS
    echo "Stan chains: killed $COUNT."
  else
    echo "Stan chains: (dry-run — not killing)"
  fi
fi

# --- 2. Corrupt PNG figures ------------------------------------------------
FIGURES_DIR="$CD/export/figures"

if [[ ! -d "$FIGURES_DIR" ]]; then
  echo "Figures dir not found ($FIGURES_DIR) — skipping PNG check."
else
  CORRUPT=()
  while IFS= read -r -d '' png; do
    if ! python3 -c "
import struct, zlib, sys
with open(sys.argv[1], 'rb') as f:
    sig = f.read(8)
    if sig != b'\x89PNG\r\n\x1a\n':
        sys.exit(1)
    while True:
        hdr = f.read(8)
        if len(hdr) < 8:
            break
        length = struct.unpack('>I', hdr[:4])[0]
        chunk_type = hdr[4:8]
        data = f.read(length)
        crc_stored = struct.unpack('>I', f.read(4))[0]
        crc_calc = zlib.crc32(chunk_type + data) & 0xffffffff
        if crc_stored != crc_calc:
            sys.exit(1)
" "$png" 2>/dev/null; then
      CORRUPT+=("$png")
    fi
  done < <(find "$FIGURES_DIR" -name "*.png" -print0)

  if [[ ${#CORRUPT[@]} -eq 0 ]]; then
    echo "Figures: no corrupt PNGs found."
  else
    echo "Figures: found ${#CORRUPT[@]} corrupt PNG(s):"
    for f in "${CORRUPT[@]}"; do
      echo "  $f"
    done
    if [[ "$DRY_RUN" == false ]]; then
      for f in "${CORRUPT[@]}"; do
        rm "$f"
      done
      echo "Figures: removed ${#CORRUPT[@]} corrupt PNG(s)."
    else
      echo "Figures: (dry-run — not removing)"
    fi
  fi
fi
