# MetaBurn

[![Download](https://img.shields.io/github/v/release/RazorBackRoar/MetaBurn?style=for-the-badge&label=Download%20DMG&color=d32f2f)](https://github.com/RazorBackRoar/MetaBurn/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/RazorBackRoar/MetaBurn/ci.yml?branch=main&style=for-the-badge&label=CI)](https://github.com/RazorBackRoar/MetaBurn/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blueviolet?style=for-the-badge)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org/)
[![macOS](https://img.shields.io/badge/mac%20os-Apple%20Silicon-d32f2f?style=for-the-badge&logo=apple&logoColor=white)](https://support.apple.com/en-us/HT211814)

**Strip EXIF, GPS, and device metadata from photos and videos — locally on macOS.**

Drag files in. MetaBurn writes cleaned copies to `~/Desktop/metaburn` (Photos / Videos). Originals stay untouched. Optional mute removes video audio. What’s visible in the frame is not altered.

<p align="center">
  <a href="https://github.com/RazorBackRoar/MetaBurn/releases/latest/download/MetaBurn.dmg"><strong>↓ Download MetaBurn.dmg</strong></a>
  ·
  <a href="https://github.com/RazorBackRoar/MetaBurn/releases">All releases</a>
</p>

![MetaBurn](docs/screenshots/app.png)

## Features

- **Local-first privacy** — metadata stays on your Mac; nothing is uploaded
- **Drag-and-drop** — drop photos/videos onto the window
- **Safe by default** — writes cleaned copies; originals never overwritten
- **EXIF / GPS / device tags** — stripped via ExifTool
- **Optional video mute** — remove audio from cleaned video copies
- **Apple Silicon native** — Swift / SwiftUI

## Install

1. Download [`MetaBurn.dmg`](https://github.com/RazorBackRoar/MetaBurn/releases/latest/download/MetaBurn.dmg)
2. Open the DMG and drag **MetaBurn.app** to `/Applications`
3. First launch — right-click → **Open** (ad-hoc signed build)

Requires macOS on Apple Silicon.

## Usage

1. Open **MetaBurn**
2. Drop photos and/or videos onto the window
3. Find cleaned copies in `~/Desktop/metaburn/Photos` and `~/Desktop/metaburn/Videos`
4. Enable mute when you also want audio removed from video copies

## Development

```bash
swift build
swift run
swift test   # requires full Xcode.app
```

Package a macOS `.app` + DMG (ad-hoc signed):

```bash
./scripts/build-mac.sh
# → build/Release/MetaBurn.dmg
```

## Docs

- [BUILD_AND_RELEASE.md](BUILD_AND_RELEASE.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SECURITY.md](SECURITY.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)

## License

MIT — see [LICENSE](LICENSE).
