#!/usr/bin/env bash
# Run the reconstructed LDO system on Verilator -- the public OSS demo.
#
#   ./sim/run_verilator.sh
#
# Three simulations are built from the committed sources and run:
#
#   analog    rtl/rnm/pg_cmp_rnm.sv + rtl/rnm/ldo_rnm.sv + sim/rnm_core_tb.sv
#             -> results/generated/verilator/rnm_nominal.csv, rnm_nominal_full.csv
#   system    the same RNM plus the Veryl-generated supervisor
#             (rtl/generated/veryl/pgood_supervisor.sv) + sim/system_nominal_tb.sv
#             -> results/generated/verilator/system_nominal.csv
#   apb       the integrated system: the RgGen-generated CSR
#             (rtl/generated/rggen/ldo_csr.sv, compiled against the vendored
#             runtime RTL in third_party/rggen-sv-rtl/) supplies `en` through a
#             real APB transfer, with the same RNM + supervisor behind it
#             + sim/apb_system_tb.sv -> results/generated/verilator/apb_system.csv
#
# The analog and system runs provide the implementation outputs that MATLAB
# compares with the Simscape/Stateflow reference; the APB run shows the generated
# CSR actually driving the system. Every testbench is self-checking: each prints
# its PASS marker only when its own checks pass, and exits non-zero on failure.
# MATLAB reads the CSVs directly from results/generated/verilator/.
#
# Verilator comes from PATH by default; override the binary with VERILATOR_BIN:
#
#   VERILATOR_BIN   default: verilator (resolved from PATH)
#
# exit 0 PASS / 1 run failed / 2 blocked (toolchain or source missing)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERILATOR_BIN="${VERILATOR_BIN:-verilator}"
OUT="$ROOT/results/generated/verilator"

blocked() { printf 'SIM_BLOCKED: %s\n' "$*" >&2; exit 2; }
fail()    { printf 'SIM_FAIL: %s\n' "$*" >&2; exit 1; }

# --- toolchain ---------------------------------------------------------------

if [[ "$VERILATOR_BIN" == */* ]]; then
  [[ -x "$VERILATOR_BIN" ]] || blocked "VERILATOR_BIN is not executable: $VERILATOR_BIN"
elif ! command -v "$VERILATOR_BIN" >/dev/null 2>&1; then
  blocked "'$VERILATOR_BIN' is not on PATH (set VERILATOR_BIN to a path to override)"
fi
for tool in g++ make; do
  command -v "$tool" >/dev/null 2>&1 || blocked "'$tool' is not on PATH"
done

# --- sources (committed; never regenerated here) -----------------------------

RNM=("$ROOT/rtl/rnm/pg_cmp_rnm.sv" "$ROOT/rtl/rnm/ldo_rnm.sv")
DUT="$ROOT/rtl/generated/veryl/pgood_supervisor.sv"
# Vendored RgGen runtime RTL. `rggen_rtl_pkg.sv` must come first: the other files
# use its typedefs. Provenance: third_party/rggen-sv-rtl/README.md.
RGLIB=("$ROOT/third_party/rggen-sv-rtl/rggen_rtl_pkg.sv"
       "$ROOT/third_party/rggen-sv-rtl/rggen_or_reducer.sv"
       "$ROOT/third_party/rggen-sv-rtl/rggen_mux.sv"
       "$ROOT/third_party/rggen-sv-rtl/rggen_bit_field_if.sv"
       "$ROOT/third_party/rggen-sv-rtl/rggen_bit_field.sv"
       "$ROOT/third_party/rggen-sv-rtl/rggen_register_if.sv"
       "$ROOT/third_party/rggen-sv-rtl/rggen_address_decoder.sv"
       "$ROOT/third_party/rggen-sv-rtl/rggen_register_common.sv"
       "$ROOT/third_party/rggen-sv-rtl/rggen_default_register.sv"
       "$ROOT/third_party/rggen-sv-rtl/rggen_bus_if.sv"
       "$ROOT/third_party/rggen-sv-rtl/rggen_adapter_common.sv"
       "$ROOT/third_party/rggen-sv-rtl/rggen_apb_if.sv"
       "$ROOT/third_party/rggen-sv-rtl/rggen_apb_adapter.sv")
CSR="$ROOT/rtl/generated/rggen/ldo_csr.sv"
for f in "${RNM[@]}" "$DUT" "$CSR" "$ROOT/sim/rnm_core_tb.sv" \
         "$ROOT/sim/system_nominal_tb.sv" "$ROOT/sim/apb_master_bfm.sv" \
         "$ROOT/sim/apb_system_tb.sv" "${RGLIB[@]}"; do
  [[ -f "$f" ]] || blocked "missing source: ${f#"$ROOT"/}"
done

# OUT is owned entirely by this script: clear it so stale files from older
# revisions cannot survive.
rm -rf "$OUT"
mkdir -p "$OUT/logs" "$OUT/build"
printf 'SIM: %s\n' "$("$VERILATOR_BIN" --version 2>/dev/null | head -1)"
printf 'SIM: results in %s (gitignored)\n' "${OUT#"$ROOT"/}"

# --- helpers -----------------------------------------------------------------
#
# These flags are the ones this repository's Verilator runs were qualified with:
#   --binary             compile and link an executable
#   --timing             the testbenches advance time with #(dt_ns)
#   --timescale 1ns/1ps  the RNM and supervisors declare no timescale
#   -Wno-ZERODLY         #(dt_ns) is statically unknown; it is not #0
#   -j 0                 build with all cores
# -Wno-fatal is deliberately not used, so an unexpected warning stops the build.

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

# The testbenches open their CSVs by relative path, so they run with $OUT as cwd.
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

# --- run ---------------------------------------------------------------------

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
