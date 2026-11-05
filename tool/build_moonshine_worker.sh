#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_root/.aurascribe/tools"
dart_bin="${FLUTTER_ROOT:-}/bin/cache/dart-sdk/bin/dart"
if [[ ! -x "$dart_bin" ]]; then dart_bin="$(command -v dart)"; fi
cd "$project_root"
"$dart_bin" compile exe tool/moonshine_worker.dart -o .aurascribe/tools/aurascribe-moonshine
