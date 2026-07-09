export type AskForMediaAccessType = "camera" | "microphone" | "screen" | "all";

export type MediaAccessType =
  | "camera"
  | "microphone"
  | "screen"
  | "accessibility"
  | "bluetooth"
  | "contacts"
  | "full-disk"
  | "location"
  | "microphone"
  | "music-library"
  | "photos"
  | "reminders"
  | "speech-recognition";

export type PermissionStatus =
  | "granted"
  | "denied"
  | "not-determined"
  | "restricted"
  | "unknown";

export type PermissionDiagnostic = {
  permission: string;
  status: PermissionStatus;
  message?: string;
};

export type OpenDialogOptions = {
  title?: string;
  defaultPath?: string;
  buttonLabel?: string;
  filters?: { name: string; extensions: string[] }[];
  properties?: Array<
    | "openFile"
    | "openDirectory"
    | "multiSelections"
    | "createDirectory"
    | "showHiddenFiles"
    | "treatPackageAsDirectory"
  >;
};

export type OpenDialogResult = { canceled: boolean; filePaths: string[] };

export type SaveDialogOptions = {
  title?: string;
  defaultPath?: string;
  buttonLabel?: string;
  filters?: { name: string; extensions: string[] }[];
};

export type SaveDialogResult = { canceled: boolean; filePath?: string };

export type MessageBoxOptions = {
  type?: "none" | "info" | "error" | "question" | "warning";
  buttons?: string[];
  defaultId?: number;
  cancelId?: number;
  title?: string;
  message: string;
  detail?: string;
};

export type MessageBoxResult = { response: number; checkboxChecked: boolean };

export type NativeThemeInfo = {
  themeSource: string;
  shouldUseDarkColors: boolean;
  isHighContrast: boolean;
};

export type MenuItemConstructorOptions = {
  label?: string;
  type?: "normal" | "separator" | "submenu" | "checkbox" | "radio";
  role?: string;
  icon?: string;
  enabled?: boolean;
  visible?: boolean;
  checked?: boolean;
  submenu?: MenuItemConstructorOptions[];
  click?: () => void;
};

export type PopupOptions = {
  x?: number;
  y?: number;
  positioningItem?: number;
};

export type PopupResult = { id: number };

export type DatePickerOptions = {
  type?: "date" | "time" | "dateAndTime";
  initial?: string;
  min?: string;
  max?: string;
};

export type DatePickerResult = { canceled: boolean; value?: string };

export type LocationPosition = {
  latitude: number;
  longitude: number;
  altitude?: number;
  accuracy?: number;
  speed?: number;
  course?: number;
  timestamp?: number;
};

export type LocationPositionOptions = {
  enableHighAccuracy?: boolean;
  timeout?: number;
  maximumAge?: number;
};

export type SystemPreferencesAuthorizationType =
  | "accessibility"
  | "camera"
  | "microphone"
  | "photos"
  | "screen-capture"
  | "full-disk";

export type SystemPreferencesPreferredScrollerStyle = "legacy" | "overlay";

export type SystemPreferencesNotificationPayload = {
  subscriptionId: number;
  event: string;
  userInfo?: Record<string, unknown>;
  object?: string;
};

export type SystemPreferencesNotificationCallback = (
  event: string,
  userInfo: Record<string, unknown>,
  object: string,
) => void;

export type SystemPreferencesNotificationOptions = {
  event?: string;
  object?: string;
};
