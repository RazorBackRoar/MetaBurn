// Main process entry point - Node.js backend for app
//
// The app CLI runtime automatically handles all framework wiring (IPC server,
// native bridge, lifecycle, signal handlers) before this file runs.
// This entry point uses only APIs.

import * as path from "path";
import { fileURLToPath } from "url";

import { app, BrowserWindow, Menu, dialog, nativeImage, nativeTheme, logger, initDevToolsButtonState, shell } from "@electron-core/backend";

import { registerHandlers } from "./handlers/index.js";
import { getPreloadPath, getWindowUrl } from "./windows/window-paths.js";
import { openSettingsWindow } from "./windows/settings-window.js";
import { DISPLAY_NAME } from "../electron-core/utils/brand.js";
import { getAppInfo, printStartupInfo } from "../electron-core/utils/appInfo.js";
import { setupLogging } from "../electron-core/utils/logging.js";
import { checkForUpdates } from "../electron-core/utils/updates.js";
import { ensureDir, appDataDir, appLogDir } from "../electron-core/utils/paths.js";

// Get directory paths
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
// Packaged Dock/Finder use Resources/icon.icns. PNG is more reliable for dock.setIcon.
const ICON_ICNS = app.isPackaged
  ? path.join(process.resourcesPath, "icon.icns")
  : path.join(__dirname, "..", "..", "app-icon.icns");
const ICON_PNG = app.isPackaged
  ? path.join(process.resourcesPath, "icon.png")
  : path.join(__dirname, "..", "..", "app-icon.png");
const WINDOW_ICON = ICON_ICNS;
const DOCK_ICON = ICON_PNG;

// ── IPC Handlers ──────────────────────────────────────────────────────
// ipcMain is already wired to the IPC server by the runtime bootstrap.
registerHandlers();

// Force dark appearance for the blue privacy theme
nativeTheme.themeSource = "dark";

// ── State ─────────────────────────────────────────────────────────────
let mainWindow: BrowserWindow | null = null;

// ── Window creation ───────────────────────────────────────────────────
async function createMainWindow() {
  if (mainWindow && !mainWindow.isDestroyed()) {
    logger.debug("main", "Main window already exists, skipping creation");
    return;
  }

  const minWindowWidth = 520;
  const minWindowHeight = 640;
  const windowWidth = 620;
  const windowHeight = 900;

  // Create main window
  const browserWindowStartTime = Date.now();
  logger.info("main", "⏱️ [COLD_START] Creating BrowserWindow", {
    timestamp: new Date().toISOString(),
  });

  mainWindow = new BrowserWindow({
    windowKey: "main", // Stable key for frame persistence
    width: windowWidth,
    height: windowHeight,
    minWidth: minWindowWidth,
    minHeight: minWindowHeight,
    title: "",
    titleBarStyle: "hidden",
    trafficLightPosition: { x: 14, y: 14 },
    backgroundColor: "#111111",
    icon: nativeImage.createFromPath(WINDOW_ICON),
    show: false, // Don't show until WebView is ready (prevents flickering)
    webPreferences: {
      preload: getPreloadPath(),
    },
  });

  const browserWindowEndTime = Date.now();
  logger.info("main", "⏱️ [COLD_START] BrowserWindow constructor completed", {
    timestamp: new Date().toISOString(),
    duration_ms: browserWindowEndTime - browserWindowStartTime,
  });

  // Wait for ready-to-show event before showing window (prevents flickering)
  mainWindow.once("ready-to-show", () => {
    const showStartTime = Date.now();
    logger.info("main", "⏱️ [COLD_START] ready-to-show event received, showing window", {
      timestamp: new Date().toISOString(),
    });

    mainWindow?.show();

    const showEndTime = Date.now();
    logger.info("main", "⏱️ [COLD_START] Window shown", {
      timestamp: new Date().toISOString(),
      duration_ms: showEndTime - showStartTime,
    });
  });

  // Determine URL to load (dev server preferred, fallback to build files)
  const url = await getWindowUrl("main-window.html");
  logger.info("main", "Resolved main window URL", { url });

  // Load URL - window will be shown automatically when ready-to-show fires
  const loadURLStartTime = Date.now();
  logger.info("main", "⏱️ [COLD_START] Loading URL in window", {
    timestamp: new Date().toISOString(),
    url,
  });

  await mainWindow.loadURL(url);

  const loadURLEndTime = Date.now();
  logger.info("main", "⏱️ [COLD_START] URL loaded in window (waiting for ready-to-show)", {
    timestamp: new Date().toISOString(),
    duration_ms: loadURLEndTime - loadURLStartTime,
  });
}

async function showAboutDialog() {
  const info = getAppInfo();
  await dialog.showMessageBox({
    type: "info",
    title: `About ${info.name}`,
    message: info.name,
    detail: [
      `Version ${info.version}`,
      info.license,
      info.organization,
      info.architecture,
      info.copyright,
    ].join("\n"),
    buttons: ["OK"],
  });
}

