#!/usr/bin/env bash
# Runs the session-list refresh benchmark suite and writes the metric lines to
# the file given as $1. The metrics are printed by the tests as
# "BENCHMETRIC <name> = <value>" and harvested from the xcodebuild log, because
# the tests run inside the simulator sandbox and cannot write to host paths.
set -euo pipefail

OUTPUT="${1:?usage: sessionlist-bench.sh <output-file> [sim-udid]}"
SIM_UDID="${2:-CAB2A791-4959-4304-A265-D762805F0E63}"
LOG="${OUTPUT%.txt}.xcodebuild.log"

cd "$(dirname "$0")/.."

: > "$OUTPUT"
export TEST_RUNNER_SESSIONLIST_BENCH_OUTPUT="$OUTPUT"

xcodebuild \
  -project HermesMobile.xcodeproj \
  -scheme HermesMobile \
  -destination "platform=iOS Simulator,id=${SIM_UDID}" \
  -derivedDataPath /tmp/slbench/DD \
  -only-testing:HermesMobileTests/SessionListRefreshBenchmarkTests \
  test 2>&1 | tee "$LOG" | grep -E "BENCHMETRIC|Test case|TEST (SUCCEEDED|FAILED)" || true

# The tests run in the simulator, whose stdout xcodebuild does not echo, so the
# metrics are collected from the report file the tests write (they receive its
# path through TEST_RUNNER_SESSIONLIST_BENCH_OUTPUT).
sort -u -o "$OUTPUT" "$OUTPUT"

echo "--- metrics written to $OUTPUT ---"
cat "$OUTPUT"

if ! grep -q "TEST SUCCEEDED" "$LOG"; then
  echo "BENCHMARK RUN FAILED (no TEST SUCCEEDED in $LOG)" >&2
  exit 1
fi
