# Build & Release — MetaBurn

Organization-standard build and release guide for
[RazorBackRoar/MetaBurn](https://github.com/RazorBackRoar/MetaBurn).

## Overview

MetaBurn is a native macOS app built with **Swift** / **SwiftUI**
(swift-tools 5.10+, macOS 14+), packaged with an ad-hoc signed `.app` / `.dmg`.

Requires **ExifTool** at runtime (`brew install exiftool`); optional **ffmpeg** for mute-audio.

## Platform Requirements

| Requirement | Value |
|-------------|-------|
| OS | macOS 14+ |
| Arch | Apple Silicon (`arm64`) |
| Toolchain | Swift Package Manager (`swift`) |
| Tests | Full **Xcode.app** required for `swift test` (XCTest) |

## Prerequisites

```zsh
# Xcode Command Line Tools (or full Xcode)
xcode-select -p
cd /path/to/MetaBurn
swift build
```

## Development Build

```zsh
swift build
swift run
```

`swift test` requires the full Xcode.app.

## Packaging

```zsh
./scripts/build-mac.sh
```

Output:

```text
build/Release/MetaBurn.app
build/Release/MetaBurn.dmg
```

## Release Process

1. Ensure `main` is green (CI `swift build`).
2. Confirm version in `Sources/MetaBurn/Resources/version.json`.
3. Run `./scripts/build-mac.sh`.
4. Install/smoke-test the `.app` (core happy path).
5. Publish a GitHub Release and attach the `.dmg`.
6. Tag `vX.Y.Z` to match `Sources/MetaBurn/Resources/version.json`.

## Versioning Expectations

- Semantic Versioning in `Sources/MetaBurn/Resources/version.json` (SSOT).
- Keep README version badges aligned when cutting a release.

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| `swift test` fails without XCTest | Install full Xcode.app, not only CLT |
| Gatekeeper blocks launch | Right-click → **Open** (ad-hoc signed builds) |
| Stale `/Applications` copy | Rebuild, then `ditto build/Release/MetaBurn.app` into Applications |
| Window size restored huge | Quit app; relaunch after upgrading (defaults may cache old frames) |

## Related Docs

- [README.md](README.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SECURITY.md](SECURITY.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
