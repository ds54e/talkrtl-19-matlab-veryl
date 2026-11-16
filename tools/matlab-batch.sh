#!/usr/bin/env bash
# Run a MATLAB statement in Windows MATLAB from WSL; the default is the MATLAB
# side of the demo. Needs this checkout on a Windows drive and matlab.exe on PATH.
cd "$(dirname "${BASH_SOURCE[0]}")/.."
matlab.exe -wait -sd "$(wslpath -w .)" -batch "${1:-addpath('matlab'); run_demo}"
