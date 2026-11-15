#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter_bin="${FLUTTER_BIN:-$PWD/.aurascribe/tools/flutter-3.50.0/bin/flutter}"
"$flutter_bin" build macos --release "$@"
bash tool/sign_local_app.sh build/macos/Build/Products/Release/AuraScribe.app
