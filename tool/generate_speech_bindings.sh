#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
dart_bin="${DART_BIN:-$root/.aurascribe/tools/flutter-3.50.0/bin/dart}"
(cd "$root/tool/native_bindings" && "$dart_bin" pub get)
entry="$(python3 - "$root/tool/native_bindings/.dart_tool/package_config.json" <<'PY'
import json,sys,pathlib,urllib.parse
p=pathlib.Path(sys.argv[1]).resolve()
e=next(x for x in json.loads(p.read_text())['packages'] if x['name']=='ffigen')
print(urllib.parse.urljoin(p.as_uri(),e['rootUri']).removeprefix('file://')+'/bin/ffigen.dart')
PY
)"
cd "$root"
"$dart_bin" --packages=tool/native_bindings/.dart_tool/package_config.json "$entry" --config ffigen.yaml
