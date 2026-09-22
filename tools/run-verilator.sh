#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERILATOR_BIN="${VERILATOR_BIN:-verilator}"
OUT="$ROOT/results/generated/verilator"

blocked() { printf 'SIM_BLOCKED: %s\n' "$*" >&2; exit 2; }
fail()    { printf 'SIM_FAIL: %s\n' "$*" >&2; exit 1; }

if [[ "$VERILATOR_BIN" == */* ]]; then
  [[ -x "$VERILATOR_BIN" ]] || blocked "VERILATOR_BIN is not executable: $VERILATOR_BIN"
elif ! command -v "$VERILATOR_BIN" >/dev/null 2>&1; then
  blocked "'$VERILATOR_BIN' is not on PATH (set VERILATOR_BIN to a path to override)"
fi
for tool in g++ make; do
  command -v "$tool" >/dev/null 2>&1 || blocked "'$tool' is not on PATH"
done

RNM=("$ROOT/rtl/rnm/pg_cmp_rnm.sv" "$ROOT/rtl/rnm/ldo_rnm.sv")
DUT="$ROOT/rtl/generated/veryl/pgood_supervisor.sv"
# rggen_rtl_pkg.sv must precede the other RgGen RTL files.
RGLIB=("$ROOT/rtl/rggen-sv-rtl/rggen_rtl_pkg.sv"
       "$ROOT/rtl/rggen-sv-rtl/rggen_or_reducer.sv"
       "$ROOT/rtl/rggen-sv-rtl/rggen_mux.sv"
       "$ROOT/rtl/rggen-sv-rtl/rggen_bit_field_if.sv"
       "$ROOT/rtl/rggen-sv-rtl/rggen_bit_field.sv"
       "$ROOT/rtl/rggen-sv-rtl/rggen_register_if.sv"
       "$ROOT/rtl/rggen-sv-rtl/rggen_address_decoder.sv"
       "$ROOT/rtl/rggen-sv-rtl/rggen_register_common.sv"
       "$ROOT/rtl/rggen-sv-rtl/rggen_default_register.sv"
       "$ROOT/rtl/rggen-sv-rtl/rggen_bus_if.sv"
       "$ROOT/rtl/rggen-sv-rtl/rggen_adapter_common.sv"
       "$ROOT/rtl/rggen-sv-rtl/rggen_apb_if.sv"
       "$ROOT/rtl/rggen-sv-rtl/rggen_apb_adapter.sv")
CSR="$ROOT/rtl/generated/rggen/ldo_csr.sv"
for f in "${RNM[@]}" "$DUT" "$CSR" "$ROOT/sim/rnm_core_tb.sv" \
         "$ROOT/sim/system_nominal_tb.sv" "$ROOT/sim/apb_master_bfm.sv" \
         "$ROOT/sim/apb_system_tb.sv" "${RGLIB[@]}"; do
  [[ -f "$f" ]] || blocked "missing source: ${f#"$ROOT"/}"
done

rm -rf "$OUT"
mkdir -p "$OUT/logs" "$OUT/build"
printf 'SIM: %s\n' "$("$VERILATOR_BIN" --version 2>/dev/null | head -1)"
printf 'SIM: results in %s (gitignored)\n' "${OUT#"$ROOT"/}"

vbuild() {
  local tag="$1" top="$2" log="$OUT/logs/$1.build.log"
  shift 2
  local mdir="$OUT/build/$tag"
  rm -rf "$mdir"; mkdir -p "$mdir"

  "$VERILATOR_BIN" --binary --timing --timescale 1ns/1ps -Wno-ZERODLY -j 0 \
    --top-module "$top" --Mdir "$mdir" "$@" > "$log" 2>&1
  local rc=$?
  [[ $rc -eq 0 ]] || {
    printf 'SIM_FAIL: verilator exited %s for %s, see %s\n' \
      "$rc" "$tag" "${log#"$ROOT"/}" >&2
    tail -n 20 "$log" >&2
    return 1
  }
  [[ -x "$mdir/V$top" ]] || { printf 'SIM_FAIL: no executable at %s\n' "$mdir/V$top" >&2; return 1; }
  printf '  built %s\n' "$tag"
}

# Testbenches write CSVs relative to cwd.
vrun() {
  local tag="$1" top="$2" marker="$3"
  shift 3
  local bin="$OUT/build/$tag/V$top" log="$OUT/logs/$tag.run.log"

  ( cd "$OUT" && "$bin" "$@" ) > "$log" 2>&1
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
vbuild rnm rnm_core_tb "${RNM[@]}" "$ROOT/sim/rnm_core_tb.sv" || exit 1
vrun rnm rnm_core_tb RNM_CORE_PASS \
  +CSV=rnm_nominal.csv +FULL_CSV=rnm_nominal_full.csv \
  +EN_RISE_NS=2000 +LOAD_RISE_NS=25000 +LOAD_FALL_NS=35000 +EN_FALL_NS=0 \
  +END_NS=50000 +DT_PS=10000 || exit 1

printf '\n=== system: SV-RNM + Veryl supervisor, 501 ticks ===\n'
vbuild system system_nominal_tb "${RNM[@]}" "$DUT" "$ROOT/sim/system_nominal_tb.sv" || exit 1
vrun system system_nominal_tb SYSTEM_NOMINAL_PASS \
  +CSV=system_nominal.csv \
  +EN_RISE_NS=2000 +LOAD_RISE_NS=25000 +LOAD_FALL_NS=35000 +EN_FALL_NS=0 \
  +END_NS=50000 +DT_PS=10000 || exit 1

printf '\n=== apb: RgGen CSR + SV-RNM + Veryl supervisor, integrated ===\n'
vbuild apb apb_system_tb "${RGLIB[@]}" "${RNM[@]}" "$DUT" "$CSR" \
  "$ROOT/sim/apb_master_bfm.sv" "$ROOT/sim/apb_system_tb.sv" || exit 1
vrun apb apb_system_tb APB_SYSTEM_PASS \
  +EN_RISE_NS=2000 +LOAD_RISE_NS=25000 +LOAD_FALL_NS=35000 \
  +END_NS=50000 +DT_PS=10000 || exit 1

printf '\nSIM_PASS\n'
