// MetaBurn — drag photos/videos/folders in to strip metadata in place.

import {
    Badge,
    Button,
    Callout,
    EmptyState,
    EmptyStateActions,
    EmptyStateDescription,
    EmptyStateMedia,
    EmptyStateTitle,
    ScrollArea,
    Status,
    Switch,
    Text,
    Toolbar,
    ToolbarActions,
    ToolbarRow,
    ToolbarTitle,
} from "@electron-core/components";
import { Ban, CheckCircle2, Loader2, ShieldCheck, TriangleAlert, UploadCloud, VolumeX, XCircle } from "lucide-react";
import { type DragEvent as ReactDragEvent, Fragment, useCallback, useEffect, useRef, useState } from "react";

import { type MetadataEntry, buildFieldRows, extOf, fileKind } from "./metadata-fields.js";

// ── Types mirrored from the backend (main/services) ─────────────────────
type CleanStatus = "cleaned" | "skipped" | "failed" | "partial";
type RunState = "waiting" | "scanning" | "cleaning" | "done" | "failed" | "cancelled";

interface Counters {
  supported: number;
  cleaned: number;
  skipped: number;
  failed: number;
  partial: number;
}

interface CleanResult {
  path: string;
  status: CleanStatus;
  reason?: string;
  metadataBefore?: MetadataEntry[];
  metadataAfter?: MetadataEntry[];
}

interface LogEntry extends CleanResult {
  id: number;
}

interface ScanSummary {
  fileCount: number;
  totalBytes: number;
}

interface StateEvent {
  jobId: string;
  state: RunState | "exiftool-missing";
  counters: Counters;
  message?: string;
  scanSummary?: ScanSummary;
}

interface ProgressEvent {
  jobId: string;
  result: CleanResult;
  counters: Counters;
}

const EMPTY_COUNTERS: Counters = { supported: 0, cleaned: 0, skipped: 0, failed: 0, partial: 0 };

const STATUS_LABEL: Record<RunState, string> = {
  waiting: "Waiting for files",
  scanning: "Scanning",
  cleaning: "Cleaning",
  done: "Done",
  failed: "Failed",
  cancelled: "Cancelled",
};

const STATUS_VARIANT: Record<RunState, "neutral" | "loading" | "success" | "error"> = {
  waiting: "neutral",
  scanning: "loading",
  cleaning: "loading",
  done: "success",
  failed: "error",
  cancelled: "neutral",
};

const BADGE_COLOR: Record<CleanStatus, "green" | "orange" | "secondary" | "red"> = {
  cleaned: "green",
  partial: "orange",
  skipped: "secondary",
  failed: "red",
};

function formatBytes(bytes: number): string {
  if (bytes <= 0) return "0 KB";
  const units = ["KB", "MB", "GB"] as const;
  let value = bytes / 1024;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return `${value < 10 ? value.toFixed(1) : Math.round(value)} ${units[unitIndex]}`;
}

function summarizeCounters(counters: Counters): string {
  const cleaned = `${counters.cleaned} ${counters.cleaned === 1 ? "file" : "files"} cleaned`;
  const extras: string[] = [];
  if (counters.skipped > 0) extras.push(`${counters.skipped} skipped`);
  if (counters.partial > 0) extras.push(`${counters.partial} partial`);
  if (counters.failed > 0) extras.push(`${counters.failed} failed`);
  return extras.length > 0 ? `${cleaned} · ${extras.join(" · ")}` : cleaned;
}

