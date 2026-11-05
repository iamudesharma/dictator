#!/bin/bash
set -euo pipefail
project_root="$(cd "${SRCROOT}/.." && pwd)"
runtime="$project_root/.aurascribe/tools/aurascribe-transcribe"
if [[ ! -x "$runtime" ]]; then
  bash "$project_root/tool/build_transcribe_runtime.sh"
fi
resources="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
mkdir -p "$resources"
cp "$runtime" "$resources/aurascribe-transcribe"
/usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$resources/aurascribe-transcribe"

if [[ ! -f "$project_root/.aurascribe/tools/AuraScribeMicrophone.pkg" ]]; then
  bash "$project_root/tool/build_virtual_microphone.sh"
fi
cp "$project_root/.aurascribe/tools/AuraScribeMicrophone.pkg" "$resources/AuraScribeMicrophone.pkg"
cp "$project_root/THIRD_PARTY_NOTICES.md" "$resources/THIRD_PARTY_NOTICES.md"

# Recompile when source/lock/SDK changes; never download model weights here.
moonshine="$project_root/.aurascribe/tools/aurascribe-moonshine"
moonshine_stamp="$project_root/.aurascribe/tools/moonshine-sdk.txt"
current_sdk="${FLUTTER_ROOT:-unknown}"
if [[ ! -x "$moonshine" || "$project_root/tool/moonshine_worker.dart" -nt "$moonshine" || "$project_root/pubspec.lock" -nt "$moonshine" || ! -f "$moonshine_stamp" || "$(cat "$moonshine_stamp")" != "$current_sdk" ]]; then
  bash "$project_root/tool/build_moonshine_worker.sh"
  printf '%s' "$current_sdk" > "$moonshine_stamp"
fi
cp "$moonshine" "$resources/aurascribe-moonshine"
/usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$resources/aurascribe-moonshine"
