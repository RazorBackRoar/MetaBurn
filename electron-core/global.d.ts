declare const __APP_DISPLAY_NAME__: string | undefined;

type ElectronIpc = {
  invoke: <T = any>(channel: string, ...args: any[]) => Promise<T>;
  send: (channel: string, ...args: any[]) => void;
  on: (channel: string, callback: (payload: any) => void) => () => void;
  once: (channel: string, callback: (payload: any) => void) => () => void;
  onNotification: (channel: string, callback: (payload: any) => void) => () => void;
  isConnected: () => boolean;
  waitForReady: () => Promise<void>;
  disconnect: () => void;
};

type ElectronDialog = {
  showOpenDialog: (options?: any) => Promise<{ canceled: boolean; filePaths: string[] }>;
  showSaveDialog: (options?: any) => Promise<{ canceled: boolean; filePath?: string }>;
  showMessageBox: (options: any) => Promise<{ response: number; checkboxChecked: boolean }>;
  showErrorBox: (title: string, content: string) => Promise<void>;
  showDatePicker: (options?: any) => Promise<{ canceled: boolean; value?: string }>;
};

type ElectronShell = {
  beep: () => void;
  showItemInFolder: (fullPath: string) => void;
  openPath?: (path: string) => Promise<string>;
  openExternal?: (url: string) => Promise<void>;
};

type ElectronWebUtils = {
  getPathForFile: (file: File) => string | null;
};

type ElectronNativeTheme = {
  getInfo: () => Promise<any>;
  setThemeSource: (source: string) => Promise<boolean>;
  getShouldUseDarkColors: () => Promise<boolean>;
  getThemeSource: () => Promise<string>;
};

type ElectronSystemPreferences = {
  getMediaAccessStatus: (mediaType: string) => Promise<any>;
  askForMediaAccess: (mediaType: string) => Promise<boolean>;
  requestScreenCaptureAccess: () => Promise<boolean>;
  getAuthorizationStatus: (type: string) => Promise<any>;
  getPreferredScrollerStyle: () => Promise<any>;
  subscribeLocalNotification: (event: string | null, callback: any) => Promise<number>;
  unsubscribeLocalNotification: (id: number) => Promise<void>;
};

type ElectronPermissions = {
  getDiagnostics: () => Promise<any[]>;
};

type ElectronMenu = {
  popup: (options?: any) => Promise<any>;
  setApplicationMenu: (template: any[] | null) => Promise<void>;
};

type ElectronLocation = {
  getCurrentPosition: (options?: any) => Promise<any>;
};

type ElectronAPI = {
  dialog: ElectronDialog;
  shell: ElectronShell;
  webUtils: ElectronWebUtils;
  nativeTheme: ElectronNativeTheme;
  systemPreferences: ElectronSystemPreferences;
  permissions: ElectronPermissions;
  Menu: ElectronMenu;
  location: ElectronLocation;
  app: {
    ipc: ElectronIpc;
  };
};

declare global {
  interface Window {
    electronAPI: ElectronAPI;
  }
}

export { };
