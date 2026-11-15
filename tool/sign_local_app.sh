#!/bin/bash
# Preserve local macOS privacy identity across development rebuilds.
set -euo pipefail
app="${1:-build/macos/Build/Products/Release/AuraScribe.app}"
identity="${AURASCRIBE_SIGNING_IDENTITY:-VoiceToText Dev}"
if [[ ! -d "$app" ]]; then
  echo "App bundle missing: $app" >&2
  exit 1
fi
# Sign the outer bundle only; preserve existing helper signatures/entitlements.
# A certificate-backed designated requirement survives changing executable hashes.
codesign --force --sign "$identity" --preserve-metadata=entitlements,flags "$app"
codesign --verify --deep --strict "$app"
requirement="$(codesign -d -r- "$app" 2>&1)"
if [[ "$requirement" == *'designated => cdhash '* ]]; then
  echo 'Refusing a hash-bound local app identity.' >&2
  exit 1
fi
printf '%s\n' "$requirement"
