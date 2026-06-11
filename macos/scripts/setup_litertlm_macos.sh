#!/bin/bash
# Copies flutter_gemma LiteRT-LM companion libraries into the app bundle.
# LiteRtLm.framework links against @rpath/libGemmaModelConstraintProvider.dylib;
# the dylib must live in Contents/Frameworks (do not delete it after copying frameworks).
set -euo pipefail

FRAMEWORKS="${BUILT_PRODUCTS_DIR:?}/${PRODUCT_NAME:?}.app/Contents/Frameworks"
if [ ! -d "${FRAMEWORKS}" ]; then
  exit 0
fi

for base in LiteRtMetalAccelerator LiteRtTopKMetalSampler; do
  rm -f "${FRAMEWORKS}/lib${base}.dylib"
done

PLUGIN_PREBUILT=""
for candidate in \
    "${HOME}/Library/Caches/flutter_gemma/native/macos_arm64" \
    "${PODS_ROOT:-}/../Flutter/ephemeral/.symlinks/plugins/flutter_gemma/native/litert_lm/prebuilt/macos_arm64" \
    "${SRCROOT:-}/../../native/litert_lm/prebuilt/macos_arm64"; do
  if [ -f "${candidate}/libGemmaModelConstraintProvider.dylib" ]; then
    PLUGIN_PREBUILT="${candidate}"
    break
  fi
done

if [ -z "${PLUGIN_PREBUILT}" ]; then
  echo "[flutter_gemma] ERROR: Could not find macOS companion dylibs in any of:"
  echo "  - ${HOME}/Library/Caches/flutter_gemma/native/macos_arm64/"
  echo "  - Flutter plugin prebuilt/macos_arm64/"
  echo "  Run 'flutter clean && flutter pub get' to repopulate the Native Assets cache."
  exit 1
fi

echo "[flutter_gemma] Using companion dylibs from: ${PLUGIN_PREBUILT}"

# Required for LiteRtLm dlopen — must be a loose dylib in Frameworks/.
GEMMA_DYLIB_SRC="${PLUGIN_PREBUILT}/libGemmaModelConstraintProvider.dylib"
GEMMA_DYLIB_DST="${FRAMEWORKS}/libGemmaModelConstraintProvider.dylib"
cp -f "${GEMMA_DYLIB_SRC}" "${GEMMA_DYLIB_DST}"
install_name_tool -id "@rpath/libGemmaModelConstraintProvider.dylib" "${GEMMA_DYLIB_DST}" 2>/dev/null || true
codesign --force --sign - "${GEMMA_DYLIB_DST}" 2>/dev/null || true
echo "[flutter_gemma] installed ${GEMMA_DYLIB_DST}"

for base in LiteRtMetalAccelerator LiteRtTopKMetalSampler; do
  src="${PLUGIN_PREBUILT}/lib${base}.dylib"
  if [ ! -f "${src}" ]; then
    echo "[flutter_gemma] WARNING: ${src} not found — skipping ${base}.framework"
    continue
  fi
  fw_dir="${FRAMEWORKS}/${base}.framework"
  mkdir -p "${fw_dir}/Versions/A/Resources"
  cp -f "${src}" "${fw_dir}/Versions/A/${base}"
  install_name_tool -id "@rpath/${base}.framework/Versions/A/${base}" \
    "${fw_dir}/Versions/A/${base}" 2>/dev/null || true
  (cd "${fw_dir}" && ln -sfh A Versions/Current && ln -sfh "Versions/Current/${base}" "${base}" && ln -sfh "Versions/Current/Resources" Resources)
  cat > "${fw_dir}/Versions/A/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>${base}</string>
  <key>CFBundleIdentifier</key><string>dev.flutterberlin.flutter_gemma.${base}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
</dict>
</plist>
EOF
  codesign --force --sign - "${fw_dir}/Versions/A/${base}" 2>/dev/null || true
  echo "[flutter_gemma] copied ${base}.framework"
done

LITERTLM="${FRAMEWORKS}/LiteRtLm.framework/Versions/A/LiteRtLm"
if [ -f "${LITERTLM}" ]; then
  codesign --force --sign - "${LITERTLM}" 2>/dev/null || true
  echo "[flutter_gemma] re-signed LiteRtLm"
fi

if [ -n "${SCRIPT_OUTPUT_FILE_0:-}" ]; then
  mkdir -p "$(dirname "${SCRIPT_OUTPUT_FILE_0}")"
  touch "${SCRIPT_OUTPUT_FILE_0}"
fi
