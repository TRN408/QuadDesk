#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
build_dir="${QUADDESK_BUILD_DIR:-$task_root/.build}"
swift test --scratch-path "$build_dir"
swift build --scratch-path "$build_dir" -c release --product QuadDeskNativePreview
swift build --scratch-path "$build_dir" -c release --product QuadDisplayWatchdog
python3 scripts/package_native_preview.py "$build_dir/release/QuadDeskNativePreview" "$build_dir/release/QuadDisplayWatchdog" "$1"
