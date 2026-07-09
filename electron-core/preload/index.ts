import {
    contextBridge,
    ipcRenderer as electronIpcRenderer,
    webUtils,
} from "electron";

// `ipcRenderer` wrapper that adds the custom methods the source preload uses
// and accepts a looser listener type so the preload source compiles.
export const ipcRenderer = {
  invoke: <T = any>(channel: string, ...args: any[]): Promise<T> =>
    electronIpcRenderer.invoke(channel, ...args) as Promise<T>,
  send: (channel: string, ...args: any[]) => electronIpcRenderer.send(channel, ...args),
  on: (channel: string, listener: (event: any, ...args: any[]) => void) =>
    electronIpcRenderer.on(channel, listener as any),
  once: (channel: string, listener: (event: any, ...args: any[]) => void) =>
    electronIpcRenderer.once(channel, listener as any),
  removeListener: (channel: string, listener: (event: any, ...args: any[]) => void) =>
    electronIpcRenderer.removeListener(channel, listener as any),
  onNotification: (channel: string, callback: (payload: any) => void) => {
    const listener = (_event: any, ...args: any[]) => {
      callback(args.length === 1 ? args[0] : args);
    };
    electronIpcRenderer.on(channel, listener);
    return () => electronIpcRenderer.removeListener(channel, listener);
  },
  isConnected: () => true,
  waitForReady: () => Promise.resolve(),
  disconnect: () => {},
};

export { contextBridge };

// Expose webUtils file-path helper for drag-and-drop.
export function createWebUtilsAPI() {
  return {
    getPathForFile: (file: any): string | null => {
      if (webUtils && typeof (webUtils as any).getPathForFile === "function") {
        try {
          return (webUtils as any).getPathForFile(file) as string | null;
        } catch {
          // fall back
        }
      }
      return file?.path ?? null;
    },
  };
}

// No-op in Electron; display capture is handled by the host.
export function installDisplayMediaCompat() {}
