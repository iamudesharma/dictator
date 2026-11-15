# Third-party software

## Hex

https://github.com/anomalyco/hex

MIT License

Copyright (c) 2026 Christopher Langton

Virtual microphone driver: Copyright (c) 2026 Kit Langton.
Virtual driver adapted from Hex 6813f740; application names and CoreAudio UIDs changed.
Chromium 155–156 input workaround and Unicode chunking in
`TextInsertionPolicy.swift` adapted from Hex paste.rs and keyboard.rs.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


## transcribe.cpp

https://github.com/anomalyco/transcribe.cpp

MIT License

Copyright (c) 2026 The transcribe.cpp authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


## transcribe.cpp third-party notices

https://github.com/anomalyco/transcribe.cpp

# Third-party licenses

transcribe.cpp is MIT-licensed (see [`LICENSE`](LICENSE)). It vendors and links
the third-party components below, each under its own permissive license. The
authoritative license text for each ships in-tree at the path noted; copies are
reproduced here for convenience.

| Component | License | Vendored at | Pin |
|-----------|---------|-------------|-----|
| ggml      | MIT     | [`ggml/LICENSE`](ggml/LICENSE) | see [`ggml/UPSTREAM`](ggml/UPSTREAM) |
| Silero VAD | MIT | [`src/third_party/silero_vad/LICENSE`](src/third_party/silero_vad/LICENSE) | see [`src/third_party/silero_vad/UPSTREAM`](src/third_party/silero_vad/UPSTREAM) |
| miniz     | MIT     | [`src/third_party/miniz/LICENSE`](src/third_party/miniz/LICENSE) | see [`src/third_party/miniz/UPSTREAM`](src/third_party/miniz/UPSTREAM) |

Prebuilt artifacts (the Swift xcframework, the native Python wheels, and the
npm platform packages) carry these same texts alongside the binaries — see each
binding's packaging for the bundled `LICENSE.ggml` / `LICENSE.miniz` / `LICENSE.silero_vad` files.

Conversion-time tooling also includes `scripts/lib/phonon.py`, adapted from
Fermion Research's Apache-2.0 container reader at
`FermionResearch/Phonon-2@7e153e4054c0a10db6d47d6fff5c062d4c77c154`.
Copyright 2026 Fermion Research. Modifications add strict record validation,
pinned artifact handling and F32 conversion. Its license text is
[`scripts/lib/phonon-LICENSE-Apache-2.0.txt`](scripts/lib/phonon-LICENSE-Apache-2.0.txt).
It is not linked into native binaries. Model-weight attribution and licenses
are separate; see [`docs/models/phonon-2.md`](docs/models/phonon-2.md).

---

## ggml

The tensor library underlying transcribe.cpp. Vendored under `ggml/`.

```
MIT License

Copyright (c) 2023-2026 The ggml authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## miniz

A single-file deflate/inflate (zlib-subset) codec. transcribe.cpp uses it only
for Whisper's temperature-fallback compression-ratio heuristic; it replaces the
previous system-zlib dependency. Vendored under `src/third_party/miniz/`.

miniz is MIT-licensed. (The comment block at the top of the amalgamated
`miniz.c` / `miniz.h` still reads "public domain" — a stale artifact from the
project's pre-relicensing history; upstream's current and authoritative license
is the MIT text below, also shipped at `src/third_party/miniz/LICENSE`.)

```
Copyright 2013-2014 RAD Game Tools and Valve Software
Copyright 2010-2014 Rich Geldreich and Tenacious Software LLC

All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

---

## Silero VAD

The offline segmentation in `src/transcribe-vad.cpp` is
translated from `silero_vad/utils_vad.py`, pinned to silero-vad 6.2.3. The
authoritative text is `src/third_party/silero_vad/LICENSE`; native artifacts
include it as `LICENSE.silero_vad`.

```
MIT License

Copyright (c) 2020-present Silero Team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Additional speech model catalog references

Artifact metadata for Orukeet and Granite Speech 5.0, model language capabilities,
language labels and published benchmark records are sourced from Hex
v3.4.0, commit 8766d096eb3c98a5b1a54cb966a6daa717bc839d (MIT, above).
Weights are optional downloads and are not included in this repository.

Orukeet: Oruk AI, based on NVIDIA Parakeet TDT 0.6B v3 (base: CC BY 4.0);
Oruk AI's r3 adaptation: CC BY-SA 4.0. GGUF conversion and Q8 quantization
by handy-computer, without retraining. Source and notice:
https://huggingface.co/handy-computer/orukeet-gguf/blob/c5511a3850fce1cbbfa5d94ef815966e1d99275f/README.md
License: https://creativecommons.org/licenses/by-sa/4.0/legalcode.en

Granite Speech 5.0 470M TurboCTC multilingual: IBM Granite (Apache-2.0);
GGUF distribution includes license and notice:
https://huggingface.co/17slever17/granite-speech-5.0-470m-turboctc-multilingual-GGUF/tree/62f64d9d5ad35989b06caf199cafe7155944a22b

### Hex interface translations

`tool/l10n/hex.json` and the Traditional Chinese conversion table are adapted from
Anomaly's Hex v3.4.0 (`8766d096eb3c98a5b1a54cb966a6daa717bc839d`), specifically
`src/desktop/i18n.rs` and `src/desktop/i18n/`. They are distributed under the Hex
MIT license reproduced above. AuraScribe-specific interface strings are maintained
in `tool/l10n/*.tsv`; generated runtime catalogs are in `assets/l10n/`.

### Shared GGML runtime modification

The shared speech runtime builds pinned transcribe.cpp with the project-owned
`tool/native_patches/accelerate_gemv.patch`, using Apple's system Accelerate
framework for supported float32 matrix-vector products. The upstream transcribe.cpp
and GGML notices above continue to apply. The optional CLI source is unmodified.
