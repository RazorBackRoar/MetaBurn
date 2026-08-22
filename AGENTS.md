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

Fully native: photos use **ImageIO**; videos use **AVFoundation** remux (metadata stripped; optional mute omits audio). No ExifTool, ffmpeg, or Homebrew runtime deps. Cancel interrupts in-flight AVFoundation exports.

**Photo quality:** JPEG, PNG, and TIFF are stripped without re-encoding pixels (JPEG marker rewrite; `CGImageDestinationCopyImageSource` for PNG/TIFF). Orientation is kept. HEIC/HEIF still convert to cleaned **`.jpg`** at `kCGImageDestinationLossyCompressionQuality = 1.0` because that is a container change, not a JPEG byte-copy.

**HEIC / HEIF:** Single Image I/O pass → cleaned **`.jpg`**. Originals never modified.

**iCloud Drive (secondary):** Drops from iCloud Drive are supported; online-only items download via `UbiquityGate` (can be slow). Core workflow is local files. Work files stay in local cache; originals never overwritten.

**Output:** Verified clean copies live only in MetaBurn’s private `~/Library/Application Support/MetaBurn/Open Files/{Photos,Videos}` workspace until the user copies or drags them out. Originals are never moved, renamed, overwritten, deleted, or modified.

- App entry: `Sources/MetaBurn/MetaBurnApp.swift`
- UI views: `Sources/MetaBurn/Views/`
- Services: `Sources/MetaBurn/Services/` (`MetadataCleaner`, `HeicJpegConverter`, `UbiquityGate`, `NativeImageIO`, …)
- Utilities: `Sources/MetaBurn/Utilities/`

Cleaned copies go only into MetaBurn’s private Open Files workspace. **Never** create `~/Desktop/MetaBurn` or `~/Pictures/MetaBurn`. Originals are never modified.

### RazorCore contracts (v1.1)

| Module | Role |
|--------|------|
| `MetaBurnCore` | Pure rules: SupportedTypes, OutputNaming, MetadataRules, HeicRules, OutputDestination / AdjacentOutput (unit-tested) |
| `Utilities/Brand.swift` | Display vs machine-safe IDs |
| `Utilities/Paths.swift` | Application Support / cache / logs under **MetaBurn**; never creates Pictures/MetaBurn or Desktop/MetaBurn |
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

Local output: `build/Release/MetaBurn.dmg` only.

## UI

- Drag-and-drop only — no browse / file-picker UI (never).
- While processing, show category count bubbles (Photos, Videos, etc.) with counts beside the title so progress is visible by media type.
- Theme setting (Auto / Light / Dark) must apply to the main window — do not force dark mode.
- Remove audio defaults on and lives at the far right of the footer; it permanently omits audio tracks from cleaned video copies.
- The centered footer button is **Open Files**. It opens the in-app private workspace, never a file picker.
- Cleaned files land in the private Open Files workspace. Remind users that visible picture/video content is not altered (only hidden metadata / optional audio). JPEG/PNG/TIFF strips are lossless; HEIC→JPG uses quality **1.0**.
- Packaging stays **ad-hoc signed** until a paid Apple Developer ID is available; do not require notarization.

## Output folders

Do **not** create `~/Desktop/MetaBurn` or `~/Pictures/MetaBurn`. The app-owned workspace is `~/Library/Application Support/MetaBurn/Open Files/` and contains exactly:

- `Photos` — verified clean photo copies
- `Videos` — verified clean video copies

Supported files are copied to a local cache work file before any metadata read or mutation, cleaned (and optionally stripped of audio), verified, then promoted into the matching workspace folder. Timeouts/failures discard the work file so destinations are never half-written. Originals stay untouched. Unsupported files are not imported or copied.

## Testing

Image/video testing uses **only** `/Users/home/Desktop/MetaBurn & L!bra Test` (`photos/` for images, `videos/` for videos). Never pull or process test media from Desktop/Downloads/Pictures/Movies/Workspace/elsewhere; generated outputs stay under that directory. Before any test, verify the source path starts with that prefix or stop.

App runtime output writes only to the private Open Files workspace. Never write `~/Desktop/MetaBurn` or `~/Pictures/MetaBurn`.

Unit tests live in `Tests/MetaBurnTests` against `MetaBurnCore` (`swift test`).

## Repository rules

- Do not create `Shared/razorcore-swift/` for v1.1.
- Do not commit, push, or create branches unless explicitly requested.

## Learned User Preferences

