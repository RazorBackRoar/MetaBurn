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

Cleaned copies are written to `~/Desktop/MetaBurn/Photos`, `~/Desktop/MetaBurn/Videos`, and bypassed files to `~/Desktop/MetaBurn/Skippable`. Originals are never overwritten.

### RazorCore contracts (v1.1)

| Module | Role |
|--------|------|
| `MetaBurnCore` | Pure rules: SupportedTypes, OutputNaming, MetadataRules (unit-tested) |
| `Utilities/Brand.swift` | Display vs machine-safe IDs |
| `Utilities/Paths.swift` | Application Support / cache / logs under **MetaBurn**; Desktop output under `MetaBurn/` |
| `Utilities/Logging.swift` | Console + file logs under Application Support |
| `Utilities/AppInfo.swift` | Metadata + startup banner |
| `Utilities/Updates.swift` | GitHub Releases check (`RazorBackRoar/MetaBurn`) |
| `Utilities/ThemePreference.swift` | Auto / Light / Dark appearance |

Behavioral SSOT: `../Docs/razorcore-api-spec.md`.

## Commands

```zsh
swift build
swift run
swift test
```

`swift test` requires the full Xcode.app (Swift Testing); the command-line tools alone are not enough.

Package a macOS `.app` and DMG with ad-hoc signing (or Developer ID + notarization when env credentials are set — see `BUILD_AND_RELEASE.md`):

```zsh
./scripts/build-mac.sh
```

Output is `build/Release/MetaBurn.dmg` only (the `.app` is consumed during packaging).

## UI

- While processing, show category count bubbles (Photos, Videos, etc.) with counts beside the title so progress is visible by media type.
- Theme setting (Auto / Light / Dark) must apply to the main window — do not force dark mode.
- Mute video audio defaults on and is shown only when the job includes videos.
- Cleaned files land under Desktop/MetaBurn. Remind users that visible picture/video content is not altered (only hidden metadata / optional audio).
- Packaging stays **ad-hoc signed** until a paid Apple Developer ID is available; do not require notarization.

## Output folders

On launch and before each job, ensure:

- `~/Desktop/MetaBurn/Photos`
- `~/Desktop/MetaBurn/Videos`
- `~/Desktop/MetaBurn/Skippable` (unsupported / non-writable drops; includes `skipped-summary.txt`)

Supported files are copied to a local cache work file, cleaned (and optionally muted), then promoted to the final path. Timeouts/failures discard the work file so destinations are never half-written. Originals stay untouched. GIF and WebM are always unsupported and routed to Skippable.

## Testing

Image/video testing uses **only** `/Users/home/Desktop/MetaBurn & L!bra Test` (`photos/` for images, `videos/` for videos). Never pull or process test media from Desktop/Downloads/Pictures/Movies/Workspace/elsewhere; generated outputs stay under that directory. Before any test, verify the source path starts with that prefix or stop.

App runtime output for real cleans is `~/Desktop/MetaBurn/` (separate from the agent test-media tree).

Unit tests live in `Tests/MetaBurnTests` against `MetaBurnCore` (`swift test`).

## Repository rules

- Do not create `Shared/razorcore-swift/` for v1.1.
- Do not commit, push, or create branches unless explicitly requested.
