#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RGGEN_BIN="${RGGEN_BIN:-rggen}"
OUT="${CSR_OUT:-$ROOT/results/generated/csr}"

command -v "$RGGEN_BIN" >/dev/null 2>&1 || {
  echo "CSR_BLOCKED: '$RGGEN_BIN' not on PATH (set RGGEN_BIN to override)" >&2
  exit 2
}

rm -rf "$OUT"
mkdir -p "$OUT"

"$RGGEN_BIN" --plugin rggen-verilog -c "$ROOT/rtl/rggen/rggen.yml" -o "$OUT" --enable verilog_rtl "$ROOT/rtl/rggen/ldo_csr.yml"

GEN="$OUT/ldo_csr.v"
[[ -f "$GEN" ]] || { echo "CSR_FAIL: $GEN was not generated" >&2; exit 1; }

echo "CSR_GENERATED $GEN"
