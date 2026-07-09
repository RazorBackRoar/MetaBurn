# MetaBurn AGENTS

Guidance for AI agents working in this repository.

## Branding

| Surface | Value |
|---------|-------|
| Display name | **MetaBurn** |
| GitHub repo | `RazorBackRoar/MetaBurn` |
| npm `name` | `metaburn` |
| `appId` | `com.razorbackroar.metaburn` |

Constants live in `electron-core/utils/brand.ts`.

## Purpose And Entry Points

MetaBurn strips photo/video metadata locally (ExifTool). Electron + React/Vite.

- Main: `main/index.ts`
- Renderer: `renderer/`
- Per-app Electron adapters: `electron-core/` (not a shared workspace package)

## Commands

```zsh
npm run type-check
npm run build
npm start
```

## Repository Rules

- Do not create a shared `Shared/razorcore-ts/` package for v1.1.
- Do not commit/push/branch unless explicitly requested.