- Drag-and-drop only forever — never add browse/file-picker UI, and never auto-open Finder or Open panels to Desktop, Downloads, or output folders.
- The red **Remove audio** toggle lives at the far right of the footer; it permanently omits audio tracks so they cannot be recovered from the cleaned file.
- The red **Open Files** button is centered in the footer and opens the in-app Photos/Videos workspace.
- Originals are immutable inputs. Copy first, clean and verify only the private copy, then let the user export verified files by copy or drag-out. Never create `~/Desktop/MetaBurn` or `~/Pictures/MetaBurn`.
- Current product line is MetaBurn **2.2.9**; native ImageIO + AVFoundation only (no ExifTool/ffmpeg/Homebrew runtime deps). JPEG/PNG/TIFF strips are lossless (orientation kept). HEIC/HEIF → stripped `.jpg` is a single Image I/O pass at quality **1.0**. iCloud Drive support is secondary (UbiquityGate; downloads can be slow).
- Metadata table primary order: Make, Model, Camera, Lens, GPS Location, Date Created, Date Modified, Size, Resolution, Type. Date Created and Date Modified display as `mm/dd/yyyy`. Always show Make/Model/Camera/GPS Location/Date Created/Date Modified (dash if missing). Never show Software.
- Duplicate cleaned filenames use zero-padded sequential suffixes (`001`, `002`, `003`) — never `-1`/`-2` or trailing `X`/`XX`.
- Privacy is the product priority, but never at the cost of visible quality loss or destroying the photo/video; prefer remux/strip over re-encode.
- Match the screenshot-style single-window layout: centered MetaBurn header, large red dashed drop zone, simple cleaned-files list, footer status at left, Open Files centered, and Remove audio at far right. Open Files shows Photos/Videos folder cards and a native selectable file table in the same window; never use a second window, sheet, or file picker.
- Do not repeat “MetaBurn” in the macOS titlebar; the in-window brand is sufficient. Keep the traffic lights and settings gear on a transparent, subtly red-black titlebar that blends into the window.
- When rebuilding for the user to try: bump `Sources/MetaBurn/Resources/version.json` (patch), then `razorbuild` / `./scripts/build-mac.sh`. Output: `build/Release/MetaBurn.dmg`. Open that DMG yourself to install. Human UAT (notification permission, launch-at-login, sleep/wake) still happens before a GitHub Release. `scripts/open-dmg.sh` only if they explicitly ask to open it. Keep the locked 500×420 DMG layout.

## Learned Workspace Facts

- Re-dropping the same folder must always finish every file; half-written destinations and leftover `.metaburn.tmp` work files are bugs — discard the work file on timeout/failure and never promote it.
- Current product line is MetaBurn **2.2.9**; native ImageIO + AVFoundation only. JPEG/PNG/TIFF strips are lossless. HEIC convertAndStrip uses `kCGImageDestinationLossyCompressionQuality = 1.0`. Videos remux with passthrough only. iCloud is optional/secondary via `UbiquityGate`.
- Cancel must interrupt in-flight AVFoundation exports; batch jobs must not stall mid-count.
- Local package output is `build/Release/MetaBurn.dmg`.


## Jules Repository Contract

Jules reads this repository-root `AGENTS.md` when it clones the repository. Parent workspace policy files are not available in that clone.

- Jules runs tasks in an Ubuntu VM; SwiftUI, ImageIO, AVFoundation, iCloud behavior, packaged-app behavior, and macOS runtime behavior are not proven there.
- The repository's GitHub macOS `quality` workflow is authoritative for merge readiness.
- Daily audits must inspect existing open and recently closed PRs before proposing work, avoid duplicates, and open at most one focused PR per task.
- `sentinel-*` security, `bolt-*` performance, and `palette-*` design branches always require human review.
- Jules PRs are merged by the owner. There is no auto-merge workflow.
- PR descriptions must list changed files, risk, verification commands and results, benchmark evidence when relevant, and unverified paths.
- Never auto-merge runtime, dependency, lockfile, workflow, packaging, release, privacy, file-operation, or user-data changes.

## Automated Agent & Jules Integration Guidelines
- **Jules PR Review**: all Jules PRs require the owner to merge; there is no auto-merge workflow.
- **No Duplicate Issue/PR Reopening**: Jules subagents must verify existing closed and open PRs before proposing repetitive fixes or contact info updates.
- **Branch Cleanup**: Head branches are deleted automatically upon squash-merge.


### Jules Autonomous Execution Rules
- **Auto-Approve Plans**: Automatically approve execution plans for background suggestions (testing, code health, performance). Do not pause or wait for human plan approval on routine refactoring.
- **Batching**: Group related unit tests or code health fixes into a single PR rather than creating endless single-function PRs.
