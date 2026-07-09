/**
 * App Preload Script
 *
 * This script runs BEFORE the main renderer code and sets up the secure bridge
 * between the renderer and the native/backend processes.
 *
 * SECURITY MODEL:
 * - This is the ONLY file that should import from '@electron-core/preload'
 * - Renderer code should ONLY access window.electronAPI
 * - Never expose ipcRenderer directly - only expose specific, controlled APIs
 *
 * BUILD & RUNTIME CONSTRAINTS:
 * The preload is built as a self-contained IIFE (not an ES module) because
 * WKWebView injects it via WKUserScript, which only supports classic scripts.
 * This is handled transparently by the build system — write normal imports here
 * and esbuild bundles everything into one file. Constraints to be aware of:
 * - No dynamic import() — all dependencies are resolved at build time
 * - No top-level await — wrap async code in an async function
 * - No Node.js APIs (fs, path, etc.) — WKWebView is a browser environment
 * - Keep this file thin — everything is inlined, so large deps increase injection time
 * - WKContentWorld provides separate JavaScript environments with their own
 *   globals and prototypes, so the preload world stays isolated from page code
 *
 * SECURE DEFAULTS:
 * By default, only SAFE APIs are exposed:
 * - dialog.* - Requires explicit user interaction with native UI
 * - shell.beep - Just plays a system sound (harmless)
 * - app.ipc - For your custom handlers (you control what's exposed)
 *
 * SENSITIVE APIs (NOT exposed by default):
 * - clipboard.* - Data theft risk via XSS
 * - shell.openExternal - Phishing/malware download risk
 * - shell.openPath - Arbitrary file execution risk
 * - file.read - Arbitrary file reading risk
 * - screen.* - Fingerprinting concern
 *
 * To add sensitive APIs for YOUR app, uncomment them below.
 * Only expose what your app actually needs!
 */

import { contextBridge, createWebUtilsAPI, installDisplayMediaCompat, ipcRenderer } from "@electron-core/preload";


// Type imports only (safe - doesn't affect runtime)
import type {
    AskForMediaAccessType,
    DatePickerOptions,
    DatePickerResult,
    LocationPosition,
    LocationPositionOptions,
    MediaAccessType,
    MenuItemConstructorOptions,
    MessageBoxOptions,
    MessageBoxResult,
    NativeThemeInfo,
    OpenDialogOptions,
    OpenDialogResult,
    PermissionDiagnostic,
    PermissionStatus,
    PopupOptions,
    PopupResult,
    SaveDialogOptions,
    SaveDialogResult,
    SystemPreferencesAuthorizationType,
    SystemPreferencesNotificationCallback,
    SystemPreferencesNotificationPayload,
    SystemPreferencesPreferredScrollerStyle,
} from "@electron-core/ipc";

// Re-export types for use in renderer code
export type {
    AskForMediaAccessType,
    LocationPosition,
    LocationPositionOptions,
    MediaAccessType, MenuItemConstructorOptions, MessageBoxOptions,
    MessageBoxResult,
    NativeThemeInfo, OpenDialogOptions,
    OpenDialogResult,
    PermissionDiagnostic,
    PermissionStatus, PopupOptions,
    PopupResult, SaveDialogOptions,
    SaveDialogResult, SystemPreferencesAuthorizationType
};

// parameters without importing the restricted @electron-core/preload entrypoint directly.

const webUtils = createWebUtilsAPI();
const systemPreferencesNotificationCallbacks = new Map<number, SystemPreferencesNotificationCallback>();
let systemPreferencesNotificationUnsubscribe: (() => void) | null = null;

