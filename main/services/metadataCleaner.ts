/**
 * metadataCleaner — locates ExifTool and cleans a single file in place.
 *
 * Cleaning rules (confirmed with the user):
 *  - Photos: strip EXIF/GPS/XMP/IPTC/MakerNotes/device/software metadata but
 *    RESTORE the ICC color profile so colors don't shift.
 *      exiftool -all= -tagsFromFile @ -icc_profile:all -overwrite_original FILE
 *  - Videos (MOV/MP4/M4V): strip all metadata.
 *      exiftool -all= -overwrite_original FILE
 *  - Videos in containers ExifTool can't safely rewrite (MKV/WEBM/AVI): skipped.
 *  - Unsupported types: skipped.
 *
 * Safety: arguments are always passed as an array (never a shell string), so
 * paths are never interpolated or wildcard-expanded. On any error the file is
 * left unchanged and reported as failed. `-overwrite_original` prevents the
 * creation of `_original` backup files.
 */

import { execFile } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { promisify } from "util";

import { classify } from "./supportedTypes.js";

const execFileAsync = promisify(execFile);

const EXEC_OPTS = { timeout: 60_000, maxBuffer: 10 * 1024 * 1024 } as const;
const MUTE_OPTS = { timeout: 5 * 60_000, maxBuffer: 10 * 1024 * 1024 } as const;

/** Known Homebrew install locations, tried before falling back to `which`. */
const EXIFTOOL_CANDIDATES = ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool"];
const FFMPEG_CANDIDATES = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"];
const BREW_CANDIDATES = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"];

export type CleanStatus = "cleaned" | "skipped" | "failed" | "partial";

export interface MetadataEntry {
  tag: string;
  value: string;
}

export interface CleanResult {
  path: string;
  status: CleanStatus;
  reason?: string;
  /** Full metadata found on the file before any changes were made. */
  metadataBefore?: MetadataEntry[];
  /** Full metadata remaining on the file after cleaning (and muting, if requested). */
  metadataAfter?: MetadataEntry[];
}

/** Filesystem/tool-version fields that aren't embedded file metadata. */
const METADATA_BLOCKLIST = new Set([
  "SourceFile",
  "ExifToolVersion",
  "FileName",
  "Directory",
  "FileSize",
  "FileModifyDate",
  "FileAccessDate",
  "FileInodeChangeDate",
  "FilePermissions",
  "FileType",
  "FileTypeExtension",
  "MIMEType",
  "Warning",
  "Error",
]);

/** Read every metadata tag ExifTool can find on a file. Never throws. */
async function readMetadata(exiftoolPath: string, filePath: string): Promise<MetadataEntry[]> {
  try {
    const { stdout } = await execFileAsync(exiftoolPath, ["-j", filePath], EXEC_OPTS);
    const parsed = JSON.parse(stdout) as Array<Record<string, unknown>>;
    const record = parsed[0] ?? {};
    const entries: MetadataEntry[] = [];
    for (const [tag, value] of Object.entries(record)) {
      if (METADATA_BLOCKLIST.has(tag) || value === null || value === undefined) continue;
      const text = typeof value === "string" ? value : Array.isArray(value) ? value.join(", ") : String(value);
      if (text.trim().length === 0) continue;
      entries.push({ tag, value: text.trim() });
    }
    entries.sort((a, b) => a.tag.localeCompare(b.tag));
    return entries;
  } catch {
    return [];
  }
}

/**
 * Permanently remove the audio track from a video by remuxing video-only
 * streams into a temp file, then replacing the original in place. `-c copy`
 * avoids re-encoding (fast, lossless for the kept video stream); dropping the
 * audio stream entirely (not just silencing it) makes it unrecoverable.
 */
export async function muteVideo(ffmpegPath: string, filePath: string): Promise<{ success: boolean; reason?: string }> {
  const dir = path.dirname(filePath);
  const ext = path.extname(filePath);
  const base = path.basename(filePath, ext);
  const tempPath = path.join(dir, `.${base}.muted.tmp${ext}`);

  try {
    await execFileAsync(ffmpegPath, ["-y", "-i", filePath, "-map", "0:v", "-c", "copy", "-an", tempPath], MUTE_OPTS);
    await fs.promises.rename(tempPath, filePath);
    return { success: true };
  } catch (err) {
    await fs.promises.rm(tempPath, { force: true }).catch(() => {});
    const e = err as { stderr?: string; message?: string };
    const reason = e.stderr ? firstIssueLine(e.stderr) : e.message || "ffmpeg failed";
    return { success: false, reason };
  }
}

let cachedExiftoolPath: string | null | undefined;
let cachedFfmpegPath: string | null | undefined;

/** Locate the system ExifTool binary, caching the result. Returns null if absent. */
export async function resolveExiftool(): Promise<string | null> {
  if (cachedExiftoolPath !== undefined) return cachedExiftoolPath;
  cachedExiftoolPath = await resolveBinary("exiftool", EXIFTOOL_CANDIDATES);
  return cachedExiftoolPath;
}

/** Clear the cached ExifTool path (e.g. after an install). */
export function invalidateExiftoolCache(): void {
  cachedExiftoolPath = undefined;
}

/** Locate the system ffmpeg binary, caching the result. Returns null if absent. */
export async function resolveFfmpeg(): Promise<string | null> {
  if (cachedFfmpegPath !== undefined) return cachedFfmpegPath;
  cachedFfmpegPath = await resolveBinary("ffmpeg", FFMPEG_CANDIDATES);
  return cachedFfmpegPath;
}

