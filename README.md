# MetaBurn

[![CI](https://img.shields.io/github/actions/workflow/status/RazorBackRoar/MetaBurn/ci.yml?branch=main&style=for-the-badge&label=CI)](https://github.com/RazorBackRoar/MetaBurn/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-1.0.0-blue?style=for-the-badge)](package.json)
[![License: MIT](https://img.shields.io/badge/license-MIT-blueviolet?style=for-the-badge)](LICENSE)
[![Electron](https://img.shields.io/badge/Electron-47848F?style=for-the-badge&logo=electron&logoColor=white)](https://www.electronjs.org/)
[![macOS](https://img.shields.io/badge/mac%20os-Apple%20Silicon-d32f2f?style=for-the-badge&logo=apple&logoColor=white)](https://support.apple.com/en-us/HT211814)

> **TL;DR:** Strip EXIF, GPS, and device metadata from photos and videos locally. Drag-and-drop workflow powered by ExifTool — nothing leaves your Mac.

## Branding

| Surface | Value |
|---------|-------|
| Display name | **MetaBurn** |
| GitHub | [RazorBackRoar/MetaBurn](https://github.com/RazorBackRoar/MetaBurn) |
| npm | `metaburn` |
| appId | `com.razorbackroar.metaburn` |

## Development

```bash
npm install
npm run type-check
npm run build
npm start
```

Package a macOS build with `npm run dist`.

Per-app Electron helpers live under `electron-core/` (not a shared workspace package). Contracts: see the Apps workspace `Docs/razorcore-api-spec.md`.

## License

MIT — see [LICENSE](LICENSE).
