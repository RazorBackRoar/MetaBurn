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

Cleaned copies are written to `~/Desktop/metaburn/Photos` and `~/Desktop/metaburn/Videos`. Originals are never overwritten.

### RazorCore contracts (v1.1)

| Module | Role |
|--------|------|
| `Utilities/Brand.swift` | Display vs machine-safe IDs |
| `Utilities/Paths.swift` | Application Support / cache / logs under **MetaBurn**; Desktop output under `metaburn/` |
| `Utilities/Logging.swift` | Console + file logs under Application Support |
| `Utilities/AppInfo.swift` | Metadata + startup banner |
| `Utilities/Updates.swift` | GitHub Releases check (`RazorBackRoar/MetaBurn`) |
| `Utilities/ThemePreference.swift` | Auto / Light / Dark appearance |

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

Output is `build/Release/MetaBurn.dmg` only (the `.app` is consumed during packaging).

## UI

- While processing, show category count bubbles (Photos, Videos, etc.) with counts beside the title so progress is visible by media type.
- Theme setting (Auto / Light / Dark) must apply to the main window — do not force dark mode.
- Mute video audio defaults on; cleaned files land under Desktop/metaburn.

## Output folders

On launch and before each job, ensure:

- `~/Desktop/metaburn/Photos`
- `~/Desktop/metaburn/Videos`

Supported files are copied there, then cleaned (and optionally muted). Originals stay untouched.

## Testing

Image/video testing uses **only** `/Users/home/Desktop/MetaBurn & L!bra Test` (`photos/` for images, `videos/` for videos). Never pull or process test media from Desktop/Downloads/Pictures/Movies/Workspace/elsewhere; generated outputs stay under that directory. Before any test, verify the source path starts with that prefix or stop.

App runtime output for real cleans is `~/Desktop/metaburn/` (separate from the agent test-media tree).

## Repository rules

- Do not create `Shared/razorcore-swift/` for v1.1.
- Do not commit, push, or create branches unless explicitly requested.
