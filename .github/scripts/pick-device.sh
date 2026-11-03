#!/bin/bash
# Finds the Simulator model whose name matches <pattern> (an extended regex) and hands its type id
# to later steps as PERF_DEVICE_TYPE, for measure.sh and shots.sh to make their device from.
set -euo pipefail
pattern=${1:?usage: pick-device.sh <pattern>}
type=$(xcrun simctl list devicetypes | grep -E "$pattern" | head -n 1 \
  | sed -E 's/.*\((com\.apple\.CoreSimulator\.SimDeviceType\.[^)]*)\).*/\1/' || true)
if [ -z "$type" ]; then
  echo "::error::no Simulator model matches '$pattern' on this runner"
  xcrun simctl list devicetypes
  exit 1
fi
echo "Simulator model: $type"
xcrun simctl list runtimes | grep -i ios || true
echo "PERF_DEVICE_TYPE=$type" >> "$GITHUB_ENV"
