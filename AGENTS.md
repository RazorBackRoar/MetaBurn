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

Local photo/video metadata stripper. Swift + SwiftUI.

Local photo/video metadata stripper. Swift + SwiftUI.

Fully native: photos use **ImageIO**; videos use **AVFoundation** remux (metadata stripped; optional mute omits audio). No ExifTool, ffmpeg, or Homebrew runtime deps. Cancel interrupts in-flight AVFoundation exports.

- App entry: `Sources/MetaBurn/MetaBurnApp.swift`
- UI views: `Sources/MetaBurn/Views/`
- Services: `Sources/MetaBurn/Services/`
- Utilities: `Sources/MetaBurn/Utilities/`

Cleaned copies are written under `~/Desktop/MetaBurn/` only when needed: `Photos` for cleaned photos, `Videos` for cleaned videos, `Skippable` for bypassed files. Subfolders (and the root) are created dynamically — never on launch. Originals are never overwritten.

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

- Drag-and-drop only — no browse / file-picker UI (never).
- While processing, show category count bubbles (Photos, Videos, etc.) with counts beside the title so progress is visible by media type.
- Theme setting (Auto / Light / Dark) must apply to the main window — do not force dark mode.
- Mute video audio defaults on and is shown on the empty start screen (and results footer).
- Cleaned files land under Desktop/MetaBurn. Remind users that visible picture/video content is not altered (only hidden metadata / optional audio).
- Packaging stays **ad-hoc signed** until a paid Apple Developer ID is available; do not require notarization.

## Output folders

Do **not** create `~/Desktop/MetaBurn` (or Photos / Videos / Skippable) on launch or at job start.

Create each folder only when first needed:

- `Photos` — when cleaning a photo
- `Videos` — when cleaning a video
- `Skippable` — when exporting skipped/unsupported files (`skipped-summary.txt` lives here)

Supported files are copied to a local cache work file, cleaned (and optionally muted), then promoted to the final path. Timeouts/failures discard the work file so destinations are never half-written. Originals stay untouched. GIF and WebM are always unsupported and routed to Skippable.

## Testing

Image/video testing uses **only** `/Users/home/Desktop/MetaBurn & L!bra Test` (`photos/` for images, `videos/` for videos). Never pull or process test media from Desktop/Downloads/Pictures/Movies/Workspace/elsewhere; generated outputs stay under that directory. Before any test, verify the source path starts with that prefix or stop.

App runtime output for real cleans is `~/Desktop/MetaBurn/` (separate from the agent test-media tree).

Unit tests live in `Tests/MetaBurnTests` against `MetaBurnCore` (`swift test`).

## Repository rules

- Do not create `Shared/razorcore-swift/` for v1.1.
- Do not commit, push, or create branches unless explicitly requested.

## Learned User Preferences

- Drag-and-drop only forever — never add browse/file-picker UI, and never auto-open Finder or Open panels to Desktop, Downloads, or output folders.
- Mute video audio toggle lives in the bottom-right footer (no top mute banner; no Desktop/MetaBurn path label there); mute means permanently omit audio tracks so they cannot be recovered from the cleaned file.
- Metadata table primary order: Created, Lens, GPS, Size, Modified, Resolution, Type; never show Software; pin fields untouched by the burn to the bottom of the list.
- Duplicate cleaned filenames use zero-padded sequential suffixes (`001`, `002`, `003`) — never `-1`/`-2` or trailing `X`/`XX`.
- Privacy is the product priority, but never at the cost of visible quality loss or destroying the photo/video; prefer remux/strip over re-encode.
- Prefer a slightly taller/wider default window and one step larger UI font across the app.
- When rebuilding for the user to try: build in-repo (`build/Release/MetaBurn.dmg`), copy to `~/Desktop/MetaBurn.dmg`, then **stop** — do not open/mount/launch; the user double-clicks the Desktop DMG, drags to Applications, and ejects manually. Never open a DMG twice. `scripts/open-dmg.sh` only if they explicitly ask to open it. Keep the locked 500×420 DMG layout. SSOT: `Apps/AGENTS.md` Post-Build.

## Learned Workspace Facts

- Re-dropping the same folder must always finish every file; half-written destinations and leftover `.metaburn.tmp` work files are bugs — discard the work file on timeout/failure and never promote it.
- Current product line is MetaBurn **2.0.0**; native ImageIO + AVFoundation only (no ExifTool/ffmpeg/Homebrew runtime deps).
- Cancel must interrupt in-flight AVFoundation exports; batch jobs must not stall mid-count.
