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
import { promisify } from "util";

import { classify } from "./supportedTypes.js";

const execFileAsync = promisify(execFile);

const EXEC_OPTS = { timeout: 60_000, maxBuffer: 10 * 1024 * 1024 } as const;

/** Known Homebrew install locations, tried before falling back to `which`. */
const EXIFTOOL_CANDIDATES = ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool"];
const BREW_CANDIDATES = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"];

export type CleanStatus = "cleaned" | "skipped" | "failed" | "partial";

export interface CleanResult {
  path: string;
  status: CleanStatus;
  reason?: string;
  /** Human-readable identifying fields found before cleaning (e.g. "GPS: ..."). */
  removedTags?: string[];
}

/** Identifying tags worth surfacing to the user before they're stripped. */
const PREVIEW_TAGS: Array<{ tag: string; label: string }> = [
  { tag: "GPSPosition", label: "GPS location" },
  { tag: "Make", label: "Camera make" },
  { tag: "Model", label: "Camera model" },
  { tag: "LensModel", label: "Lens" },
  { tag: "Software", label: "Software" },
  { tag: "DateTimeOriginal", label: "Date taken" },
  { tag: "Artist", label: "Artist" },
  { tag: "OwnerName", label: "Owner name" },
  { tag: "SerialNumber", label: "Camera serial" },
];

/** Read a compact set of identifying tags before they're stripped. Never throws. */
async function readPreviewTags(exiftoolPath: string, filePath: string): Promise<string[]> {
  try {
    const { stdout } = await execFileAsync(
      exiftoolPath,
      ["-j", ...PREVIEW_TAGS.map((t) => `-${t.tag}`), filePath],
      EXEC_OPTS,
    );
    const parsed = JSON.parse(stdout) as Array<Record<string, unknown>>;
    const record = parsed[0] ?? {};
    const found: string[] = [];
    for (const { tag, label } of PREVIEW_TAGS) {
      const value = record[tag];
      if (typeof value === "string" && value.trim().length > 0) {
        found.push(`${label}: ${value.trim()}`);
      } else if (typeof value === "number") {
        found.push(`${label}: ${value}`);
      }
    }
    return found;
  } catch {
    return [];
  }
}

let cachedExiftoolPath: string | null | undefined;

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

/** Locate the Homebrew binary for one-click install. Returns null if absent. */
export async function resolveBrew(): Promise<string | null> {
  return resolveBinary("brew", BREW_CANDIDATES);
}

async function resolveBinary(name: string, candidates: string[]): Promise<string | null> {
  const fs = await import("fs");
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

/** Clean one file in place. Never throws — always resolves to a CleanResult. */
export async function cleanFile(exiftoolPath: string, filePath: string): Promise<CleanResult> {
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

  const removedTags = await readPreviewTags(exiftoolPath, filePath);
  const args = buildArgs(info.kind, filePath);

  try {
    const { stdout, stderr } = await execFileAsync(exiftoolPath, args, EXEC_OPTS);
    const result = interpretOutput(filePath, `${stdout}\n${stderr}`);
    return removedTags.length > 0 ? { ...result, removedTags } : result;
  } catch (err) {
    // execFile rejects on non-zero exit; exiftool leaves the file unchanged.
    const e = err as { stdout?: string; stderr?: string; message?: string };
    const combined = `${e.stdout ?? ""}\n${e.stderr ?? ""}`.trim();
    const reason = combined.length > 0 ? firstIssueLine(combined) : e.message || "exiftool failed";
    return { path: filePath, status: "failed", reason };
  }
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
