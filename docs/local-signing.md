# Local builds and macOS Accessibility permission

The installed app inspected on November 13 was ad-hoc signed: its designated
requirement was only `cdhash`, so rebuilding changed the identity to which macOS
had granted Accessibility. A checked old entry could therefore coexist with
`AXIsProcessTrusted() == false` in the updated application.

`tool/sign_local_app.sh` signs an existing bundle with the existing local
`VoiceToText Dev` certificate, preserving entitlements and nested signatures.
The verified requirement is now the app identifier plus the certificate leaf,
instead of the executable hash. It does not grant or reset any macOS permission.

For future local releases:

```bash
FLUTTER_BIN=/Users/udesh/Downloads/flutter3/bin/flutter bash tool/build_local_release.sh
```

To sign an existing build:

```bash
bash tool/sign_local_app.sh /path/to/AuraScribe.app
```

An immediately usable copy of the currently installed application was prepared
at `build/local-signed/AuraScribe.app`; its binary and bundled models/runtime have
not been rebuilt or replaced. `codesign --verify --deep --strict` passed.

One-time recovery after moving from the old ad-hoc identity:

1. Quit AuraScribe from its menu bar menu.
2. Replace `/Applications/AuraScribe.app` with the signed copy above.
3. System Settings → Privacy & Security → Accessibility: remove the old AuraScribe
   entry, add `/Applications/AuraScribe.app`, and enable it.
4. Reopen the installed app and check Accessibility in General before dictating.

Keep using the same certificate and installed location for local rebuilds.
This is local development signing, not Developer ID distribution/notarization.
The existing signed-updater distribution requirements still apply.

Apple documents hash-bound ad-hoc requirements in
[TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
