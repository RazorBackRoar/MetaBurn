/**
 * App Handlers - Application-level IPC methods
 */

import { logger } from "@electron-core/backend";

import { getAppInfo } from "../../electron-core/utils/appInfo.js";
import { checkForUpdates } from "../../electron-core/utils/updates.js";

export const appHandlers = {
  getInfo: async () => {
    logger.info("app", "App info requested");
    return getAppInfo();
  },

  checkForUpdates: async () => {
    const info = getAppInfo();
    logger.info("app", "Update check requested", { version: info.version });
    return checkForUpdates(info.version);
  },
};
