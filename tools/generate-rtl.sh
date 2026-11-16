#!/usr/bin/env bash
# Regenerate the Veryl supervisor and the RgGen CSR into rtl/generated/.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
veryl build
rggen -c rtl/rggen/rggen.yml -o rtl/generated/rggen --enable sv_rtl rtl/rggen/ldo_csr.yml
