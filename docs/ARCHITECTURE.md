# Architecture — MetaBurn

Developer map for the local metadata stripper (SwiftUI + ImageIO + AVFoundation).

## Layer split

| Layer | Path | Role |
|-------|------|------|
| **MetaBurnCore** | `Sources/MetaBurnCore/` | Pure rules — types, naming, output paths, HEIC rules, work-file safety |
| **App** | `Sources/MetaBurn/` | UI, services, AVFoundation/ImageIO adapters |

Unit tests target `MetaBurnCore` (`Tests/MetaBurnTests/CoreTests.swift`). App
layer tests (e.g. `PathsTests`) use `@testable import MetaBurn`.

## Core modules (`MetaBurnCore`)

| Module | Role |
|--------|------|
| `SupportedTypes` | Photo/video/unsupported classification |
| `OutputNaming` | Zero-padded duplicate suffixes (`001`, `002`, …) |
| `OutputDestination` | Desktop vs adjacent output roots |
| `MetadataRules` | Which fields to strip vs display |
| `HeicRules` | HEIC/HEIF → stripped JPEG contract |
| `WorkFileSafety` | Validated xattr paths for cache work files |
| `SkipSummary` | Skipped-file export rules |

## Services (`Sources/MetaBurn/Services/`)

| Service | Role |
|---------|------|
| `MetadataCleaner` | Batch orchestration |
| `NativeImageIO` | Still-image strip (JPEG quality **1.0**) |
| `HeicJpegConverter` | Single-pass HEIC → `.jpg` |
| `NativeVideoClean` | AVFoundation remux strip (optional mute) |
| `Scanner` | Drop intake, type routing |
| `UbiquityGate` | iCloud Drive online-only download |
| `OutputRootResolver` | Desktop vs adjacent folder creation |
| `TaskRunner` | Async job queue, cancel |
| `SkipExporter` | Unsupported → `Skippable/` |

## Processing flow

```text
Drop → Scanner (SupportedTypes)
  → local cache work file (.metaburn.tmp)
  → NativeImageIO / HeicJpegConverter / NativeVideoClean
  → promote to Photos/ | Videos/ | Skippable/
```

- **Originals are never overwritten.** Folders are created on first use only.
- **Cancel** interrupts in-flight AVFoundation exports.
- **GIF / WebM** are always unsupported → `Skippable/`.

## Supported formats

| Category | Extensions | Output |
|----------|------------|--------|
| Photos | jpg, jpeg, png, heic, heif, webp, tiff, bmp, jp2 | `Photos/` (HEIC → `.jpg`) |
| Videos | mov, mp4, m4v | `Videos/` (remux strip) |
| Non-writable video | avi, mkv | `Skippable/` |
| Always unsupported | gif, webm | `Skippable/` |

## Output destinations

**Desktop (default):** `~/Desktop/MetaBurn/{Photos,Videos,Skippable}`

**Adjacent:** `<source-dir>/MetaBurn/{Photos,Videos,Skippable}`

## Updates security

`GithubPinningDelegate` pins TLS public keys for `api.github.com` update
checks. Rotating GitHub certificates requires updating pinned hashes in source.

## User data paths

| Path | Contents |
|------|----------|
| `~/Library/Application Support/MetaBurn/` | Settings, logs |
| `~/Library/Caches/MetaBurn/` | Update check cache |

## Related docs

- [BUILD_AND_RELEASE.md](../BUILD_AND_RELEASE.md)
- [CONTRIBUTING.md](../CONTRIBUTING.md)
- [AGENTS.md](../AGENTS.md)