export function HomeView() {
  const [exiftoolReady, setExiftoolReady] = useState<boolean | null>(null);
  const [canInstall, setCanInstall] = useState(false);
  const [installing, setInstalling] = useState(false);

  const [muteAudio, setMuteAudio] = useState(false);
  const [ffmpegReady, setFfmpegReady] = useState<boolean | null>(null);
  const [canInstallFfmpeg, setCanInstallFfmpeg] = useState(false);
  const [installingFfmpeg, setInstallingFfmpeg] = useState(false);

  const [runState, setRunState] = useState<RunState>("waiting");
  const [counters, setCounters] = useState<Counters>(EMPTY_COUNTERS);
  const [runMessage, setRunMessage] = useState<string | undefined>(undefined);
  const [scanSummary, setScanSummary] = useState<ScanSummary | null>(null);
  const [log, setLog] = useState<LogEntry[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [isDragging, setIsDragging] = useState(false);
  const [dropNotice, setDropNotice] = useState<string | null>(null);

  const jobIdRef = useRef<string | null>(null);
  const logIdRef = useRef(0);

  const processing = runState === "scanning" || runState === "cleaning";

  // The file whose report is shown: the clicked one, else the first processed.
  const selectedEntry = log.find((e) => e.id === selectedId) ?? log[0] ?? null;

  // ── Verify ExifTool on mount ──────────────────────────────────────────
  const checkExiftool = useCallback(async () => {
    const res = await window.electronAPI.app.ipc.invoke<{
      available: boolean;
      canInstall: boolean;
    }>("clean:checkExiftool");
    setExiftoolReady(res.available);
    setCanInstall(res.canInstall);
  }, []);

  useEffect(() => {
    void checkExiftool();
  }, [checkExiftool]);

  // ── Verify ffmpeg on mount (only needed if Mute Video is used) ─────────
  const checkFfmpeg = useCallback(async () => {
    const res = await window.electronAPI.app.ipc.invoke<{
      available: boolean;
      canInstall: boolean;
    }>("clean:checkFfmpeg");
    setFfmpegReady(res.available);
    setCanInstallFfmpeg(res.canInstall);
  }, []);

  useEffect(() => {
    void checkFfmpeg();
  }, [checkFfmpeg]);

  const handleInstallFfmpeg = useCallback(async () => {
    setInstallingFfmpeg(true);
    try {
      const res = await window.electronAPI.app.ipc.invoke<{ success: boolean }>("clean:installFfmpeg");
      if (res.success) setFfmpegReady(true);
      else await checkFfmpeg();
    } finally {
      setInstallingFfmpeg(false);
    }
  }, [checkFfmpeg]);

  // ── Subscribe to live cleaning events ─────────────────────────────────
  useEffect(() => {
    const offState = window.electronAPI.app.ipc.onNotification("clean:state", (raw) => {
      const evt = raw as StateEvent;
      jobIdRef.current = evt.jobId;
      setCounters(evt.counters);
      if (evt.state === "exiftool-missing") {
        setExiftoolReady(false);
        setRunState("failed");
        return;
      }
      setRunMessage(evt.message);
      setRunState(evt.state);
      if (evt.scanSummary) setScanSummary(evt.scanSummary);
    });

    const offProgress = window.electronAPI.app.ipc.onNotification("clean:progress", (raw) => {
      const evt = raw as ProgressEvent;
      jobIdRef.current = evt.jobId;
      setCounters(evt.counters);
      setLog((prev) => [...prev, { ...evt.result, id: logIdRef.current++ }]);
    });

    return () => {
      offState();
      offProgress();
    };
  }, []);

  // ── Start a cleaning job from a set of paths (drop or browse) ──────────
  const startJob = useCallback(
    (paths: string[]) => {
      if (paths.length === 0) return;
      // Fresh run: reset the log and counters, then auto-start cleaning.
      setDropNotice(null);
      setLog([]);
      setSelectedId(null);
      setCounters(EMPTY_COUNTERS);
      setRunMessage(undefined);
      setScanSummary(null);
      setRunState("scanning");
      void window.electronAPI.app.ipc.invoke("clean:start", { paths, muteAudio });
    },
    [muteAudio],
  );

  // ── Drag & drop (the whole window is a drop target) ───────────────────
  const handleDragOver = useCallback((e: ReactDragEvent) => {
    e.preventDefault();
  }, []);

  const handleDragEnter = useCallback(
    (e: ReactDragEvent) => {
      e.preventDefault();
      if (exiftoolReady && !processing) setIsDragging(true);
    },
    [exiftoolReady, processing],
  );

  const handleDragLeave = useCallback((e: ReactDragEvent) => {
    // Only clear when the pointer leaves the window, not when crossing children.
    if (e.currentTarget === e.target) setIsDragging(false);
  }, []);

  const handleDrop = useCallback(
    (e: ReactDragEvent) => {
      e.preventDefault();
      setIsDragging(false);
      if (!exiftoolReady || processing) return;

      const files = Array.from(e.dataTransfer.files);
      const paths = files
        .map((f) => window.electronAPI.webUtils.getPathForFile(f))
        .filter((p): p is string => typeof p === "string" && p.length > 0);

      if (paths.length === 0) {
        // Never fail silently — tell the user and point them at the fallback.
        setDropNotice(
          files.length > 0
            ? "Couldn't read those items' file paths. Click the drop area to browse and pick them instead."
            : "No files were detected in that drop. Try photos, videos, or a folder — or click to browse.",
        );
        return;
      }

      startJob(paths);
    },
    [exiftoolReady, processing, startJob],
  );

  // ── Native file/folder picker — a reliable fallback for drag & drop ────
  const handleBrowse = useCallback(async () => {
    if (!exiftoolReady || processing) return;
    const res = await window.electronAPI.dialog.showOpenDialog({
      properties: ["openFile", "openDirectory", "multiSelections"],
    });
    if (res.canceled || res.filePaths.length === 0) return;
    startJob(res.filePaths);
  }, [exiftoolReady, processing, startJob]);

  // ── Actions ───────────────────────────────────────────────────────────
  const handleCancel = useCallback(() => {
    if (jobIdRef.current) {
      void window.electronAPI.app.ipc.invoke("clean:cancel", { jobId: jobIdRef.current });
    }
  }, []);

  const handleClearLog = useCallback(() => {
    setLog([]);
    setSelectedId(null);
    setDropNotice(null);
    setCounters(EMPTY_COUNTERS);
    setRunMessage(undefined);
    setScanSummary(null);
    setRunState("waiting");
  }, []);

  // ── Keyboard shortcuts: ⌘K clears the log, ⌘. cancels a running job ────
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (!e.metaKey) return;
      if (e.key.toLowerCase() === "k" && !processing && log.length > 0) {
        e.preventDefault();
        handleClearLog();
      } else if (e.key === "." && processing) {
        e.preventDefault();
        handleCancel();
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [processing, log.length, handleClearLog, handleCancel]);

  const handleInstall = useCallback(async () => {
    setInstalling(true);
    try {
      const res = await window.electronAPI.app.ipc.invoke<{ success: boolean }>("clean:installExiftool");
      if (res.success) {
        setExiftoolReady(true);
        setRunState("waiting");
      } else {
        await checkExiftool();
      }
    } finally {
      setInstalling(false);
    }
  }, [checkExiftool]);

  // ── Missing-dependency view ───────────────────────────────────────────
  if (exiftoolReady === false) {
    return (
      <div className="h-full flex flex-col">
        <Toolbar>
          <ToolbarRow className="relative">
            <ToolbarTitle
              className="absolute left-1/2 -translate-x-1/2 pl-0 text-support-red select-none"
              title="Double-click for About · Right-click for updates"
              onDoubleClick={() => {
                void window.electronAPI.app.ipc.invoke("app:getInfo").then(async (info) => {
                  const i = info as {
                    name: string;
                    version: string;
                    license: string;
                    organization: string;
                    architecture: string;
                    copyright: string;
                  };
                  await window.electronAPI.dialog.showMessageBox({
                    type: "info",
                    title: `About ${i.name}`,
                    message: i.name,
                    detail: [
                      `Version ${i.version}`,
                      i.license,
                      i.organization,
                      i.architecture,
                      i.copyright,
                    ].join("\n"),
                    buttons: ["OK"],
                  });
                });
              }}
              onContextMenu={(e) => {
                e.preventDefault();
                void window.electronAPI.app.ipc.invoke("app:checkForUpdates").then(async (result) => {
                  const r = result as {
                    current_version: string;
                    latest_version: string;
                    update_available: boolean;
                    download_url?: string | null;
                    error?: string | null;
                  };
                  if (r.error) {
                    await window.electronAPI.dialog.showMessageBox({
                      type: "warning",
                      title: "MetaBurn Updates",
                      message: "Update check failed",
                      detail: r.error,
                      buttons: ["OK"],
                    });
                    return;
                  }
                  if (r.update_available) {
                    await window.electronAPI.dialog.showMessageBox({
                      type: "info",
                      title: "MetaBurn Updates",
                      message: `Update available: ${r.latest_version}`,
                      detail: `You have ${r.current_version}.${r.download_url ? `\n\n${r.download_url}` : ""}`,
                      buttons: ["OK"],
                    });
                    return;
                  }
                  await window.electronAPI.dialog.showMessageBox({
                    type: "info",
                    title: "MetaBurn Updates",
                    message: "You're up to date",
                    detail: `Current version: ${r.current_version}`,
                    buttons: ["OK"],
                  });
                });
              }}
            >
              MetaBurn
            </ToolbarTitle>
          </ToolbarRow>
        </Toolbar>
        <EmptyState placement="center">
          <EmptyStateMedia>
            <ShieldCheck className="size-10 text-support-orange" />
          </EmptyStateMedia>
          <EmptyStateTitle>ExifTool is required</EmptyStateTitle>
          <EmptyStateDescription>
            Install it with: <span className="font-mono text-primary">brew install exiftool</span>
          </EmptyStateDescription>
          <EmptyStateActions>
            {canInstall ? (
              <Button variant="accent" onClick={handleInstall} disabled={installing}>
                {installing ? "Installing…" : "Install ExifTool"}
              </Button>
            ) : null}
            <Button variant="transparent" onClick={() => void checkExiftool()} disabled={installing}>
              Re-check
            </Button>
          </EmptyStateActions>
        </EmptyState>
      </div>
    );
  }

  // ── Main view ─────────────────────────────────────────────────────────
  return (
    <div
      className="h-full flex flex-col"
      onDragOver={handleDragOver}
      onDragEnter={handleDragEnter}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      <Toolbar>
        <ToolbarRow className="relative">
          <ToolbarTitle
            className="absolute left-1/2 -translate-x-1/2 pl-0 text-support-red select-none"
            title="Double-click for About · Right-click for updates"
            onDoubleClick={() => {
              void window.electronAPI.app.ipc.invoke("app:getInfo").then(async (info) => {
                const i = info as {
                  name: string;
                  version: string;
                  license: string;
                  organization: string;
                  architecture: string;
                  copyright: string;
                };
                await window.electronAPI.dialog.showMessageBox({
                  type: "info",
                  title: `About ${i.name}`,
                  message: i.name,
                  detail: [
                    `Version ${i.version}`,
                    i.license,
                    i.organization,
                    i.architecture,
                    i.copyright,
                  ].join("\n"),
                  buttons: ["OK"],
                });
              });
            }}
            onContextMenu={(e) => {
              e.preventDefault();
              void window.electronAPI.app.ipc.invoke("app:checkForUpdates").then(async (result) => {
                const r = result as {
                  current_version: string;
                  latest_version: string;
                  update_available: boolean;
                  download_url?: string | null;
                  error?: string | null;
                };
                if (r.error) {
                  void window.electronAPI.dialog.showMessageBox({
                    type: "warning",
                    title: "MetaBurn Updates",
                    message: "Update check failed",
                    detail: r.error,
                    buttons: ["OK"],
                  });
                  return;
                }
                if (r.update_available) {
                  void window.electronAPI.dialog.showMessageBox({
                    type: "info",
                    title: "MetaBurn Updates",
                    message: `Update available: ${r.latest_version}`,
                    detail: `You have ${r.current_version}.${r.download_url ? `\n\n${r.download_url}` : ""}`,
                    buttons: ["OK"],
                  });
                  return;
                }
                void window.electronAPI.dialog.showMessageBox({
                  type: "info",
                  title: "MetaBurn Updates",
                  message: "You're up to date",
                  detail: `Current version: ${r.current_version}`,
                  buttons: ["OK"],
                });
              });
            }}
          >
            MetaBurn
          </ToolbarTitle>
          <ToolbarActions>
            {processing ? (
              <Button variant="transparent" onClick={handleCancel}>
                Cancel
              </Button>
            ) : (
              <Button variant="transparent" onClick={handleClearLog} disabled={log.length === 0}>
                Clear Log
              </Button>
            )}
          </ToolbarActions>
        </ToolbarRow>
      </Toolbar>

      <div className="flex-1 min-h-0 flex flex-col gap-3 px-4 pb-4">
        {/* Drop zone — the whole window accepts drops; click here to browse */}
        <button
          type="button"
          onClick={handleBrowse}
          disabled={processing}
          className={[
            "shrink-0 w-full flex flex-col items-center justify-center gap-1.5 rounded-card border-2 border-dashed py-6 transition-colors",
            isDragging ? "border-accent bg-control-subtle" : "border-separator",
            processing ? "opacity-60" : "hover:border-accent hover:bg-control-subtle",
          ].join(" ")}
        >
          {processing ? (
            <Loader2 className="size-8 text-accent animate-spin" />
          ) : (
            <UploadCloud className="size-8 text-tertiary" />
          )}
          <Text variant="strong" color="primary">
            {processing ? "Processing…" : "Drop photos, videos, or folders here"}
          </Text>
          <Text variant="small" color="secondary">
            {processing ? "Cleaning metadata in place…" : "or click to browse — removed in place, no copies"}
          </Text>
        </button>

        {dropNotice ? (
          <Callout color="orange" icon={<TriangleAlert className="size-4" />} className="shrink-0">
            <Callout.Text>{dropNotice}</Callout.Text>
          </Callout>
        ) : null}

        {/* Mute Video option */}
        <div className="shrink-0 flex items-center justify-between gap-3 rounded-card border border-separator px-3 py-2">
          <div className="flex items-center gap-2 min-w-0">
            <VolumeX className="size-4 text-tertiary shrink-0" />
            <div className="flex flex-col min-w-0">
              <Text variant="small-strong" color="primary">
                Mute Video
              </Text>
              <Text variant="small" color="tertiary">
                Permanently remove audio from videos before cleaning.
              </Text>
            </div>
          </div>
          <Switch checked={muteAudio} onCheckedChange={setMuteAudio} disabled={processing} />
        </div>
        {muteAudio && ffmpegReady === false ? (
          <Callout color="orange" icon={<TriangleAlert className="size-4" />} className="shrink-0">
            <Callout.Text className="flex items-center gap-2 flex-wrap">
              <span>ffmpeg is required to mute audio.</span>
              {canInstallFfmpeg ? (
                <Button variant="transparent" size="small" onClick={handleInstallFfmpeg} disabled={installingFfmpeg}>
                  {installingFfmpeg ? "Installing…" : "Install ffmpeg"}
                </Button>
              ) : null}
            </Callout.Text>
          </Callout>
        ) : null}

        {/* Status + counters */}
        <div className="shrink-0 flex items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <Status variant={STATUS_VARIANT[runState]} />
            <Text variant="small-strong" color="primary">
              {STATUS_LABEL[runState]}
            </Text>
          </div>
          <div className="flex items-center gap-4 tabular-nums">
            <Counter
              label={scanSummary && scanSummary.totalBytes > 0 ? `Found · ${formatBytes(scanSummary.totalBytes)}` : "Found"}
              value={counters.supported}
              color="secondary"
            />
            <Counter label="Cleaned" value={counters.cleaned} color="success" />
            <Counter label="Skipped" value={counters.skipped} color="secondary" />
            <Counter label="Partial" value={counters.partial} color="warning" />
            <Counter label="Failed" value={counters.failed} color="error" />
          </div>
        </div>

        {/* Results summary — a distinct outcome banner once a batch finishes */}
        {runState === "done" ? (
          <Callout color="green" icon={<CheckCircle2 className="size-4" />} className="shrink-0">
            <Callout.Text>Done — {summarizeCounters(counters)}</Callout.Text>
          </Callout>
        ) : runState === "failed" ? (
          <Callout color="red" icon={<XCircle className="size-4" />} className="shrink-0">
            <Callout.Text>Failed — {runMessage ?? summarizeCounters(counters)}</Callout.Text>
          </Callout>
        ) : runState === "cancelled" ? (
          <Callout color="secondary" icon={<Ban className="size-4" />} className="shrink-0">
            <Callout.Text>Cancelled — {summarizeCounters(counters)}</Callout.Text>
          </Callout>
        ) : null}

        {/* Compact file picker — only when more than one file was processed */}
        {log.length > 1 ? (
          <div className="shrink-0 flex gap-2 overflow-x-auto pb-1">
            {log.map((entry) => (
              <FileChip
                key={entry.id}
                entry={entry}
                selected={entry.id === selectedEntry?.id}
                onSelect={() => setSelectedId(entry.id)}
              />
            ))}
          </div>
        ) : null}

        {/* Metadata preview — before / after, fills the remaining height */}
        <div className="flex-1 min-h-0 rounded-card border border-separator overflow-hidden">
          {selectedEntry ? (
            <MetadataReport entry={selectedEntry} />
          ) : (
            <div className="h-full flex items-center justify-center p-4">
              <Text variant="small" color="tertiary" className="text-center">
                Drop a photo, video, or folder to see its before-and-after metadata.
              </Text>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function Counter({
  label,
  value,
  color,
}: {
  label: string;
  value: number;
  color: "secondary" | "success" | "warning" | "error";
}) {
  const valueColor =
    color === "success"
      ? "text-support-green"
      : color === "warning"
        ? "text-support-orange"
        : color === "error"
          ? "text-support-red"
          : "text-primary";
  return (
    <div className="flex items-baseline gap-1.5">
      <span className={`text-[13px] font-semibold ${valueColor}`}>{value}</span>
      <Text variant="small" color="tertiary">
        {label}
      </Text>
    </div>
  );
}

function FileChip({
  entry,
  selected,
  onSelect,
}: {
  entry: LogEntry;
  selected: boolean;
  onSelect: () => void;
}) {
  const name = entry.path.split("/").pop() || entry.path;
  return (
    <button
      type="button"
      onClick={onSelect}
      title={entry.path}
      className={[
        "shrink-0 max-w-[220px] flex items-center gap-2 rounded-control border px-2.5 py-1 transition-colors",
        selected ? "border-accent bg-control-subtle" : "border-separator hover:bg-control-subtle",
      ].join(" ")}
    >
      <Badge color={BADGE_COLOR[entry.status]} size="small">
        {entry.status}
      </Badge>
      <Text variant="small" color={selected ? "primary" : "secondary"} className="truncate">
        {name}
      </Text>
    </button>
  );
}

function MetadataReport({ entry }: { entry: LogEntry }) {
  const name = entry.path.split("/").pop() || entry.path;
  const kind = fileKind(entry.path);
  const ext = extOf(entry.path);
  const rows = buildFieldRows(kind, entry.path, entry.metadataBefore, entry.metadataAfter);
  const sectionTitle = kind === "video" ? "Video Metadata" : "Photo Metadata";
  const typeLabel = kind === "video" ? "Video" : "Photo";

  return (
    <div className="h-full flex flex-col">
      {/* Header: file name, extension, file type */}
      <div className="shrink-0 px-4 py-3 border-b border-separator flex flex-col gap-1.5">
        <Text variant="strong" color="primary" className="truncate" title={entry.path}>
          {name}
        </Text>
        <div className="flex items-center gap-2 flex-wrap">
          <Badge color={BADGE_COLOR[entry.status]} size="small">
            {entry.status}
          </Badge>
          <Text variant="small" color="secondary">
            {ext || "—"} · {typeLabel}
          </Text>
        </div>
        {entry.reason ? (
          <Text variant="small" color="tertiary">
            {entry.reason}
          </Text>
        ) : null}
      </div>

      {/* Section title */}
      <div className="shrink-0 px-4 pt-3 pb-1">
        <Text variant="small-strong" color="secondary">
          {sectionTitle}
        </Text>
      </div>

      {/* Mirrored column headers: Before Burn | After Burn (green underline) */}
      <div className="shrink-0 grid grid-cols-2 border-t border-separator">
        <div className="px-4 py-1.5">
          <Text variant="small-strong" color="primary">
            Before Burn
          </Text>
          <div className="mt-1 h-0.5 w-full bg-support-green" />
        </div>
        <div className="px-4 py-1.5 border-l border-separator">
          <Text variant="small-strong" color="primary">
            After Burn
          </Text>
          <div className="mt-1 h-0.5 w-full bg-support-green" />
        </div>
      </div>

      {/* Field rows — identical labels/order on both sides for easy comparison */}
      <ScrollArea scrollbars="vertical" className="flex-1 min-h-0">
        <div className="grid grid-cols-2">
          {rows.map((row) => {
            const stripped = row.before !== "" && row.after === "";
            return (
              <Fragment key={row.label}>
                <MetaCell label={row.label} value={row.before} tone={stripped ? "removed" : "normal"} />
                <MetaCell label={row.label} value={row.after} tone="normal" leftBorder />
              </Fragment>
            );
          })}
        </div>
      </ScrollArea>
    </div>
  );
}

function MetaCell({
  label,
  value,
  tone,
  leftBorder,
}: {
  label: string;
  value: string;
  tone: "normal" | "removed";
  leftBorder?: boolean;
}) {
  const empty = value === "";
  const valueColor = empty ? "tertiary" : tone === "removed" ? "red" : "primary";
  return (
    <div
      className={[
        "px-4 py-2 border-b border-separator flex flex-col gap-0.5 min-w-0",
        leftBorder ? "border-l" : "",
      ].join(" ")}
    >
      <Text variant="small" color="tertiary">
        {label}
      </Text>
      <Text variant="small-strong" color={valueColor} className="break-words">
        {empty ? "Empty" : value}
      </Text>
    </div>
  );
}
