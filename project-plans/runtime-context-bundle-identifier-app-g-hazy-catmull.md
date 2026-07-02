# MetaCleaner — Local Drag-and-Drop Metadata Cleaner

## Context

MetaCleaner is a local-only macOS utility (Glaze/Raycast app) that strips identifying metadata
(EXIF, GPS, XMP, IPTC, QuickTime, device/camera/software tags) from photos and videos **in place**,
with no backups, no renames, no copies, and no network access. The user drags files/folders from
Finder onto a drop zone; the app builds an explicit, path-bounded file list from exactly what was
dropped, then runs the system Homebrew `exiftool` on each supported file. It shows a live per-file
log, live counters, and a final summary. Correctness and file safety take priority over speed.

The app is a fresh Glaze template scaffold. All heavy lifting (fs scanning + `exiftool` execution)
must live in the **backend** (`main/`, Node.js) because it needs `fs` and `child_process`; the
**renderer** (`renderer/`, React) is the drag-and-drop UI. Communication is over the native IPC
bridge already exposed by the scaffold.

### Confirmed decisions (from user)
- **Photos:** preserve the ICC color profile while stripping everything else (avoids color shifts).
- **Videos:** fully clean MOV/MP4/M4V; MKV/WEBM/AVI are left untouched and logged as `skipped` with
  a clear reason (ExifTool cannot safely rewrite those containers).

### Verified platform facts (no preload changes needed — all exposed by default)
- `window.glazeAPI.webUtils.getPathForFile(file: File) => string` — absolute path of a dropped file/folder.
- `window.glazeAPI.glaze.ipc.invoke(channel, ...args)` — request/reply to backend.
- `window.glazeAPI.glaze.ipc.onNotification(channel, cb) => unsubscribe` — receive backend broadcasts.
- Backend `ipcMain.handle(channel, handler)` and `ipcMain.broadcast(channel, ...args)` (from `@glaze/core/backend`).

## Architecture

- **Backend (all core logic).** Modular services under `main/services/`, thin IPC handler under
  `main/handlers/`. Cleaning runs sequentially, file-by-file, so cancel checks and progress
  broadcasts happen between files. No shell strings — `execFile` with argument arrays only.
- **Frontend.** Single focused view: drop zone + status + live log + counters + Clear Log / Cancel.
  Uses `@glaze/core` design-system components (no hand-rolled CSS).
- **No new npm dependencies.** Uses Node `fs`/`path`/`child_process` + system `exiftool`.

## Backend — files to create

### `main/services/supportedTypes.ts`
- `PHOTO_EXTS = new Set([".jpg",".jpeg",".png",".heic",".heif",".webp",".tiff"])`
- `VIDEO_EXTS = new Set([".mov",".mp4",".m4v",".avi",".mkv",".webm"])`
- Classification helpers (case-insensitive via `path.extname(name).toLowerCase()`):
  - `classify(filePath)` → `{ kind: "photo" | "video" | "unsupported", writable: boolean, ext }`.
  - `writable = false` for `.mkv`, `.webm`, `.avi` (container not safely rewritable → will be `skipped`).
  - All photo exts + `.mov`/`.mp4`/`.m4v` are `writable = true`.

### `main/services/scanner.ts`
Builds the **explicit** file list from only the dropped paths — the safety core.
- `buildFileList(droppedPaths: string[]): { files: string[]; scannedCount }`.
- For each dropped path: `fs.promises.lstat`.
  - **Symlink → skip** (never follow; satisfies "no symlinks outside dropped folder"). Record skip reason.
  - **File →** include as-is (it was explicitly dropped; supported-ness checked later).
  - **Directory →** recurse with `fs.promises.readdir(dir, { withFileTypes: true })`, using `lstat`
    per entry, skipping any symlink, staying strictly within the dropped root. Only collect regular files.
- Never infers parents, never touches siblings of a dropped file, never special-cases
  Desktop/Home/Downloads/Workspace — those are processed only if that exact folder was the dropped path.
- Dedupe paths (in case of overlapping drops) before returning.

### `main/services/metadataCleaner.ts`
- `resolveExiftool(): Promise<string | null>` — probe, in order: `/opt/homebrew/bin/exiftool`
  (Apple Silicon), `/usr/local/bin/exiftool` (Intel), then `execFile("/usr/bin/which","exiftool")`.
  Cache the result. Returns null if not found.
- `cleanFile(exiftoolPath, filePath): Promise<Result>` where
  `Result = { path, status: "cleaned"|"skipped"|"failed"|"partial", reason?: string }`.
  - `classify` first. Unsupported ext → `skipped` ("unsupported file type").
  - Non-writable video container → `skipped` ("container not safely writable by ExifTool").
  - **Photo args:** `["-all=", "-tagsFromFile", "@", "-icc_profile:all", "-overwrite_original", filePath]`
    (strips EXIF/GPS/XMP/IPTC/MakerNotes/software, restores ICC color profile).
  - **Video args (mov/mp4/m4v):** `["-all=", "-overwrite_original", filePath]`.
  - Run via `execFile(exiftoolPath, args, { timeout: 60_000, maxBuffer: 10*1024*1024 })`.
  - On error → `failed` with `err.message` (exiftool leaves the file unchanged on failure).
  - Parse exiftool stdout for `1 image files updated` vs `0 image files updated` /
    `weren't updated due to errors` to distinguish `cleaned` vs `partial`/`failed`.