function ensureSystemPreferencesNotificationListener(): void {
  if (systemPreferencesNotificationUnsubscribe) {
    return;
  }

  systemPreferencesNotificationUnsubscribe = ipcRenderer.onNotification(
    "systemPreferences:notification",
    (params: unknown) => {
      const payload = params as SystemPreferencesNotificationPayload;
      const callback = systemPreferencesNotificationCallbacks.get(payload.subscriptionId);
      if (!callback) {
        return;
      }

      try {
        callback(payload.event, payload.userInfo ?? {}, payload.object ?? "");
      } catch {
        // Ignore renderer callback errors at the bridge boundary.
      }
    },
  );
}

const PAGE_WORLD_FUNCTION_SOURCE = Symbol.for("app.pageWorldFunctionSource");

function annotatePageWorldFunction<T extends (...args: never[]) => unknown>(fn: T, source: string): T {
  const pageWorldFunction = fn as T & Record<symbol, unknown>;
  if (pageWorldFunction[PAGE_WORLD_FUNCTION_SOURCE] !== source) {
    Object.defineProperty(pageWorldFunction, PAGE_WORLD_FUNCTION_SOURCE, {
      value: source,
      writable: false,
      configurable: false,
      enumerable: false,
    });
  }

  return fn;
}

const pageWorldShellBeepSource = `function() {
  void window.electronAPI.app.ipc.invoke("shell:beep").catch(() => {});
  return undefined;
}`;

type ElectronIpcEvent = {
  channel?: string;
  ports: MessagePort[];
};

type ElectronIpcListener = (event: ElectronIpcEvent, ...args: unknown[]) => void;

function toElectronIpcEvent(event: { channel?: string }): ElectronIpcEvent {
  return {
    channel: event.channel,
    ports: [],
  };
}

function addElectronIpcListener(channel: string, callback: ElectronIpcListener, once: boolean): () => void {
  const listener = (event: { channel?: string }, ...args: unknown[]) => {
    callback(toElectronIpcEvent(event), ...args);
  };

  if (once) {
    ipcRenderer.once(channel, listener);
  } else {
    ipcRenderer.on(channel, listener);
  }

  return () => {
    ipcRenderer.removeListener(channel, listener);
  };
}

/**
 * ElectronAPI - The secure API exposed to renderer code
 *
 * All IPC communication MUST go through this API.
 * Renderer code should NEVER import ipcRenderer directly.
 *
 * MINIMAL SECURE DEFAULTS - only safe APIs are exposed.
 * See comments above for how to add sensitive APIs if needed.
 */
