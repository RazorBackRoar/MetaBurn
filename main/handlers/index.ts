/**
 * Handler Registration
 *
 * Register all your IPC handlers here
 */

import * as path from "path";
import { fileURLToPath } from "url";

import { appHandlers } from "./app.js";
import { cleanHandlers } from "./clean.js";
import { getSettingsWindow, openSettingsWindow } from "../windows/settings-window.js";

import { ipcMain, logger } from "@electron-core/backend";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export function registerHandlers(): void {
  logger.info("handlers", "Registering IPC handlers...");

  // Register app handlers using ipcMain API
  ipcMain.handle("app:getInfo", async (_event) => {
    return await appHandlers.getInfo();
  });

  // Return the .app project path (used for deep links back to the host)
  // __dirname = build/main, so two levels up is the app root
  ipcMain.handle("app:getProjectPath", async () => {
    return path.join(__dirname, "..", "..");
  });

  // Settings window handlers
  ipcMain.handle("window:openSettings", async (_event) => {
    await openSettingsWindow();
  });

  ipcMain.handle("window:closeSettings", async (_event) => {
    getSettingsWindow()?.close();
  });

  // MetaBurn handlers
  ipcMain.handle("clean:checkExiftool", async () => {
    return await cleanHandlers.checkExiftool();
  });

  ipcMain.handle("clean:checkFfmpeg", async () => {
    return await cleanHandlers.checkFfmpeg();
  });

  ipcMain.handle("clean:start", async (_event, params) => {
    return await cleanHandlers.start(params ?? {});
  });

  ipcMain.handle("clean:cancel", async (_event, params) => {
    return await cleanHandlers.cancel(params ?? {});
  });

  ipcMain.handle("clean:installExiftool", async () => {
    return await cleanHandlers.installExiftool();
  });

  ipcMain.handle("clean:installFfmpeg", async () => {
    return await cleanHandlers.installFfmpeg();
  });

  logger.info("handlers", "✓ IPC handlers registered");

  // TODO: Add more handlers here using ipcMain.handle()
  // Example:
  // ipcMain.handle('file:read', async (event, path) => {
  //   const fs = await import('fs/promises');
  //   return await fs.readFile(path, 'utf-8');
  // });
}