async function runUpdateCheck() {
  const info = getAppInfo();
  const result = await checkForUpdates(info.version);
  if (result.error) {
    await dialog.showMessageBox({
      type: "warning",
      title: `${info.name} Updates`,
      message: "Update check failed",
      detail: result.error,
      buttons: ["OK"],
    });
    return;
  }
  if (result.update_available) {
    const response = await dialog.showMessageBox({
      type: "info",
      title: `${info.name} Updates`,
      message: `Update available: ${result.latest_version}`,
      detail: `You have ${result.current_version}.${result.download_url ? `\n\n${result.download_url}` : ""}`,
      buttons: result.download_url ? ["Open Release", "OK"] : ["OK"],
      defaultId: 0,
    });
    if (result.download_url && response.response === 0) {
      await shell.openExternal(result.download_url);
    }
    return;
  }
  await dialog.showMessageBox({
    type: "info",
    title: `${info.name} Updates`,
    message: "You're up to date",
    detail: `Current version: ${result.current_version}`,
    buttons: ["OK"],
  });
}

// ── Application menu ──────────────────────────────────────────────────
async function setupApplicationMenu() {
  await initDevToolsButtonState();
  const menu = Menu.buildFromTemplate([
    {
      label: DISPLAY_NAME,
      submenu: [
        {
          label: `About ${DISPLAY_NAME}`,
          click: () => {
            void showAboutDialog();
          },
        },
        {
          label: "Check for Updates…",
          click: () => {
            void runUpdateCheck();
          },
        },
        { type: "separator" },
        {
          label: "Settings…",
          icon: "gearshape",
          accelerator: "Command+,",
          click: async () => await openSettingsWindow(),
        },
        { type: "separator" },
        { role: "services" },
        { type: "separator" },
        { role: "hide" },
        { role: "hideOthers" },
        { role: "unhide" },
        { type: "separator" },
        { role: "quit" },
      ],
    },
    { role: "fileMenu" },
    { role: "editMenu" },
    { role: "viewMenu" },
    { role: "windowMenu" },
  ]);
  Menu.setApplicationMenu(menu);
  logger.info("main", "Application menu configured with Settings");
}

// ── Lifecycle events ──────────────────────────────────────────────────
app.on("window-all-closed", () => {
  // On macOS, apps typically don't quit when all windows are closed
  // Uncomment to quit on all windows closed:
  // app.quit();
});

app.on("activate", (hasVisibleWindows) => {
  logger.info("main", "App activate event received", {
    hasVisibleWindows,
    mainWindowExists: !!mainWindow,
    mainWindowDestroyed: mainWindow?.isDestroyed() ?? true,
  });

  // On macOS, re-create window when dock icon clicked if no windows
  if (!hasVisibleWindows) {
    if (!mainWindow || mainWindow.isDestroyed()) {
      logger.info("main", "Creating main window due to activate event");
      createMainWindow();
    } else {
      logger.info("main", "Showing existing main window");
      mainWindow.show();
    }
  } else {
    logger.info("main", "Has visible windows, no action needed");
  }
});

app.on("before-quit", () => {
  logger.info("main", "App before-quit, cleaning up...");
});

// ── App ready ─────────────────────────────────────────────────────────
const startTime = Date.now();
logger.info("main", "⏱️ [COLD_START] Waiting for app ready...", {
  timestamp: new Date().toISOString(),
});

app.setName(DISPLAY_NAME);
printStartupInfo();
setupLogging();
ensureDir(appDataDir());
logger.info("main", "Data directories ready", {
  appData: appDataDir(),
  logs: appLogDir(),
});

app.whenReady().then(async () => {
  const windowCreateStartTime = Date.now();
  logger.info("main", "⏱️ [COLD_START] App ready, creating main window", {
    timestamp: new Date().toISOString(),
    wait_duration_ms: windowCreateStartTime - startTime,
  });

  await setupApplicationMenu();

  if (process.platform === "darwin" && app.dock) {
    const dockImage = nativeImage.createFromPath(DOCK_ICON);
    if (!dockImage.isEmpty()) {
      app.dock.setIcon(dockImage);
    } else {
      const fallback = nativeImage.createFromPath(WINDOW_ICON);
      if (!fallback.isEmpty()) app.dock.setIcon(fallback);
    }
  }

  createMainWindow()
    .then(() => {
      const windowCreateEndTime = Date.now();
      logger.info("main", "⏱️ [COLD_START] Main window created successfully", {
        timestamp: new Date().toISOString(),
        duration_ms: windowCreateEndTime - windowCreateStartTime,
      });
    })
    .catch((error) => {
      logger.error("main", "Failed to create main window", error);
    });
});
