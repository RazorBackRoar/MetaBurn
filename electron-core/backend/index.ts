import * as fs from "node:fs";
import { createRequire } from "node:module";
import * as path from "node:path";

import { getLogger } from "../utils/logging.js";

const require = createRequire(import.meta.url);
const electron: typeof Electron = require("electron");

const electronApp = electron.app;

const coreLogger = getLogger("app");

// Logger shim matching custom structured logging API.
export const logger = {
  info: (scope: string, message: string, data?: Record<string, unknown>) => {
    coreLogger.info(`[${scope}] ${message}`, data);
  },
  debug: (scope: string, message: string, data?: Record<string, unknown>) => {
    coreLogger.debug(`[${scope}] ${message}`, data);
  },
  error: (scope: string, message: string, data?: unknown) => {
    coreLogger.error(`[${scope}] ${message}`, data);
  },
};

export const initDevToolsButtonState = async () => {
  // No-op in standalone Electron.
};

// Adapt the Electron `app` so the custom-style `app.on("activate", (hasVisibleWindows) => ...)`)
// signature works. All other properties/methods are forwarded to the real app object.
export const app = new Proxy(electronApp, {
  get(target, prop) {
    if (prop === "on") {
      return (event: string, listener: (...args: unknown[]) => void) => {
        if (event === "activate") {
          return electronApp.on(
            "activate",
            (_event: Electron.Event, hasVisibleWindows: boolean) => listener(hasVisibleWindows),
          );
        }
        return electronApp.on(event as any, listener as any);
      };
    }
    if (prop === "once") {
      return (event: string, listener: (...args: unknown[]) => void) => {
        if (event === "activate") {
          return electronApp.once(
            "activate",
            (_event: Electron.Event, hasVisibleWindows: boolean) => listener(hasVisibleWindows),
          );
        }
        return electronApp.once(event as any, listener as any);
      };
    }
    const value = Reflect.get(target, prop);
    if (typeof value === "function") {
      return value.bind(target);
    }
    return value;
  },
}) as Electron.App;
// BrowserWindow wrapper that strips custom `windowKey` and ensures the
// preload path is an absolute file URL/path Electron understands.
const ElectronBrowserWindow = electron.BrowserWindow;

interface BrowserWindowStatic {
  new (options: any): BrowserWindow;
  getAllWindows(): BrowserWindow[];
  getFocusedWindow(): BrowserWindow | null;
  fromId(id: number): BrowserWindow;
  fromWebContents(webContents: Electron.WebContents): BrowserWindow | null;
  fromBrowserView(browserView: Electron.BrowserView): BrowserWindow | null;
  [key: string]: any;
}

export type BrowserWindow = Electron.BrowserWindow;

export const BrowserWindow: BrowserWindowStatic = Object.assign(
  function BrowserWindow(this: any, options: any): BrowserWindow {
    const safeOptions = { ...options };
    delete safeOptions.windowKey;

    if (safeOptions.webPreferences?.preload) {
      const preloadPath = safeOptions.webPreferences.preload;
      if (typeof preloadPath === "string" && !path.isAbsolute(preloadPath)) {
        safeOptions.webPreferences.preload = path.resolve(preloadPath);
      }
    }

    return new ElectronBrowserWindow(safeOptions);
  },
  electron.BrowserWindow as any,
);

if (ElectronBrowserWindow) { BrowserWindow.prototype = ElectronBrowserWindow.prototype; }

function cleanMenuTemplate(
  template: Electron.MenuItemConstructorOptions[],
): Electron.MenuItemConstructorOptions[] {
  return template.map((item) => {
    const copy = { ...item };
    if (typeof copy.icon === "string") {
      delete copy.icon;
    }
    if (copy.submenu) {
      copy.submenu = cleanMenuTemplate(copy.submenu as Electron.MenuItemConstructorOptions[]);
    }
    return copy;
  });
}

const ElectronMenu = electron.Menu;

export const Menu = Object.assign({}, ElectronMenu, {
  buildFromTemplate: (template: Electron.MenuItemConstructorOptions[]) => {
    return ElectronMenu.buildFromTemplate(cleanMenuTemplate(template));
  },
});

export const nativeTheme = electron.nativeTheme;
export const dialog = electron.dialog;
export const shell = electron.shell;
export const Notification = electron.Notification;
export const nativeImage = electron.nativeImage;

