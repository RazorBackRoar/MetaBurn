# MetaBurn AGENTS

Guidance for agents in this repository. Use with `../AGENTS.md`.

## Branding

| Surface | Value |
|---------|-------|
| Display name | **MetaBurn** |
| GitHub | `RazorBackRoar/MetaBurn` |
| npm `name` | `metaburn` |
| `appId` | `com.razorbackroar.metaburn` |
| Executable | `MetaBurn` (default; no override in `package.json`) |

Constants: `electron-core/utils/brand.ts`.

## Purpose and entry points

Local photo/video metadata stripper (ExifTool). Electron + React/Vite.

- Main: `main/index.ts`
- Renderer: `renderer/`
- Per-app Electron adapters: `electron-core/` (not a shared workspace package)

### electron-core contracts (v1.1)

| Module | Role |
|--------|------|
| `utils/brand.ts` | Display vs machine-safe IDs |
| `utils/paths.ts` | userData / cache under **MetaBurn** |
| `utils/logging.ts` | Logs under Application Support |
| `utils/appInfo.ts` | Metadata + startup banner |
| `utils/updates.ts` | GitHub Releases check (`RazorBackRoar/MetaBurn`) |

Behavioral SSOT: `../Docs/razorcore-api-spec.md`.

## Commands

```zsh
npm run type-check
npm run build
npm run lint
npm start
npm run dist
```

## Repository rules

- Do not create `Shared/razorcore-ts/` for v1.1.
- Do not commit, push, or create branches unless explicitly requested.
