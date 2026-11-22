#!/usr/bin/env bash
# Maps the temperature sensors of this Mac: records every HID temperature sensor and SMC T* key once a
# second through idle, a P-core load, an E-core load and a GPU load, then prints how much each one rose
# under each load. Takes about 8 minutes and heats the Mac; quit heavy apps first.
#
#   ./scripts/thermal-sensor-map/run.sh [output-dir]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT"
P_CORES="$(sysctl -n hw.perflevel0.logicalcpu)"
E_CORES="$(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null || echo 0)"

swiftc -O "$HERE/record.swift" -o "$OUT/record"
swiftc -O "$HERE/gpuload.swift" -o "$OUT/gpuload"

caffeinate -d -i -w $$ &
: > "$OUT/samples.csv"
"$OUT/record" "$OUT/samples.csv" &
RECORDER=$!
trap 'kill $RECORDER 2>/dev/null; killall yes 2>/dev/null || true' EXIT

: > "$OUT/phases.csv"
mark() { echo "$(date +%s),$1" >> "$OUT/phases.csv"; echo "$(date +%T) $1"; }
load() { local n=$1; shift; for _ in $(seq "$n"); do "$@" yes > /dev/null & done; sleep 90; killall yes 2>/dev/null || true; }

mark idle;   sleep 40
mark pcores; load "$P_CORES" env
mark cool1;  sleep 60
mark ecores; load "$E_CORES" taskpolicy -b
mark cool2;  sleep 60
mark gpu;    "$OUT/gpuload" 90
mark cool3;  sleep 60
mark end

python3 -I "$HERE/analyze.py" "$OUT"
echo "Raw data: $OUT"
