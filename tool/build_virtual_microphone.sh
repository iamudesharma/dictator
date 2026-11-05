#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
output="$project_root/.aurascribe/tools/virtual-microphone"
driver="$output/root/Library/Audio/Plug-Ins/HAL/AuraScribeMicrophone.driver"
mkdir -p "$driver/Contents/MacOS" "$output/scripts"
xcrun --sdk macosx clang -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -arch arm64 -mmacosx-version-min=13.0 -std=c11 -O2 -fvisibility=hidden -bundle \
  -framework CoreAudio -framework CoreFoundation \
  "$project_root/native/AuraScribeMicrophoneDriver/AuraScribeMicrophoneDriver.c" \
  -o "$driver/Contents/MacOS/AuraScribeMicrophoneDriver"
cp "$project_root/native/AuraScribeMicrophoneDriver/Info.plist" "$driver/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$driver"
cat > "$output/scripts/postinstall" <<'SCRIPT'
#!/bin/sh
/usr/sbin/chown -R root:wheel /Library/Audio/Plug-Ins/HAL/AuraScribeMicrophone.driver
/usr/bin/killall coreaudiod || true
exit 0
SCRIPT
chmod +x "$output/scripts/postinstall"
/usr/bin/pkgbuild --root "$output/root" --scripts "$output/scripts" --identifier com.aurascribe.microphone.installer \
  --version 1.0.0 "$project_root/.aurascribe/tools/AuraScribeMicrophone.pkg"