const appAPI = {
  // -------------------------------------------------------------------------
  // Dialog APIs - SAFE: Requires explicit user interaction with native UI
  // -------------------------------------------------------------------------
  dialog: {
    showOpenDialog: (options?: OpenDialogOptions): Promise<OpenDialogResult> =>
      ipcRenderer.invoke("dialog:showOpenDialog", options),

    showSaveDialog: (options?: SaveDialogOptions): Promise<SaveDialogResult> =>
      ipcRenderer.invoke("dialog:showSaveDialog", options),

    showMessageBox: (options: MessageBoxOptions): Promise<MessageBoxResult> =>
      ipcRenderer.invoke("dialog:showMessageBox", options),

    showErrorBox: (title: string, content: string): Promise<void> =>
      ipcRenderer.invoke("dialog:showErrorBox", title, content),

    showDatePicker: (options: DatePickerOptions): Promise<DatePickerResult> =>
      ipcRenderer.invoke("dialog:showDatePicker", options),
  },

  // -------------------------------------------------------------------------
  // Shell APIs - Only SAFE methods exposed by default
  // -------------------------------------------------------------------------
  shell: {
    // SAFE: Just plays a system sound
    beep: annotatePageWorldFunction(function beep(): void {
      void ipcRenderer.invoke("shell:beep").catch(() => {});
    }, pageWorldShellBeepSource),

    /** @deprecated Use beep() for fire-and-forget behavior. */
    beepAsync: (): Promise<void> => ipcRenderer.invoke("shell:beep"),

    // ⚠️ SENSITIVE - Uncomment ONLY if your app needs these:
    //
    // openPath: (path: string): Promise<string> =>
    //   ipcRenderer.invoke("shell:openPath", path),
    //
    // openExternal: async (
    //   url: string,
    //   options?: { activate?: boolean; workingDirectory?: string; logUsage?: boolean },
    // ): Promise<void> => {
    //   const didOpen = await ipcRenderer.invoke("shell:openExternalWithResult", url, options);
    //   if (!didOpen) {
    //     throw new Error("Failed to open URL");
    //   }
    // },
    //
    // /** @deprecated Use openExternal() for Electron-compatible Promise<void> behavior. */
    // openExternalWithResult: (
    //   url: string,
    //   options?: { activate?: boolean; workingDirectory?: string; logUsage?: boolean },
    // ): Promise<boolean> =>
    //   ipcRenderer.invoke("shell:openExternalWithResult", url, options),
    //
    // showItemInFolder(fullPath: string): void {
    //   void ipcRenderer.invoke("shell:showItemInFolder", fullPath).catch(() => {});
    // },
    //
    // /** @deprecated Use showItemInFolder() for fire-and-forget behavior. */
    // showItemInFolderAsync: (fullPath: string): Promise<void> =>
    //   ipcRenderer.invoke("shell:showItemInFolder", fullPath),
    //
    // trashItem: (path: string): Promise<void> =>
    //   ipcRenderer.invoke("shell:trashItem", path),
  },

  // -------------------------------------------------------------------------
  // WebUtils APIs - webUtils module
  // -------------------------------------------------------------------------
  webUtils,

  // -------------------------------------------------------------------------
  // Clipboard APIs - ⚠️ SENSITIVE: Not exposed by default
  // Uncomment ONLY if your app needs clipboard access
  // Also add createClipboardAPI to the @electron-core/preload import above.
  // -------------------------------------------------------------------------
  // clipboard: createClipboardAPI(ipcRenderer.invoke.bind(ipcRenderer)),

  // -------------------------------------------------------------------------
  // Native Theme APIs - For theme detection and switching
  // -------------------------------------------------------------------------
  nativeTheme: {
    getInfo: (): Promise<NativeThemeInfo> => ipcRenderer.invoke("nativeTheme:getInfo"),

    setThemeSource: (source: "system" | "light" | "dark"): Promise<boolean> =>
      ipcRenderer.invoke("nativeTheme:setThemeSource", source),

    getShouldUseDarkColors: (): Promise<boolean> => ipcRenderer.invoke("nativeTheme:getShouldUseDarkColors"),

    getThemeSource: (): Promise<"system" | "light" | "dark"> => ipcRenderer.invoke("nativeTheme:getThemeSource"),
  },

  // -------------------------------------------------------------------------
  // Minimal permissions APIs used by the template examples
  // -------------------------------------------------------------------------
  systemPreferences: {
    getMediaAccessStatus: (mediaType: MediaAccessType): Promise<PermissionStatus> =>
      ipcRenderer.invoke("systemPreferences:getMediaAccessStatus", mediaType),

    askForMediaAccess: (mediaType: AskForMediaAccessType): Promise<boolean> =>
      ipcRenderer.invoke("systemPreferences:askForMediaAccess", mediaType),

    requestScreenCaptureAccess: (): Promise<boolean> =>
      ipcRenderer.invoke("systemPreferences:requestScreenCaptureAccess"),

    getAuthorizationStatus: (type: SystemPreferencesAuthorizationType): Promise<PermissionStatus> =>
      ipcRenderer.invoke("systemPreferences:getAuthorizationStatus", type),

    getPreferredScrollerStyle: (): Promise<SystemPreferencesPreferredScrollerStyle> =>
      ipcRenderer.invoke("systemPreferences:getPreferredScrollerStyle"),

    subscribeLocalNotification: async (
      event: string | null,
      callback: SystemPreferencesNotificationCallback,
    ): Promise<number> => {
      ensureSystemPreferencesNotificationListener();
      const subscriptionId = (await ipcRenderer.invoke(
        "systemPreferences:subscribeLocalNotification",
        event,
      )) as number;
      systemPreferencesNotificationCallbacks.set(subscriptionId, callback);
      return subscriptionId;
    },

    unsubscribeLocalNotification: async (id: number): Promise<void> => {
      await ipcRenderer.invoke("systemPreferences:unsubscribeLocalNotification", id);
      systemPreferencesNotificationCallbacks.delete(id);
    },
  },

  location: {
    getCurrentPosition: (options?: LocationPositionOptions): Promise<LocationPosition> =>
      ipcRenderer.invoke("location:getCurrentPosition", options),
  },

  permissions: {
    getDiagnostics: (): Promise<PermissionDiagnostic[]> => ipcRenderer.invoke("electron:permissions:getDiagnostics"),
  },

  // -------------------------------------------------------------------------
  // Menu APIs - For native dropdown/context menus
  // -------------------------------------------------------------------------
  Menu: {
    popup: (options: PopupOptions): Promise<PopupResult> => ipcRenderer.invoke("Menu:popup", options),

    setApplicationMenu: (template: MenuItemConstructorOptions[] | null): Promise<void> =>
      ipcRenderer.invoke("Menu:setApplicationMenu", template),
  },

  // -------------------------------------------------------------------------
  // Electron IPC - SAFE: For your custom backend handlers
  // You control what handlers exist, so you control what's exposed
  // -------------------------------------------------------------------------
  app: {
    ipc: {
      /**
       * Invoke a backend handler and wait for the result
       * Use for custom handlers registered with ipcMain.handle()
       */
      invoke: <T = unknown>(channel: string, ...args: unknown[]): Promise<T> => ipcRenderer.invoke(channel, ...args),

      /**
       * Send a fire-and-forget message to a backend listener registered with ipcMain.on().
       */
      send: (channel: string, ...args: unknown[]): void => ipcRenderer.send(channel, ...args),

      on: (channel: string, callback: ElectronIpcListener): (() => void) => addElectronIpcListener(channel, callback, false),

      once: (channel: string, callback: ElectronIpcListener): (() => void) => addElectronIpcListener(channel, callback, true),

      /**
       * Subscribe to notifications from the backend
       * Returns an unsubscribe function
       */
      onNotification: (channel: string, callback: (params: unknown) => void): (() => void) =>
        ipcRenderer.onNotification(channel, callback),

      /**
       * Check if connected to the backend
       */
      isConnected: (): boolean => ipcRenderer.isConnected(),

      /**
       * Wait for the IPC connection to be ready.
       * The connection is automatically established on first IPC call, but
       * you can use this to explicitly wait if needed (e.g., to show a loading state).
       */
      waitForReady: (): Promise<void> => ipcRenderer.waitForReady(),

      /**
       * Disconnect from the backend
       */
      disconnect: (): void => ipcRenderer.disconnect(),
    },
  },

};

const preloadURL = new URL(window.location.href);

function exposeAppAPI(): void {
  contextBridge.exposeInMainWorld("electronAPI", appAPI);
}

// `process.env.DEV_HARNESS` is a build-time define (build-renderer replaces it
// with "1"/"0"), not a runtime browser global — hence the no-undef disable.
// eslint-disable-next-line no-undef
if (process.env.DEV_HARNESS === "1" && preloadURL.searchParams.get("parityDefaultPendingStub") === "1") {
  window.setTimeout(exposeAppAPI, 200);
} else {
  exposeAppAPI();
}

// Routes navigator.mediaDevices.getDisplayMedia through the app's
// session.setDisplayMediaRequestHandler (falls back to the built-in WebKit
// behavior when no handler is registered). Runs after the electronAPI exposure
// above so the bridge bootstrap is fully initialized.
installDisplayMediaCompat();

// Export type for TypeScript
export type ElectronAPI = typeof appAPI;
