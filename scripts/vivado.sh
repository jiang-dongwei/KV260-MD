#!/usr/bin/env bash
set -euo pipefail
# Container allocator/udev conflict in FlexNet host-information enumeration.
# Preload the real system library; do not replace license-manager behavior.
# Matching report: https://github.com/fastmachinelearning/hls4ml-tutorial/issues/81
udev=/lib/x86_64-linux-gnu/libudev.so.1
test -r "$udev"
export LD_PRELOAD="$udev${LD_PRELOAD:+:$LD_PRELOAD}"
if [[ -z ${XILINXD_LICENSE_FILE:-} && -r /tmp/Xilinx.lic ]]; then
 export XILINXD_LICENSE_FILE=/tmp/Xilinx.lic
fi
case ${KRIA_VIVADO_VERSION:-auto} in
 2026.1) candidates=(/opt/Xilinx/2026.1/Vivado/bin/vivado) ;;
 2023.2) candidates=(/opt/Xilinx/Vivado/2023.2/bin/vivado /opt/Xilinx/2023.2/Vivado/bin/vivado) ;;
 auto) candidates=(/opt/Xilinx/2026.1/Vivado/bin/vivado /opt/Xilinx/Vivado/2023.2/bin/vivado /opt/Xilinx/2023.2/Vivado/bin/vivado) ;;
 *) echo "Unsupported KRIA_VIVADO_VERSION: $KRIA_VIVADO_VERSION" >&2; exit 2 ;;
esac
for candidate in "${candidates[@]}"; do
 if [[ -x "$candidate" ]]; then
  export XILINX_VIVADO="${candidate%/bin/vivado}"
  exec "$candidate" "$@"
 fi
done
echo "No Vivado executable found for ${KRIA_VIVADO_VERSION:-auto} in the container" >&2
exit 127
