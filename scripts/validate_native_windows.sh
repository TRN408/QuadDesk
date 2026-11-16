#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
swift test --scratch-path "${QUADDESK_BUILD_DIR:-$task_root/.build}"
bash scripts/build.sh "${1:-$task_root/dist/QuadDesk.app}"
