#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
developer="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
sdk="$(DEVELOPER_DIR="$developer" xcrun --sdk macosx --show-sdk-path)"
"$developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++" -O2 -std=c++17 \
 -isysroot "$sdk" -mmacosx-version-min=13.0 \
 -I "$root/.reference/transcribe.cpp/ggml/include" \
 "$root/tool/verify_accelerate_gemv.cpp" -L "$root/.aurascribe/tools/native" \
 -Wl,-rpath,"$root/.aurascribe/tools/native" -lggml-cpu.0.26.0 -lggml-base.0.26.0 \
 -o "$root/.aurascribe/tools/verify-accelerate-gemv"
"$root/.aurascribe/tools/verify-accelerate-gemv"
