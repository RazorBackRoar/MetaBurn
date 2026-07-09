import * as fs from "node:fs";
import * as path from "node:path";

import {
  ARCHITECTURE,
  COPYRIGHT_FULL,
  DISPLAY_NAME,
  LICENSE_TEXT,
  ORGANIZATION,
} from "./brand.js";

export interface AppInfo {
  name: string;
  version: string;
  license: string;
  copyright: string;
  organization: string;
  architecture: string;
}

function readPackageVersion(startDir: string): string | null {
  let dir = startDir;
  for (let i = 0; i < 6; i++) {
    const candidate = path.join(dir, "package.json");
    try {
      if (fs.existsSync(candidate)) {
        const pkg = JSON.parse(fs.readFileSync(candidate, "utf8")) as {
          version?: string;
          productName?: string;
        };
        if (pkg.version && (pkg.productName === DISPLAY_NAME || pkg.version !== "0.0.0")) {
          return pkg.version;
        }
        if (pkg.version) return pkg.version;
      }
    } catch {
      // continue walking up
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

function resolveVersion(): string {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { app } = require("electron") as typeof Electron;
    const fromDisk =
      readPackageVersion(app.getAppPath()) ??
      readPackageVersion(process.cwd());
    if (fromDisk) return fromDisk;
    const v = app.getVersion();
    if (v) return v;
  } catch {
    // not in electron
  }
  return readPackageVersion(process.cwd()) ?? "0.0.0";
}

export function getAppInfo(): AppInfo {
  return {
    name: DISPLAY_NAME,
    version: resolveVersion(),
    license: LICENSE_TEXT,
    copyright: COPYRIGHT_FULL,
    organization: ORGANIZATION,
    architecture: ARCHITECTURE,
  };
}

/** Print the standardized startup banner to stdout (mirrors Python razorcore). */
export function printStartupInfo(): void {
  const info = getAppInfo();
  console.log(`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ${info.name}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Version:  ${info.version}
  License:  ${info.license}
  Arch:     ${info.architecture}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
`);
}
