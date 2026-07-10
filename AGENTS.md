# MetaBurn AGENTS

Guidance for agents in this repository. Use with `../AGENTS.md`.

## Branding

| Surface | Value |
|---------|-------|
| Display name | **MetaBurn** |
| GitHub | `RazorBackRoar/MetaBurn` |
| `appId` | `com.razorbackroar.metaburn` |
| Executable | `MetaBurn` |

Constants: `Sources/MetaBurn/Utilities/Brand.swift`.

## Purpose and entry points

Local photo/video metadata stripper (ExifTool). Swift + SwiftUI.

- App entry: `Sources/MetaBurn/MetaBurnApp.swift`
- UI views: `Sources/MetaBurn/Views/`
- Services: `Sources/MetaBurn/Services/`
- Utilities: `Sources/MetaBurn/Utilities/`

### RazorCore contracts (v1.1)

| Module | Role |
|--------|------|
| `Utilities/Brand.swift` | Display vs machine-safe IDs |
| `Utilities/Paths.swift` | Application Support / cache / logs under **MetaBurn** |
| `Utilities/Logging.swift` | Console + file logs under Application Support |
| `Utilities/AppInfo.swift` | Metadata + startup banner |
| `Utilities/Updates.swift` | GitHub Releases check (`RazorBackRoar/MetaBurn`) |

Behavioral SSOT: `../Docs/razorcore-api-spec.md`.

## Commands

```zsh
swift build
swift run
```

`swift test` requires the full Xcode.app (XCTest); the command-line tools ship without it.

Package a macOS `.app` and DMG with ad-hoc signing:

```zsh
./scripts/build-mac.sh
```

Output is in `build/Release/MetaBurn.app` and `build/Release/MetaBurn.dmg`.

## Repository rules

- Do not create `Shared/razorcore-swift/` for v1.1.
- Do not commit, push, or create branches unless explicitly requested.
