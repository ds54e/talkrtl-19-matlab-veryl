#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XEZIM_BIN="${XEZIM_BIN:-xezim}"
OUT="$ROOT/results/generated/xezim"

blocked() { printf 'SIM_BLOCKED: %s\n' "$*" >&2; exit 2; }
fail()    { printf 'SIM_FAIL: %s\n' "$*" >&2; exit 1; }

if [[ "$XEZIM_BIN" == */* ]]; then
  [[ -x "$XEZIM_BIN" ]] || blocked "XEZIM_BIN is not executable: $XEZIM_BIN"
elif ! command -v "$XEZIM_BIN" >/dev/null 2>&1; then
  blocked "'$XEZIM_BIN' is not on PATH (set XEZIM_BIN to a path to override)"
fi

RNM=("$ROOT/rtl/rnm/pg_cmp_rnm.sv" "$ROOT/rtl/rnm/ldo_rnm.sv")
DUT="$ROOT/rtl/generated/veryl/pgood_supervisor.sv"
RGLIB_DIR="$ROOT/rtl/rggen-verilog-rtl"
RGLIB=("$RGLIB_DIR/rggen_or_reducer.v"
       "$RGLIB_DIR/rggen_mux.v"
       "$RGLIB_DIR/rggen_bit_field.v"
       "$RGLIB_DIR/rggen_address_decoder.v"
       "$RGLIB_DIR/rggen_register_common.v"
       "$RGLIB_DIR/rggen_default_register.v"
       "$RGLIB_DIR/rggen_adapter_common.v"
       "$RGLIB_DIR/rggen_apb_adapter.v"
       "$ROOT/rtl/rggen-sv-rtl/rggen_apb_if.sv")
CSR="$ROOT/rtl/generated/rggen/ldo_csr.v"
for f in "${RNM[@]}" "$DUT" "$CSR" "$ROOT/sim/rnm_core_tb.sv" \
         "$ROOT/sim/system_nominal_tb.sv" "$ROOT/sim/apb_master_bfm.sv" \
         "$ROOT/sim/apb_system_tb.sv" "${RGLIB[@]}"; do
  [[ -f "$f" ]] || blocked "missing source: ${f#"$ROOT"/}"
done

rm -rf "$OUT"
mkdir -p "$OUT/logs"
printf 'SIM: %s\n' "$("$XEZIM_BIN" -V 2>/dev/null | head -1)"
printf 'SIM: results in %s (gitignored)\n' "${OUT#"$ROOT"/}"

# Testbenches write CSVs relative to cwd.
xrun() {
  local tag="$1" top="$2" marker="$3"
  shift 3
  local log="$OUT/logs/$tag.run.log"

  ( cd "$OUT" && "$XEZIM_BIN" --simulate --no-cache --error-exit \
      --module-timescale 1ns/1ps --max-time 1ms -I "$RGLIB_DIR" -s "$top" "$@" ) > "$log" 2>&1
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
  grep -E '^(RNM_CORE|SYSTEM_NOMINAL|APB_SYSTEM): ' "$log" | sed 's/^/    /'
}

printf '\n=== analog: SV-RNM LDO, nominal 50 us scenario ===\n'
xrun rnm rnm_core_tb RNM_CORE_PASS "${RNM[@]}" "$ROOT/sim/rnm_core_tb.sv" \
  +CSV=rnm_nominal.csv +FULL_CSV=rnm_nominal_full.csv \
  +EN_RISE_NS=2000 +LOAD_RISE_NS=25000 +LOAD_FALL_NS=35000 +EN_FALL_NS=0 \
  +END_NS=50000 +DT_PS=10000 || exit 1

printf '\n=== system: SV-RNM + Veryl supervisor, 501 ticks ===\n'
xrun system system_nominal_tb SYSTEM_NOMINAL_PASS "${RNM[@]}" "$DUT" "$ROOT/sim/system_nominal_tb.sv" \
  +CSV=system_nominal.csv \
  +EN_RISE_NS=2000 +LOAD_RISE_NS=25000 +LOAD_FALL_NS=35000 +EN_FALL_NS=0 \
  +END_NS=50000 +DT_PS=10000 || exit 1

printf '\n=== apb: RgGen CSR + SV-RNM + Veryl supervisor, integrated ===\n'
xrun apb apb_system_tb APB_SYSTEM_PASS "${RGLIB[@]}" "${RNM[@]}" "$DUT" "$CSR" \
  "$ROOT/sim/apb_master_bfm.sv" "$ROOT/sim/apb_system_tb.sv" \
  +EN_RISE_NS=2000 +LOAD_RISE_NS=25000 +LOAD_FALL_NS=35000 \
  +END_NS=50000 +DT_PS=10000 || exit 1

printf '\nSIM_PASS\n'
