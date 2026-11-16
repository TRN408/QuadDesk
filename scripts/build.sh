#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="${1:-$task_root/dist/QuadDesk.app}"
case "$app_dir" in /*) ;; *) app_dir="$PWD/$app_dir" ;; esac
cd "$task_root"
build_dir="${QUADDESK_BUILD_DIR:-$task_root/.build}"
mapping="$task_root=/QuadDesk"
flags=(--scratch-path "$build_dir" -c release
       -Xswiftc -gnone -Xcc -g0
       -Xswiftc -debug-prefix-map -Xswiftc "$mapping"
       -Xswiftc -file-prefix-map -Xswiftc "$mapping"
       -Xcc "-fdebug-prefix-map=$mapping" -Xcc "-ffile-prefix-map=$mapping")
swift build "${flags[@]}" --product QuadDisplayWatchdog
swift build "${flags[@]}" --product QuadDesk
python3 scripts/package.py "$build_dir/release/QuadDesk" "$app_dir"
