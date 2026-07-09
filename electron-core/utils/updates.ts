import * as fs from "node:fs";
import * as https from "node:https";
import * as path from "node:path";

import { DISPLAY_NAME, GITHUB_ORG, GITHUB_REPO } from "./brand.js";
import { appCacheDir, ensureCacheDir } from "./paths.js";

const CACHE_DURATION_SECS = 3600;
const USER_AGENT = "metaburn-update-checker/1.0";

export interface UpdateResult {
  current_version: string;
  latest_version: string;
  update_available: boolean;
  download_url?: string | null;
  release_notes?: string | null;
  release_date?: string | null;
  error?: string | null;
}

interface GitHubRelease {
  tag_name: string;
  html_url?: string;
  body?: string;
  published_at?: string;
}

interface CachePayload {
  timestamp: number;
  latest_version: string;
  download_url?: string | null;
  release_notes?: string | null;
  release_date?: string | null;
}

function cacheFile(): string {
  return path.join(appCacheDir(), "update_check.json");
}

function nowSecs(): number {
  return Math.floor(Date.now() / 1000);
}

/** Compare major.minor.patch (optional leading `v`). Returns -1 / 0 / 1. */
export function compareVersions(a: string, b: string): number {
  const pa = parseVersion(a);
  const pb = parseVersion(b);
  if (!pa || !pb) return 0;
  for (let i = 0; i < 3; i++) {
    if (pa[i]! < pb[i]!) return -1;
    if (pa[i]! > pb[i]!) return 1;
  }
  return 0;
}

function parseVersion(version: string): [number, number, number] | null {
  const cleaned = version.trim().replace(/^v/i, "");
  const match = /^(\d+)\.(\d+)\.(\d+)/.exec(cleaned);
  if (!match) return null;
  return [Number(match[1]), Number(match[2]), Number(match[3])];
}

function readCache(): CachePayload | null {
  try {
    const raw = fs.readFileSync(cacheFile(), "utf8");
    const payload = JSON.parse(raw) as CachePayload;
    if (nowSecs() - payload.timestamp > CACHE_DURATION_SECS) return null;
    return payload;
  } catch {
    return null;
  }
}

function writeCache(payload: CachePayload): void {
  try {
    ensureCacheDir();
    fs.writeFileSync(cacheFile(), JSON.stringify(payload), "utf8");
  } catch {
    // non-fatal
  }
}

function fetchLatestRelease(): Promise<GitHubRelease> {
  const url = `https://api.github.com/repos/${GITHUB_ORG}/${GITHUB_REPO}/releases/latest`;
  return new Promise((resolve, reject) => {
    const req = https.get(
      url,
      {
        headers: {
          "User-Agent": USER_AGENT,
          Accept: "application/vnd.github.v3+json",
        },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => {
          data += chunk;
        });
        res.on("end", () => {
          if (res.statusCode && res.statusCode >= 400) {
            reject(new Error(`GitHub Releases returned HTTP ${res.statusCode}`));
            return;
          }
          try {
            resolve(JSON.parse(data) as GitHubRelease);
          } catch (err) {
            reject(err);
          }
        });
      },
    );
    req.on("error", reject);
  });
}

/** Check GitHub Releases for a newer version of MetaBurn. */
export async function checkForUpdates(currentVersion: string): Promise<UpdateResult> {
  const cached = readCache();
  if (cached) {
    return {
      current_version: currentVersion,
      latest_version: cached.latest_version,
      update_available: compareVersions(currentVersion, cached.latest_version) < 0,
      download_url: cached.download_url,
      release_notes: cached.release_notes,
      release_date: cached.release_date,
      error: null,
    };
  }

  try {
    const release = await fetchLatestRelease();
    const latest = release.tag_name.replace(/^v/i, "");
    writeCache({
      timestamp: nowSecs(),
      latest_version: latest,
      download_url: release.html_url ?? null,
      release_notes: release.body ?? null,
      release_date: release.published_at ?? null,
    });
    return {
      current_version: currentVersion,
      latest_version: latest,
      update_available: compareVersions(currentVersion, latest) < 0,
      download_url: release.html_url ?? null,
      release_notes: release.body ?? null,
      release_date: release.published_at ?? null,
      error: null,
    };
  } catch (err) {
    return {
      current_version: currentVersion,
      latest_version: currentVersion,
      update_available: false,
      download_url: null,
      release_notes: null,
      release_date: null,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

export function updatesCacheLabel(): string {
  return `${DISPLAY_NAME} update cache → ${appCacheDir()}`;
}
