#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XEZIM_BIN="${XEZIM_BIN:-xezim}"
OUT="$ROOT/results/generated/xezim"

RNM=("$ROOT/rtl/rnm/pg_cmp_rnm.sv" "$ROOT/rtl/rnm/ldo_rnm.sv")
DUT="$ROOT/rtl/generated/veryl/pgood_supervisor.sv"
RGLIB_DIR="$ROOT/rtl/rggen-sv-rtl"
# rggen_rtl_pkg.sv must come first.
RGLIB=()
for f in rtl_pkg or_reducer mux bit_field_if bit_field register_if address_decoder \
         register_common default_register bus_if adapter_common apb_if apb_adapter; do
  RGLIB+=("$RGLIB_DIR/rggen_$f.sv")
done
CSR="$ROOT/rtl/generated/rggen/ldo_csr.sv"
rm -rf "$OUT"
mkdir -p "$OUT/logs"
printf 'SIM: %s\n' "$("$XEZIM_BIN" -V 2>/dev/null | head -1)"
printf 'SIM: results in %s (gitignored)\n' "${OUT#"$ROOT"/}"

# Testbenches write CSVs relative to cwd.
xrun() {
  local tag="$1" top="$2" marker="$3"
  shift 3
  local log="$OUT/logs/$tag.run.log"

  ( cd "$OUT" && "$XEZIM_BIN" --simulate --wave --no-cache --error-exit \
      --module-timescale 1ns/1ps --max-time 1ms -s "$top" "$@" ) > "$log" 2>&1
  local rc=$?
  [[ $rc -eq 0 ]] || {
    printf 'SIM_FAIL: %s exited %s, see %s\n' "$tag" "$rc" "${log#"$ROOT"/}" >&2
    tail -n 20 "$log" >&2
    return 1
  }
  grep -q "$marker" "$log" || {
    printf 'SIM_FAIL: %s never printed %s, see %s\n' "$tag" "$marker" "${log#"$ROOT"/}" >&2
    tail -n 20 "$log" >&2
    return 1
  }
  printf '  PASS %s\n' "$tag"
  grep -E '^APB_SYSTEM: ' "$log" | sed 's/^/    /' || true
}

printf '\n=== apb: RgGen CSR + SV-RNM + Veryl supervisor, analog and digital CSVs ===\n'
xrun apb apb_system_tb APB_SYSTEM_PASS "${RGLIB[@]}" "${RNM[@]}" "$DUT" "$CSR" \
  "$ROOT/sim/apb_master_bfm.sv" "$ROOT/sim/apb_system_tb.sv" || exit 1

# xezim writes package parameters as `pkg::NAME`, which is not a VCD
# identifier and makes GTKWave stop; rename them to `pkg__NAME`.
sed -i '/^\$var/s/::/__/g' "$OUT/wave.vcd"
printf '\nWaveform: %s\n' "${OUT#"$ROOT"/}/wave.vcd"
printf '\nSIM_PASS\n'
