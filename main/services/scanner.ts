/**
 * scanner — builds an explicit, path-bounded file list from ONLY the dropped paths.
 *
 * Safety guarantees:
 *  - Never infers parent folders or processes siblings of a dropped file.
 *  - Only recurses into a directory that was itself dropped (or nested under one).
 *  - Never follows symlinks (uses lstat + skip), so nothing outside a dropped
 *    folder tree is ever touched.
 *  - Directly-dropped files are always included (support is decided later by the
 *    cleaner); directory contents are filtered to supported types.
 */

import * as fs from "fs";
import * as path from "path";

import { isSupported } from "./supportedTypes.js";

export interface ScanResult {
  /** Absolute file paths to consider for cleaning, de-duplicated. */
  files: string[];
  /** Paths skipped during scanning with a human-readable reason. */
  skipped: Array<{ path: string; reason: string }>;
}

/**
 * Recursively collect supported regular files under a dropped directory.
 * Symlinks (files or dirs) are skipped so traversal never escapes the tree.
 */
async function walkDir(dir: string, out: string[], skipped: ScanResult["skipped"]): Promise<void> {
  let entries: fs.Dirent[];
  try {
    entries = await fs.promises.readdir(dir, { withFileTypes: true });
  } catch (err) {
    skipped.push({ path: dir, reason: `could not read directory: ${errMsg(err)}` });
    return;
  }

  for (const entry of entries) {
    const full = path.join(dir, entry.name);

    // lstat so we detect symlinks without following them.
    let stat: fs.Stats;
    try {
      stat = await fs.promises.lstat(full);
    } catch (err) {
      skipped.push({ path: full, reason: `could not stat: ${errMsg(err)}` });
      continue;
    }

    if (stat.isSymbolicLink()) {
      skipped.push({ path: full, reason: "symlink skipped for safety" });
      continue;
    }

    if (stat.isDirectory()) {
      await walkDir(full, out, skipped);
    } else if (stat.isFile()) {
      if (isSupported(full)) {
        out.push(full);
      }
      // Unsupported files inside folders are silently ignored (not logged as
      // skips) to keep the log focused on what the user explicitly dropped.
    }
  }
}

/**
 * Build the explicit file list from exactly the dropped paths.
 */
export async function buildFileList(droppedPaths: string[]): Promise<ScanResult> {
  const files: string[] = [];
  const skipped: ScanResult["skipped"] = [];

  for (const dropped of droppedPaths) {
    if (!dropped || typeof dropped !== "string") continue;

    let stat: fs.Stats;
    try {
      stat = await fs.promises.lstat(dropped);
    } catch (err) {
      skipped.push({ path: dropped, reason: `could not stat: ${errMsg(err)}` });
      continue;
    }

    if (stat.isSymbolicLink()) {
      skipped.push({ path: dropped, reason: "symlink skipped for safety" });
      continue;
    }

    if (stat.isDirectory()) {
      await walkDir(dropped, files, skipped);
    } else if (stat.isFile()) {
      // A directly dropped file is always included; the cleaner decides support.
      files.push(dropped);
    } else {
      skipped.push({ path: dropped, reason: "not a regular file or folder" });
    }
  }

  return { files: dedupe(files), skipped };
}

function dedupe(paths: string[]): string[] {
  return Array.from(new Set(paths));
}

function errMsg(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}
