#!/usr/bin/env bash
# Simulate RgGen CSR + SV-RNM LDO + Veryl supervisor with xezim.
# Writes signals.csv and wave.fst to results/generated/xezim.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/results/generated/xezim"
rm -rf "$OUT" && mkdir -p "$OUT" && cd "$OUT"

xezim -V | head -1
xezim --simulate --module-timescale 1ns/1ps -s apb_system_tb \
  --fst wave.fst --fst-scope 2:apb_system_tb \
  "$ROOT"/rtl/rggen-sv-rtl/*.sv "$ROOT"/rtl/rnm/*.sv "$ROOT"/rtl/generated/*/*.sv "$ROOT"/sim/*.sv \
  > sim.log 2>&1
status=$?
grep '^APB_SYSTEM' sim.log
[[ $status -eq 0 ]] || { tail -n 20 sim.log; echo "SIM_FAIL (see ${OUT#"$ROOT"/}/sim.log)"; exit 1; }
echo "Waveform: ${OUT#"$ROOT"/}/wave.fst"
