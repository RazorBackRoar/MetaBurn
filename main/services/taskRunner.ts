/**
 * taskRunner — orchestrates a cleaning run: scan → clean sequentially, while
 * broadcasting live progress and supporting cancellation between files.
 *
 * Events broadcast to renderers (received via glazeAPI.glaze.ipc.onNotification):
 *  - "clean:state"    → { jobId, state, counters, message? }
 *  - "clean:progress" → { jobId, result, counters }
 *
 * Cleaning is sequential (one file at a time) so cancel checks and progress
 * updates happen at safe boundaries between files.
 */

import { ipcMain, logger, Notification } from "@glaze/core/backend";

import { buildFileList } from "./scanner.js";
import { cleanFile, resolveExiftool, resolveFfmpeg, type CleanResult, type CleanStatus } from "./metadataCleaner.js";

export type RunState =
  | "scanning"
  | "cleaning"
  | "done"
  | "failed"
  | "cancelled"
  | "exiftool-missing";

export interface Counters {
  supported: number;
  cleaned: number;
  skipped: number;
  failed: number;
  partial: number;
}

export interface Summary {
  jobId: string;
  state: RunState;
  counters: Counters;
  message?: string;
}

export interface ScanSummary {
  fileCount: number;
  totalBytes: number;
}

interface ActiveJob {
  id: string;
  cancelled: boolean;
}

let activeJob: ActiveJob | null = null;

function emptyCounters(): Counters {
  return { supported: 0, cleaned: 0, skipped: 0, failed: 0, partial: 0 };
}

function tally(counters: Counters, status: CleanStatus): void {
  if (status === "cleaned") counters.cleaned += 1;
  else if (status === "skipped") counters.skipped += 1;
  else if (status === "failed") counters.failed += 1;
  else if (status === "partial") counters.partial += 1;
}

function broadcastState(summary: Summary, scanSummary?: ScanSummary): void {
  ipcMain.broadcast("clean:state", scanSummary ? { ...summary, scanSummary } : summary);
}

function broadcastProgress(jobId: string, result: CleanResult, counters: Counters): void {
  ipcMain.broadcast("clean:progress", { jobId, result, counters });
}

function summarizeForNotification(counters: Counters): string {
  const parts = [`${counters.cleaned} cleaned`];
  if (counters.skipped > 0) parts.push(`${counters.skipped} skipped`);
  if (counters.partial > 0) parts.push(`${counters.partial} partial`);
  if (counters.failed > 0) parts.push(`${counters.failed} failed`);
  return parts.join(" · ");
}

function notifyCompletion(state: RunState, counters: Counters, message?: string): void {
  if (!Notification.isSupported()) return;
  const body =
    state === "done"
      ? summarizeForNotification(counters)
      : state === "cancelled"
        ? `Cancelled — ${summarizeForNotification(counters)}`
        : message || "Cleaning failed";
  new Notification({ title: "MetaBurn", body }).show();
}

/** Run a full cleaning job over the dropped paths. Returns the final summary. */
export async function runClean(jobId: string, droppedPaths: string[], muteAudio: boolean): Promise<Summary> {
  activeJob = { id: jobId, cancelled: false };
  const counters = emptyCounters();

  try {
    const exiftoolPath = await resolveExiftool();
    const ffmpegPath = muteAudio ? await resolveFfmpeg() : null;
    if (!exiftoolPath) {
      const summary: Summary = {
        jobId,
        state: "exiftool-missing",
        counters,
        message: "ExifTool is required. Install it with: brew install exiftool",
      };
      broadcastState(summary);
      return summary;
    }

    // ── Scan ──────────────────────────────────────────────────────────
    broadcastState({ jobId, state: "scanning", counters });
    const { files, skipped, totalBytes } = await buildFileList(droppedPaths);

    // Report scan-time skips (symlinks, unreadable entries) in the log.
    for (const s of skipped) {
      counters.skipped += 1;
      broadcastProgress(jobId, { path: s.path, status: "skipped", reason: s.reason }, counters);
    }

    counters.supported = files.length;

    // ── Clean ─────────────────────────────────────────────────────────
    broadcastState({ jobId, state: "cleaning", counters }, { fileCount: files.length, totalBytes });

    for (const file of files) {
      if (activeJob?.cancelled) {
        const summary: Summary = { jobId, state: "cancelled", counters };
        broadcastState(summary);
        notifyCompletion(summary.state, counters);
        return summary;
      }

      const result = await cleanFile(exiftoolPath, file, { muteAudio, ffmpegPath });
      tally(counters, result.status);
      broadcastProgress(jobId, result, counters);
    }

    const finalState: RunState = activeJob?.cancelled ? "cancelled" : "done";
    const summary: Summary = { jobId, state: finalState, counters };
    broadcastState(summary);
    notifyCompletion(summary.state, counters);
    return summary;
  } catch (err) {
    logger.error("taskRunner", "Cleaning run failed", err);
    const summary: Summary = {
      jobId,
      state: "failed",
      counters,
      message: err instanceof Error ? err.message : String(err),
    };
    broadcastState(summary);
    notifyCompletion(summary.state, counters, summary.message);
    return summary;
  } finally {
    if (activeJob?.id === jobId) activeJob = null;
  }
}

/** Request cancellation of the given job (takes effect before the next file). */
export function cancel(jobId: string): boolean {
  if (activeJob && activeJob.id === jobId) {
    activeJob.cancelled = true;
    return true;
  }
  return false;
}
