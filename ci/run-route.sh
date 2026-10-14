#!/usr/bin/env bash
set -euo pipefail
python3 /work/ci/wait-review.py
/work/ci/compile.sh /work/scripts/vivado.sh -mode batch -source /work/hardware/kv260/implement.tcl -tclargs md
python3 /work/scripts/export-implementation.py md
python3 /work/scripts/pack-core.py /work/ci-output/MD02-Diag-2026.k26 --id Genesis --firmware /build/kria-mister-md-vivado/implementation/md.bit.bin --overlay /work/reference-firmware/overlay.dtbo
cp /build/kria-mister-md-vivado/implementation/implementation.json /work/ci-output/
mkdir -p /work/ci-output/routed-reports
cp /build/kria-mister-md-vivado/implementation/*.rpt /work/ci-output/routed-reports/
sha256sum /work/ci-output/MD02-Diag-2026.k26 > /work/ci-output/MD02-Diag-2026.sha256
