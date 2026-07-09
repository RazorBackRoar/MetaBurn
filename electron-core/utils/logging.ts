import * as fs from "node:fs";
import * as path from "node:path";

import { DISPLAY_NAME } from "./brand.js";
import { appLogDir, ensureLogDir } from "./paths.js";

export type LogLevel = "debug" | "info" | "warn" | "error";

let fileLoggingReady = false;

function logFilePath(): string {
  return path.join(appLogDir(), "metaburn.log");
}

/** Create the log directory and enable file appends. Safe to call more than once. */
export function setupLogging(): void {
  ensureLogDir();
  fileLoggingReady = true;
}

/** Kept for renderer bootstrap compatibility (no-op / ensure setup). */
export function initLogging(): void {
  // Renderer has no electron file access; console only.
}

function writeLine(level: LogLevel, message: string): void {
  const timestamp = new Date().toISOString();
  const line = `[${timestamp}] [${level.toUpperCase()}] ${message}`;
  const consoleFn =
    level === "error" ? console.error : level === "warn" ? console.warn : level === "debug" ? console.debug : console.log;
  consoleFn(line);

  if (!fileLoggingReady) return;
  try {
    ensureLogDir();
    fs.appendFileSync(logFilePath(), `${line}\n`, "utf8");
  } catch (err) {
    console.error(`[${DISPLAY_NAME}] Failed to write log:`, err);
  }
}

export function log(level: LogLevel, message: string): void {
  writeLine(level, message);
}

export function getLogger(scope: string) {
  return {
    debug: (msg: string, data?: unknown) =>
      writeLine("debug", `[${scope}] ${msg}${data !== undefined ? ` ${stringify(data)}` : ""}`),
    info: (msg: string, data?: unknown) =>
      writeLine("info", `[${scope}] ${msg}${data !== undefined ? ` ${stringify(data)}` : ""}`),
    warn: (msg: string, data?: unknown) =>
      writeLine("warn", `[${scope}] ${msg}${data !== undefined ? ` ${stringify(data)}` : ""}`),
    error: (msg: string, data?: unknown) =>
      writeLine("error", `[${scope}] ${msg}${data !== undefined ? ` ${stringify(data)}` : ""}`),
  };
}

function stringify(data: unknown): string {
  if (typeof data === "string") return data;
  try {
    return JSON.stringify(data);
  } catch {
    return String(data);
  }
}
