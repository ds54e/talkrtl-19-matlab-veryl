#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
trap 'echo GENERATED_RTL_CHECK_FAIL >&2' ERR
cd "$ROOT"

veryl fmt --check
veryl check
veryl build --out-dir "$WORK/veryl"
CSR_OUT="$WORK/rggen" bash tools/gen-csr.sh

# Veryl preserves the target path from Veryl.toml under --out-dir.
diff -u rtl/generated/veryl/pgood_supervisor.sv \
  "$WORK/veryl/results/generated/veryl/pgood_supervisor.sv"
diff -u rtl/generated/rggen/ldo_csr.sv "$WORK/rggen/ldo_csr.sv"
echo GENERATED_RTL_CHECK_PASS