/** Clear the cached ffmpeg path (e.g. after an install). */
export function invalidateFfmpegCache(): void {
  cachedFfmpegPath = undefined;
}

/** Locate the Homebrew binary for one-click install. Returns null if absent. */
export async function resolveBrew(): Promise<string | null> {
  return resolveBinary("brew", BREW_CANDIDATES);
}

async function resolveBinary(name: string, candidates: string[]): Promise<string | null> {
  for (const candidate of candidates) {
    try {
      await fs.promises.access(candidate, fs.constants.X_OK);
      return candidate;
    } catch {
      // try next
    }
  }
  try {
    const { stdout } = await execFileAsync("/usr/bin/which", [name], {
      timeout: 5_000,
      maxBuffer: 1024 * 1024,
    });
    const resolved = stdout.trim();
    return resolved.length > 0 ? resolved : null;
  } catch {
    return null;
  }
}

/** Build the ExifTool argument array for a given file classification. */
function buildArgs(kind: "photo" | "video", filePath: string): string[] {
  if (kind === "photo") {
    // Strip everything, then copy back the ICC color profile to preserve color.
    return ["-all=", "-tagsFromFile", "@", "-icc_profile:all", "-overwrite_original", filePath];
  }
  // Video (MOV/MP4/M4V): strip all metadata including QuickTime tags.
  return ["-all=", "-overwrite_original", filePath];
}

export interface CleanOptions {
  /** Strip the audio track from videos (unrecoverable — dropped, not just silenced). */
  muteAudio: boolean;
  /** Resolved ffmpeg path, or null if unavailable. Only needed when muteAudio is true. */
  ffmpegPath: string | null;
}

/** Clean one file in place. Never throws — always resolves to a CleanResult. */
export async function cleanFile(exiftoolPath: string, filePath: string, options: CleanOptions): Promise<CleanResult> {
  const info = classify(filePath);

  if (info.kind === "unsupported") {
    return { path: filePath, status: "skipped", reason: "unsupported file type" };
  }
  if (info.kind === "video" && !info.writable) {
    return {
      path: filePath,
      status: "skipped",
      reason: "container not safely writable by ExifTool",
    };
  }

  const metadataBefore = await readMetadata(exiftoolPath, filePath);

  let muteReason: string | undefined;
  if (options.muteAudio && info.kind === "video") {
    if (!options.ffmpegPath) {
      muteReason = "ffmpeg not installed — audio not removed";
    } else {
      const muted = await muteVideo(options.ffmpegPath, filePath);
      if (!muted.success) muteReason = `audio removal failed: ${muted.reason}`;
    }
  }

  const args = buildArgs(info.kind, filePath);
  let result: CleanResult;
  try {
    const { stdout, stderr } = await execFileAsync(exiftoolPath, args, EXEC_OPTS);
    result = interpretOutput(filePath, `${stdout}\n${stderr}`);
  } catch (err) {
    // execFile rejects on non-zero exit; exiftool leaves the file unchanged.
    const e = err as { stdout?: string; stderr?: string; message?: string };
    const combined = `${e.stdout ?? ""}\n${e.stderr ?? ""}`.trim();
    const reason = combined.length > 0 ? firstIssueLine(combined) : e.message || "exiftool failed";
    result = { path: filePath, status: "failed", reason };
  }

  const metadataAfter = await readMetadata(exiftoolPath, filePath);

  if (muteReason && result.status === "cleaned") {
    result = { ...result, status: "partial", reason: muteReason };
  }

  return { ...result, metadataBefore, metadataAfter };
}

/**
 * Decide the outcome from ExifTool's summary output.
 *
 * ExifTool prints one of:
 *   "N image files updated"                → metadata was stripped
 *   "N image files unchanged"              → nothing to remove (already clean)
 *   "N files weren't updated due to errors"→ real failure
 * A "Warning:" line (e.g. "No writable tags set") is benign, not an error.
 */
function interpretOutput(filePath: string, output: string): CleanResult {
  const updatedCount = matchCount(output, /(\d+)\s+(?:image\s+)?files?\s+updated/i);
  const unchangedCount = matchCount(output, /(\d+)\s+(?:image\s+)?files?\s+unchanged/i);
  const failedCount = matchCount(output, /(\d+)\s+files?\s+(?:weren't|were not)\s+updated/i);
  const hasError = /(^|\n)\s*error[:\s]/i.test(output);

  if (failedCount > 0 || hasError) {
    return { path: filePath, status: "failed", reason: firstIssueLine(output) || "exiftool reported an error" };
  }
  if (updatedCount >= 1) {
    return { path: filePath, status: "cleaned" };
  }
  if (unchangedCount >= 1) {
    // File had no removable metadata — its end state is clean.
    return { path: filePath, status: "cleaned", reason: "already free of removable metadata" };
  }
  return { path: filePath, status: "failed", reason: firstIssueLine(output) || "no changes applied" };
}

function matchCount(text: string, re: RegExp): number {
  const m = re.exec(text);
  return m ? parseInt(m[1], 10) : 0;
}

function firstIssueLine(text: string): string {
  const lines = text.split("\n").map((l) => l.trim()).filter(Boolean);
  // Prefer a genuine error, then a "weren't updated" note, then any warning.
  return (
    lines.find((l) => /error/i.test(l)) ||
    lines.find((l) => /weren't|were not/i.test(l)) ||
    lines.find((l) => /warning/i.test(l)) ||
    lines[0] ||
    ""
  );
}