### `main/services/taskRunner.ts`
Orchestrates a run and drives progress + cancellation.
- Module-level `activeJob: { id, cancelled: boolean } | null`.
- `runClean(jobId, droppedPaths, broadcast): Promise<Summary>`:
  1. `resolveExiftool()`; if null → broadcast `error: exiftool-missing` and return early.
  2. Broadcast `state: "scanning"`; `buildFileList`.
  3. Broadcast `state: "cleaning"` with total supported count.
  4. Iterate files sequentially. Before each: if `activeJob.cancelled` → break and mark run cancelled.
     For each result, broadcast a `clean:progress` event `{ jobId, path, status, reason, counters }`.
  5. Broadcast `state: "done"` (or `"failed"`/cancelled) + final `Summary`
     `{ supported, cleaned, skipped, failed, partial, cancelled }`.
- `cancel(jobId)` sets `cancelled = true`.

### `main/handlers/clean.ts` (+ register in `main/handlers/index.ts`)
- `ipcMain.handle("clean:start", (_e, { paths }) => taskRunner.runClean(newId, paths, ipcMain.broadcast))`
  — returns the final `Summary` (renderer also gets live events).
- `ipcMain.handle("clean:cancel", (_e, { jobId }) => taskRunner.cancel(jobId))`.
- `ipcMain.handle("clean:checkExiftool", () => resolveExiftool().then(p => ({ available: !!p, path: p })))`.
- Add `import { cleanHandlers } from "./clean.js"` and register calls inside existing
  `registerHandlers()` in `main/handlers/index.ts` (colon-namespaced, matching scaffold convention).
- Progress broadcasts use `ipcMain.broadcast("clean:progress", payload)` and `"clean:state"`.

## Frontend — files to modify

### `renderer/main/home-view.tsx` (replace template content)
Single view, built with `@glaze/core` components (invoke `glaze-component-patterns` +
`glaze-drag-and-drop` + `glaze-icon-usage` skills during implementation). Structure:
- **On mount:** `invoke("clean:checkExiftool")`. If unavailable, show a prominent notice:
  “ExifTool is required. Install it with: `brew install exiftool`” and disable the drop zone.
- **Drop zone (large):** `onDragOver` (preventDefault to allow drop), `onDrop`:
  - `Array.from(e.dataTransfer.files)` → `webUtils.getPathForFile(f)` for each → non-empty paths array.
  - Immediately call `invoke("clean:start", { paths })`; auto-start cleaning.
- **Status state machine:** `Waiting for files → Scanning → Cleaning → Done/Failed` (also Cancelled).
  Rendered as a status pill/badge.
- **Live log:** subscribe via `onNotification("clean:progress", …)` and `onNotification("clean:state", …)`
  in a `useEffect` (store unsubscribe, clean up on unmount). Each log row = file path +
  `cleaned/skipped/failed/partial` badge + reason when not cleaned.
- **Counters row:** Supported found · Cleaned · Skipped · Failed · Partial.
- **Actions:** `Clear Log` (resets log + counters, only when idle) and `Cancel`
  (`invoke("clean:cancel", { jobId })`, visible only while scanning/cleaning).
- Keep the existing draggable title-bar region from `root-view.tsx`.

### `main/index.ts` — window sizing
- Invoke `glaze-window-sizing` skill; set a focused utility size (approx `width: 560, height: 700,
  minWidth: 440, minHeight: 560`) suited to a drop zone + scrolling log. Keep default frame +
  traffic lights (no custom chrome, no CSS blur).

## Safety guarantees (enforced in code)
- Explicit file list built **only** from dropped paths; no parent inference, no sibling processing.
- Symlinks never followed (lstat + skip) → nothing outside a dropped folder is touched.
- `-overwrite_original` → no `_original` backups; files never moved/renamed/copied.
- `execFile` with argument arrays → no shell interpolation, no wildcard expansion, paths passed literally.
- On any exiftool error the file is left unchanged and reported as `failed`.
- No network calls, no telemetry anywhere in the code.

## Validation
1. `npm run type-check && npm run lint` (from `.glaze-sources/`).
2. Build the app (canonical host build) and launch it.
3. Runtime checks via live DOM inspection / manual drop:
   - Missing-exiftool path: temporarily verify the install notice renders when probe returns unavailable.
   - Drop a single photo → verify status flows Waiting→Scanning→Cleaning→Done, log row `cleaned`,
     counters increment. Confirm with `exiftool <file>` that GPS/EXIF/device tags are gone and the
     ICC profile remains; confirm no `_original` file was created.
   - Drop a folder with mixed photos/videos + an unsupported file → recursive scan, unsupported →
     `skipped`, MKV/WEBM/AVI → `skipped` w/ reason, MOV/MP4 → `cleaned`.
   - Drop multiple mixed files+folders at once → all handled; symlinks skipped.
   - Start a large batch and hit `Cancel` → run stops between files, summary marks cancelled.
   - `Clear Log` resets the view.
4. Confirm no files outside the dropped paths were modified (spot-check sibling timestamps).

## Project memory
- After completion, create `.glaze_memory/PROJECT-CONTEXT.md` (Overview + Current State +
  first Recent History entry) documenting the services, IPC channels (`clean:start`,
  `clean:cancel`, `clean:checkExiftool`, broadcasts `clean:progress`/`clean:state`), the
  exiftool argument choices, and the two confirmed tradeoff decisions.
