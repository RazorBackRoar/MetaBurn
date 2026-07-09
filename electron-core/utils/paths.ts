import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

import { DISPLAY_NAME } from "./brand.js";

/**
 * Prefer Electron's app paths when the app is ready; fall back to the same
 * macOS layout so modules can resolve dirs before `app.whenReady()`.
 */
function electronApp(): Electron.App | null {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { app } = require("electron") as typeof Electron;
    return app;
  } catch {
    return null;
  }
}

export function appName(): string {
  return DISPLAY_NAME;
}

export function appDataDir(): string {
  const app = electronApp();
  if (app) {
    try {
      return app.getPath("userData");
    } catch {
      // app not ready yet
    }
  }
  return path.join(os.homedir(), "Library", "Application Support", DISPLAY_NAME);
}

export function appCacheDir(): string {
  // Electron has no getPath("cache"); use macOS Caches/<AppName>.
  return path.join(os.homedir(), "Library", "Caches", DISPLAY_NAME);
}

export function appLogDir(): string {
  return path.join(appDataDir(), "logs");
}

export function ensureDir(dir: string): void {
  fs.mkdirSync(dir, { recursive: true });
}

export function ensureLogDir(): void {
  ensureDir(appLogDir());
}

export function ensureCacheDir(): void {
  ensureDir(appCacheDir());
}
