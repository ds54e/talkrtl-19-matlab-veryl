#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERYL_BIN="${VERYL_BIN:-veryl}"
RGGEN_BIN="${RGGEN_BIN:-rggen}"

# `veryl build --out-dir` preserves the target path from Veryl.toml.
SNAPSHOTS=(
  "rtl/generated/rggen/ldo_csr.sv|rggen/ldo_csr.sv"
  "rtl/generated/veryl/pgood_supervisor.sv|veryl/results/generated/veryl/pgood_supervisor.sv"
)
# Re-enter a login shell once so user-local veryl/rggen installs are visible.
if [[ "${GENERATED_RTL_CHECK_LOGIN:-0}" != "1" ]] \
   && { ! command -v "$VERYL_BIN" >/dev/null 2>&1 || ! command -v "$RGGEN_BIN" >/dev/null 2>&1; }; then
  exec env GENERATED_RTL_CHECK_LOGIN=1 bash -lc 'exec "$0" "$@"' "$0" "$@"
fi

FAIL=0
note() { printf '%s\n' "$*"; }
fail() { printf 'GENERATED_RTL_CHECK_FAIL: %s\n' "$*" >&2; FAIL=1; }

for tool in "$VERYL_BIN" "$RGGEN_BIN" cmp; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "GENERATED_RTL_CHECK_BLOCKED: '$tool' not on PATH" >&2
    echo "(veryl / rggen are user-local installs; run this from a login shell)" >&2
    exit 2
  }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-generated-rtl.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

cd "$ROOT" || exit 2

note "=== toolchain (measured) ==="
note "veryl: $("$VERYL_BIN" --version 2>&1 | head -1)"
note "rggen: $("$RGGEN_BIN" --version 2>&1 | head -1) / $(ruby --version 2>&1 | head -1)"

note
note "=== Veryl: fmt --check, check, build ==="
if ! "$VERYL_BIN" fmt --check; then fail "veryl fmt --check"; fi
if ! "$VERYL_BIN" check; then fail "veryl check"; fi
if ! "$VERYL_BIN" build --out-dir "$WORK/veryl"; then fail "veryl build"; fi

note
note "=== RgGen: rtl/rggen/rggen.yml + rtl/rggen/ldo_csr.yml ==="
if ! CSR_OUT="$WORK/rggen" RGGEN_BIN="$RGGEN_BIN" bash tools/gen-csr.sh; then fail "rggen CSR generation"; fi

note
note "=== snapshot comparison ==="
for entry in "${SNAPSHOTS[@]}"; do
  snap="${entry%%|*}"
  fresh="$WORK/${entry##*|}"
  if [[ ! -f "$snap" ]]; then
    fail "missing committed snapshot: $snap"
    continue
  fi
  if [[ ! -f "$fresh" ]]; then
    fail "fresh output missing: $fresh"
    continue
  fi
  if cmp -s "$snap" "$fresh"; then
    note "OK       $snap"
  else
    fail "$snap differs from fresh output"
    diff -u "$snap" "$fresh" | head -n 60 >&2 || true
  fi
done

note
if [[ "$FAIL" -eq 0 ]]; then
  echo "GENERATED_RTL_CHECK_PASS"
  exit 0
fi
echo "GENERATED_RTL_CHECK_FAILED"
exit 1
