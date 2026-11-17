# ePdfUB

<p align="center">
  <img src="assets/ePdfUB%20icon.png" alt="ePdfUB app icon" width="120">
</p>

Turn small-print PDFs into EPUBs you can read at your own font size. Conversion runs on your device.

[![Download on the App Store](https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg)](https://apps.apple.com/tw/app/make-it-flow/id6780764422?l=en-GB)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)

![Demo showing a small-print PDF on a phone, importing it into ePdfUB, and reading the reflowed EPUB](assets/epdfub-demo.gif)

[Try the sample PDF](assets/brewing-notes.pdf) · [Download the demo MP4](assets/epdfub-demo.mp4)

## How to use it

1. Import a PDF into ePdfUB.
2. Export it as an EPUB.
3. Open the EPUB in Apple Books or your preferred EPUB reader.

PDFs with selectable text and a clear reading order are the best starting point. Scans and complex layouts can need a closer look after conversion.

[Build from source, use the CLI, or see the benchmarks](docs/technical-guide.md).

## License and acknowledgements

- **ePdfUB source code** is available under the [GNU Affero General Public License, version 3](LICENSE). The [technical guide](docs/technical-guide.md) explains how to build the app and CLI from source.
- **EPUB reader** uses Readium Swift Toolkit 3.8.0 under the [BSD 3-Clause License](https://github.com/readium/swift-toolkit/blob/3.8.0/LICENSE). The full notice appears below.
- **Layout detection model weights** come from [hantian/yolo-doclaynet](https://huggingface.co/hantian/yolo-doclaynet), licensed under AGPL-3.0. The models use [Ultralytics YOLOv26](https://github.com/ultralytics/ultralytics) and were trained on DocLayNet.
- **Brand assets** are all rights reserved. The AGPL grant for the source code excludes the ePdfUB name and app icon.
- **Third-party test documents** in [evaluation](evaluation/) are subject to their own terms. Check the original source before redistributing them.

<details>
<summary>Readium Swift Toolkit 3.8.0 license</summary>

```text
BSD 3-Clause License

Copyright (c) 2017, Readium
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

</details>
