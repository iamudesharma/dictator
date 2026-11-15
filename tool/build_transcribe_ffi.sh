#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
reference_dir="$root/.reference/transcribe.cpp"
revision=7045d1c0fe7cee37747b2792977421d435e75fca
[[ -d "$reference_dir/.git" ]] || git clone https://github.com/anomalyco/transcribe.cpp "$reference_dir"
[[ "$(git -C "$reference_dir" rev-parse HEAD)" == "$revision" ]] || { echo 'Native speech source revision differs from pinned ABI' >&2; exit 1; }
# Keep the pinned reference untouched. Prepare a content-addressed source tree
# with the reviewed project-owned performance patch for this shared runtime.
patch_file="$root/tool/native_patches/accelerate_gemv.patch"
patch_hash="$(shasum -a 256 "$patch_file" | cut -d ' ' -f 1)"
source_dir="$root/.aurascribe/tools/transcribe-native-source/$revision-$patch_hash"
if [[ ! -f "$source_dir/.aurascribe-prepared" ]]; then
  mkdir -p "$(dirname "$source_dir")"
  git clone --shared --no-checkout "$reference_dir" "$source_dir"
  git -C "$source_dir" checkout --detach "$revision"
  git -C "$source_dir" apply --check "$patch_file"
  git -C "$source_dir" apply "$patch_file"
  touch "$source_dir/.aurascribe-prepared"
fi
developer="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
sdk="$(DEVELOPER_DIR="$developer" xcrun --sdk macosx --show-sdk-path)"
build="$root/.aurascribe/tools/transcribe-ffi-build-${patch_hash:0:12}"
cmake -S "$source_dir" -B "$build" -DCMAKE_BUILD_TYPE=Release \
 -DCMAKE_C_COMPILER="$developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang" \
 -DCMAKE_CXX_COMPILER="$developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++" \
 -DCMAKE_C_FLAGS="-DAURASCRIBE_ACCELERATE_GEMV=1" \
 -DCMAKE_OSX_SYSROOT="$sdk" -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
 -DTRANSCRIBE_BUILD_SHARED=ON -DTRANSCRIBE_BUILD_TESTS=OFF -DTRANSCRIBE_BUILD_EXAMPLES=OFF \
 -DTRANSCRIBE_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON
cmake --build "$build" --target transcribe --parallel 4
output="$root/.aurascribe/tools/native"
mkdir -p "$output"
"$developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang" -O3 -dynamiclib \
 -isysroot "$sdk" -mmacosx-version-min=13.0 \
 "$root/macos/native/pcm_reader.c" -o "$output/libaurascribe_audio.dylib"
# Keep the matching ggml dylibs adjacent; resolve every non-system dependency
# relative to its owning library rather than a developer's build directory.
find "$build" -type f -name '*.dylib' -exec cp {} "$output/" \;
python3 - "$build" "$output" <<'PY_NATIVE'
import pathlib,subprocess,sys
build,output=map(pathlib.Path,sys.argv[1:])
names={p.name:p.resolve().name for p in build.rglob('*.dylib')}
for lib in output.glob('*.dylib'):
 subprocess.run(['install_name_tool','-id','@rpath/'+lib.name,str(lib)],check=True)
 dependencies=subprocess.check_output(['otool','-L',str(lib)],text=True).splitlines()[1:]
 for line in dependencies:
  dependency=line.strip().split(' (')[0]; name=pathlib.Path(dependency).name
  if name in names:
   subprocess.run(['install_name_tool','-change',dependency,'@loader_path/'+names[name],str(lib)],check=True)
 subprocess.run(['codesign','--force','--sign','-',str(lib)],check=True)
PY_NATIVE
