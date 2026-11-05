#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$project_root/.reference/transcribe.cpp"
build_dir="$project_root/.aurascribe/tools/transcribe-build"
revision=7045d1c0fe7cee37747b2792977421d435e75fca
if [[ ! -d "$source_dir/.git" ]]; then
  git clone https://github.com/anomalyco/transcribe.cpp "$source_dir"
fi
if [[ "$(git -C "$source_dir" rev-parse HEAD)" != "$revision" ]]; then
  git -C "$source_dir" checkout --detach "$revision"
fi
cmake -S "$source_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release \
  -DTRANSCRIBE_BUILD_TESTS=OFF -DTRANSCRIBE_BUILD_EXAMPLES=ON \
  -DTRANSCRIBE_BUILD_SHARED=OFF -DGGML_METAL_EMBED_LIBRARY=ON \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
cmake --build "$build_dir" --target transcribe-cli --parallel 2
mkdir -p "$project_root/.aurascribe/tools"
cp "$build_dir/bin/transcribe-cli" "$project_root/.aurascribe/tools/aurascribe-transcribe"
/usr/bin/codesign --force --sign - "$project_root/.aurascribe/tools/aurascribe-transcribe"
