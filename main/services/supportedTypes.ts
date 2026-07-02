/**
 * supportedTypes — supported photo/video extensions and per-file classification.
 *
 * Extension matching is case-insensitive. Some video containers (Matroska/WEBM
 * and AVI) cannot be safely rewritten by ExifTool, so they are marked as not
 * writable and are skipped rather than risking corruption.
 */

import * as path from "path";

export const PHOTO_EXTS = new Set([".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp", ".tiff"]);
export const VIDEO_EXTS = new Set([".mov", ".mp4", ".m4v", ".avi", ".mkv", ".webm"]);

/** Video containers ExifTool cannot safely rewrite in place. */
const NON_WRITABLE_VIDEO_EXTS = new Set([".mkv", ".webm", ".avi"]);

export type FileKind = "photo" | "video" | "unsupported";

export interface FileClassification {
  ext: string;
  kind: FileKind;
  /** True when ExifTool can safely clean this file type in place. */
  writable: boolean;
}

/** Classify a file path by its extension (case-insensitive). */
export function classify(filePath: string): FileClassification {
  const ext = path.extname(filePath).toLowerCase();

  if (PHOTO_EXTS.has(ext)) {
    return { ext, kind: "photo", writable: true };
  }

  if (VIDEO_EXTS.has(ext)) {
    return { ext, kind: "video", writable: !NON_WRITABLE_VIDEO_EXTS.has(ext) };
  }

  return { ext, kind: "unsupported", writable: false };
}

/** Whether a path is a supported photo or video (regardless of writability). */
export function isSupported(filePath: string): boolean {
  return classify(filePath).kind !== "unsupported";
}