// Extend `ipcMain` with custom `broadcast` helper used by backend job services.
export const ipcMain = Object.assign(electron.ipcMain, {
  broadcast: (channel: string, ...args: unknown[]) => {
    for (const win of BrowserWindow.getAllWindows()) {
      if (!win.isDestroyed()) {
        win.webContents.send(channel, ...args);
      }
    }
  },
});

// Protocol helper used by the thumbnail service.
// custom `createFileResponse` returns an object; Electron's `protocol.handle`
// expects a standard `Response`.
let protocolReady = false;
const protocolQueue: Array<{ scheme: string; handler: (request: Request) => any }> = [];

function registerProtocolQueue() {
  if (protocolReady) return;
  protocolReady = true;
  for (const { scheme, handler } of protocolQueue) {
    electron.protocol.handle(scheme, async (request: Request) => {
      const result = await handler(request);
      if (result instanceof Response) {
        return result;
      }
      if (result && typeof result === "object" && "data" in result) {
        const { data, statusCode, headers } = result as {
          data: any;
          statusCode: number;
          headers: Record<string, string>;
        };
        return new Response(data, { status: statusCode, headers });
      }
      return result;
    });
  }
}

export const protocol = {
  registerSchemesAsPrivileged: (
    schemes: Array<{
      scheme: string;
      privileges?: Record<string, boolean>;
    }>,
  ) => {
    const safeSchemes = schemes.map((s) => ({
      scheme: s.scheme,
      privileges: s.privileges,
    }));
    return electron.protocol.registerSchemesAsPrivileged(safeSchemes as any);
  },
  handle: (scheme: string, handler: (request: Request) => any) => {
    protocolQueue.push({ scheme, handler });
    if (app.isReady()) {
      registerProtocolQueue();
    } else {
      electronApp.whenReady().then(registerProtocolQueue);
    }
  },
  createFileResponse: (
    relativePath: string,
    {
      root,
      headers,
      statusCode,
    }: { root: string; headers?: Record<string, string>; statusCode?: number },
  ) => {
    const filePath = path.join(root, relativePath);
    const data = fs.readFileSync(filePath);
    return new Response(data, {
      status: statusCode ?? 200,
      headers: headers ?? { "Content-Type": "image/jpeg" },
    });
  },
};

// Register standard IPC handlers so the preload `window.electronAPI` methods can work.
// These are registered on module import so they are ready when main/index.ts calls registerHandlers().
electron.ipcMain.handle("dialog:showOpenDialog", async (_event: Electron.IpcMainInvokeEvent, options: Electron.OpenDialogOptions) => {
  const focused = BrowserWindow.getFocusedWindow() ?? BrowserWindow.getAllWindows()[0];
  return electron.dialog.showOpenDialog(focused as any, options);
});

electron.ipcMain.handle("dialog:showSaveDialog", async (_event: Electron.IpcMainInvokeEvent, options: Electron.SaveDialogOptions) => {
  const focused = BrowserWindow.getFocusedWindow() ?? BrowserWindow.getAllWindows()[0];
  return electron.dialog.showSaveDialog(focused as any, options);
});

electron.ipcMain.handle("dialog:showMessageBox", async (_event: Electron.IpcMainInvokeEvent, options: Electron.MessageBoxOptions) => {
  const focused = BrowserWindow.getFocusedWindow() ?? BrowserWindow.getAllWindows()[0];
  return electron.dialog.showMessageBox(focused as any, options);
});

electron.ipcMain.handle("dialog:showErrorBox", async (_event: Electron.IpcMainInvokeEvent, title: string, content: string) => {
  electron.dialog.showErrorBox(title, content);
});

electron.ipcMain.handle("shell:beep", () => {
  electron.shell.beep();
});

electron.ipcMain.handle("shell:showItemInFolder", (_event: Electron.IpcMainInvokeEvent, fullPath: string) => {
  electron.shell.showItemInFolder(fullPath);
});

electron.ipcMain.handle("nativeTheme:getInfo", () => ({
  themeSource: electron.nativeTheme.themeSource,
  shouldUseDarkColors: electron.nativeTheme.shouldUseDarkColors,
  isHighContrast: false,
}));

electron.ipcMain.handle("nativeTheme:setThemeSource", (_event: Electron.IpcMainInvokeEvent, source: string) => {
  electron.nativeTheme.themeSource = source as any;
  return true;
});

electron.ipcMain.handle("nativeTheme:getShouldUseDarkColors", () => electron.nativeTheme.shouldUseDarkColors);

electron.ipcMain.handle("nativeTheme:getThemeSource", () => electron.nativeTheme.themeSource);
