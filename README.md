# MetaBurn

[![Version](https://img.shields.io/badge/version-1.0.0-blue?style=for-the-badge)](Sources/MetaBurn/Resources/version.json)
[![License: MIT](https://img.shields.io/badge/license-MIT-blueviolet?style=for-the-badge)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org/)
[![macOS](https://img.shields.io/badge/mac%20os-Apple%20Silicon-d32f2f?style=for-the-badge&logo=apple&logoColor=white)](https://support.apple.com/en-us/HT211814)

> **TL;DR:** Strip EXIF, GPS, and device metadata from photos and videos locally. Drag-and-drop workflow powered by ExifTool — nothing leaves your Mac.

## Branding

| Surface | Value |
|---------|-------|
| Display name | **MetaBurn** |
| GitHub | [RazorBackRoar/MetaBurn](https://github.com/RazorBackRoar/MetaBurn) |
| appId | `com.razorbackroar.metaburn` |

## Development

```bash
swift build
swift run
```

`swift test` requires the full Xcode.app (XCTest).

Package a macOS `.app` and DMG with ad-hoc signing:

```bash
./scripts/build-mac.sh
```

Output: `build/Release/MetaBurn.app` and `build/Release/MetaBurn.dmg`.

## License

MIT — see [LICENSE](LICENSE).
