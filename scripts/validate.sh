#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
swift test --scratch-path "${QUADDESK_BUILD_DIR:-$task_root/.build}"
probe_build_dir="${QUADDESK_BUILD_DIR:-$task_root/.build}/input-probe"
mkdir -p "$probe_build_dir"
swiftc "$task_root/Tests/Fixtures/InputProbe.swift" -o "$probe_build_dir/QuadDeskInputProbe"
./scripts/build.sh "${1:-$task_root/dist/QuadDesk.app}"
