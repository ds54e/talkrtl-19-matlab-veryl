#!/usr/bin/env bash
# Launch Windows MATLAB from WSL and return its batch exit status.
set -euo pipefail
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  printf '%s\n' 'Usage: bash tools/matlab-batch.sh "MATLAB statement"' \
    'MATLAB_EXE: optional MATLAB.exe path (WSL or Windows form).' \
    "Default statement: addpath('matlab'); run_demo"
  exit 0
fi
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
exe=${MATLAB_EXE:-$(command -v matlab.exe || true)}
if [[ -z "$exe" ]]; then
  candidates=(/mnt/{c,d,e}/Program\ Files/MATLAB/R*/bin/matlab.exe)
  exe=${candidates[0]}
fi
case "$exe" in [A-Za-z]:*) exe=$(wslpath -u "$exe");; esac
out="$root/results/generated"
mkdir -p "$out"
log="$out/matlab-$(date -u +%Y%m%dT%H%M%SZ)-$$.log"
statement=${1:-"addpath('matlab'); run_demo"}
printf 'MATLAB: %s\nLog: %s\n' "$exe" "$log" >&2
# -wait is required to receive MATLAB's exit status.
set +e
"$exe" -wait -sd "$(wslpath -w "$root")" -logfile "$(wslpath -w "$log")" -batch "$statement"
rc=$?
set -e
printf 'MATLAB exit status: %s\n' "$rc" >&2
exit "$rc"
