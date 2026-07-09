export type ClassValue =
  | string
  | number
  | boolean
  | undefined
  | null
  | ClassValue[]
  | { [key: string]: boolean | undefined | null };

function flatten(inputs: ClassValue[]): string[] {
  const out: string[] = [];
  for (const input of inputs) {
    if (!input) continue;
    if (typeof input === "string" || typeof input === "number") {
      out.push(String(input));
    } else if (Array.isArray(input)) {
      out.push(...flatten(input));
    } else if (typeof input === "object") {
      for (const [key, value] of Object.entries(input)) {
        if (value) out.push(key);
      }
    }
  }
  return out;
}

export function cn(...inputs: ClassValue[]) {
  const classes = flatten(inputs);
  const seen = new Set<string>();
  const result: string[] = [];
  for (const c of classes) {
    const trimmed = c.trim();
    if (!trimmed) continue;
    const parts = trimmed.split(/\s+/);
    for (const p of parts) {
      if (!seen.has(p)) {
        seen.add(p);
        result.push(p);
      }
    }
  }
  return result.join(" ");
}

/** Kept for renderer bootstrap; file logging is main-process only. */
export function initLogging() {
  // No-op in renderer; Electron console logging is sufficient here.
}

export { DISPLAY_NAME, GITHUB_REPO, APP_ID } from "./brand.js";
