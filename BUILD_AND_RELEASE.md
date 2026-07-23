# Build & Release — MetaBurn

Organization-standard build and release guide for
[RazorBackRoar/MetaBurn](https://github.com/RazorBackRoar/MetaBurn).

## Overview

MetaBurn is a native macOS app built with **Swift** / **SwiftUI**
(swift-tools **6.3**, macOS 14+), packaged as an ad-hoc or Developer ID–signed `.dmg`.

Requires **ExifTool** at runtime (`brew install exiftool`). Video mute uses built-in AVFoundation (no ffmpeg).

## Platform Requirements

| Requirement | Value |
|-------------|-------|
| OS | macOS 14+ |
| Arch | Apple Silicon (`arm64`) |
| Toolchain | Swift Package Manager (`swift`), Package.swift tools 6.3 |
| Tests | Full **Xcode.app** required for `swift test` (Swift Testing / XCTest) |

## Prerequisites

```zsh
# Xcode Command Line Tools (or full Xcode)
xcode-select -p
cd /path/to/MetaBurn
swift build
swift test
```

## Development Build

```zsh
swift build
swift run
swift test
```

`swift test` requires the full Xcode.app.

## Packaging

```zsh
./scripts/build-mac.sh
```

Output:

```text
build/Release/MetaBurn.dmg
```

### Signing & notarization (optional)

Default builds are **ad-hoc** signed (Gatekeeper may require Right-click → Open).

For Developer ID + notarization, export before packaging:

```zsh
export METABURN_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
# Preferred:
export NOTARYTOOL_KEYCHAIN_PROFILE="notarytool-profile"
# Or:
# export APPLE_ID="you@example.com"
# export APPLE_TEAM_ID="TEAMID"
# export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"

./scripts/build-mac.sh
```

The script signs the `.app` with Hardened Runtime, builds the DMG, signs the DMG,
submits via `notarytool`, and staples the ticket when credentials are present.

## Release Process

1. Ensure `main` is green (CI `swift build` + `swift test`).
2. Confirm version in `Sources/MetaBurn/Resources/version.json`.
3. Run `./scripts/build-mac.sh` (with notarization env if releasing publicly).
4. Install/smoke-test by mounting `build/Release/MetaBurn.dmg` and dragging `MetaBurn.app` to `/Applications`.
5. Publish a GitHub Release and attach `build/Release/MetaBurn.dmg`.
6. Tag `vX.Y.Z` to match `Sources/MetaBurn/Resources/version.json`.

## Privacy notes

MetaBurn strips removable metadata (and optional video audio) on copies under
`~/Desktop/metaburn`. It does **not** alter pixels — faces, rooms, text, and other
in-frame content remain. Share only the cleaned copies you intend to publish.

## Versioning Expectations

- Semantic Versioning in `Sources/MetaBurn/Resources/version.json` (SSOT).
- Keep README version badges aligned when cutting a release.

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| `swift test` fails without XCTest | Install full Xcode.app, not only CLT |
| Gatekeeper blocks launch | Right-click → **Open**, or notarize with Developer ID |
| Stale `/Applications` copy | Mount `build/Release/MetaBurn.dmg` and drag `MetaBurn.app` to `/Applications` |
| Window size restored huge | Quit app; relaunch after upgrading (defaults may cache old frames) |
| ExifTool timeout on HEIC | Work copy is discarded; destination never written — retry or convert |

## Related Docs

- [README.md](README.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SECURITY.md](SECURITY.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
