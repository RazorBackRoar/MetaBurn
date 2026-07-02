/**
 * clean handlers — IPC entry points for the metadata cleaner.
 *
 * Channels:
 *  - "clean:checkExiftool" → { available, path }  (also probes brew for install)
 *  - "clean:checkFfmpeg"   → { available, path, canInstall } (needed only for Mute Video)
 *  - "clean:start"         → runs a job over dropped paths, returns final Summary
 *  - "clean:cancel"        → requests cancellation of a running job
 *  - "clean:installExiftool" → runs `brew install exiftool` (one-click setup)
 *  - "clean:installFfmpeg"   → runs `brew install ffmpeg` (one-click setup)
 */

import { execFile } from "node:child_process";
import { promisify } from "util";

import { logger } from "@glaze/core/backend";

import { runClean, cancel, type Summary } from "../services/taskRunner.js";
import {
  resolveExiftool,
  resolveFfmpeg,
  resolveBrew,
  invalidateExiftoolCache,
  invalidateFfmpegCache,
} from "../services/metadataCleaner.js";

const execFileAsync = promisify(execFile);

let jobCounter = 0;
function nextJobId(): string {
  jobCounter += 1;
  return `job-${Date.now()}-${jobCounter}`;
}

export const cleanHandlers = {
  checkExiftool: async (): Promise<{ available: boolean; path: string | null; canInstall: boolean }> => {
    const path = await resolveExiftool();
    const brew = await resolveBrew();
    return { available: !!path, path, canInstall: !!brew };
  },

  checkFfmpeg: async (): Promise<{ available: boolean; path: string | null; canInstall: boolean }> => {
    const path = await resolveFfmpeg();
    const brew = await resolveBrew();
    return { available: !!path, path, canInstall: !!brew };
  },

  start: async (params: { paths?: string[]; muteAudio?: boolean }): Promise<Summary> => {
    const paths = Array.isArray(params?.paths) ? params.paths.filter((p) => typeof p === "string") : [];
    const muteAudio = params?.muteAudio === true;
    const jobId = nextJobId();
    logger.info("clean", `Starting job ${jobId} for ${paths.length} dropped path(s)`, { muteAudio });
    return runClean(jobId, paths, muteAudio);
  },

  cancel: async (params: { jobId?: string }): Promise<{ cancelled: boolean }> => {
    const jobId = params?.jobId;
    if (!jobId) return { cancelled: false };
    return { cancelled: cancel(jobId) };
  },

  installExiftool: async (): Promise<{ success: boolean; message?: string }> => {
    const brew = await resolveBrew();
    if (!brew) {
      return { success: false, message: "Homebrew not found. Install ExifTool manually: brew install exiftool" };
    }
    try {
      await execFileAsync(brew, ["install", "exiftool"], {
        timeout: 10 * 60_000,
        maxBuffer: 10 * 1024 * 1024,
      });
      invalidateExiftoolCache();
      const path = await resolveExiftool();
      return { success: !!path };
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      logger.error("clean", "ExifTool install failed", err);
      return { success: false, message };
    }
  },

  installFfmpeg: async (): Promise<{ success: boolean; message?: string }> => {
    const brew = await resolveBrew();
    if (!brew) {
      return { success: false, message: "Homebrew not found. Install ffmpeg manually: brew install ffmpeg" };
    }
    try {
      await execFileAsync(brew, ["install", "ffmpeg"], {
        timeout: 10 * 60_000,
        maxBuffer: 10 * 1024 * 1024,
      });
      invalidateFfmpegCache();
      const path = await resolveFfmpeg();
      return { success: !!path };
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      logger.error("clean", "ffmpeg install failed", err);
      return { success: false, message };
    }
  },
};
