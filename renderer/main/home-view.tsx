// MetaBurn — drag photos/videos/folders in to strip metadata in place.

import { type DragEvent as ReactDragEvent, useCallback, useEffect, useRef, useState } from "react";
import {
  Toolbar,
  ToolbarRow,
  ToolbarTitle,
  ToolbarActions,
  Button,
  Badge,
  Status,
  Text,
  ScrollArea,
  EmptyState,
  EmptyStateTitle,
  EmptyStateDescription,
  EmptyStateActions,
  EmptyStateMedia,
  Callout,
  CollapsibleRoot,
  CollapsibleTrigger,
  CollapsibleChevron,
  CollapsibleContent,
  Switch,
} from "@glaze/core/components";
import { ShieldCheck, UploadCloud, Loader2, CheckCircle2, XCircle, Ban, VolumeX, TriangleAlert } from "lucide-react";

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

interface MetadataEntry {
  tag: string;
  value: string;
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
  const [isDragging, setIsDragging] = useState(false);

  const jobIdRef = useRef<string | null>(null);
  const logIdRef = useRef(0);

  const processing = runState === "scanning" || runState === "cleaning";

  // ── Verify ExifTool on mount ──────────────────────────────────────────
  const checkExiftool = useCallback(async () => {
    const res = await window.glazeAPI.glaze.ipc.invoke<{
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
    const res = await window.glazeAPI.glaze.ipc.invoke<{
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
      const res = await window.glazeAPI.glaze.ipc.invoke<{ success: boolean }>("clean:installFfmpeg");
      if (res.success) setFfmpegReady(true);
      else await checkFfmpeg();
    } finally {
      setInstallingFfmpeg(false);
    }
  }, [checkFfmpeg]);

  // ── Subscribe to live cleaning events ─────────────────────────────────
  useEffect(() => {
    const offState = window.glazeAPI.glaze.ipc.onNotification("clean:state", (raw) => {
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

    const offProgress = window.glazeAPI.glaze.ipc.onNotification("clean:progress", (raw) => {
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

  // ── Drag & drop ───────────────────────────────────────────────────────
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
    // Only clear when leaving the drop zone itself, not its children.
    if (e.currentTarget === e.target) setIsDragging(false);
  }, []);

  const handleDrop = useCallback(
    (e: ReactDragEvent) => {
      e.preventDefault();
      setIsDragging(false);
      if (!exiftoolReady || processing) return;

      const paths = Array.from(e.dataTransfer.files)
        .map((f) => window.glazeAPI.webUtils.getPathForFile(f))
        .filter((p): p is string => typeof p === "string" && p.length > 0);

      if (paths.length === 0) return;

      // Fresh run: reset the log and counters, then auto-start cleaning.
      setLog([]);
      setCounters(EMPTY_COUNTERS);
      setRunMessage(undefined);
      setScanSummary(null);
      setRunState("scanning");
      void window.glazeAPI.glaze.ipc.invoke("clean:start", { paths, muteAudio });
    },
    [exiftoolReady, processing, muteAudio],
  );

  // ── Actions ───────────────────────────────────────────────────────────
  const handleCancel = useCallback(() => {
    if (jobIdRef.current) {
      void window.glazeAPI.glaze.ipc.invoke("clean:cancel", { jobId: jobIdRef.current });
    }
  }, []);

  const handleClearLog = useCallback(() => {
    setLog([]);
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
      const res = await window.glazeAPI.glaze.ipc.invoke<{ success: boolean }>("clean:installExiftool");
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
            <ToolbarTitle className="absolute left-1/2 -translate-x-1/2 pl-0 text-support-red">
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
    <div className="h-full flex flex-col">
      <Toolbar>
        <ToolbarRow className="relative">
          <ToolbarTitle className="absolute left-1/2 -translate-x-1/2 pl-0 text-support-red">
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

      <div className="flex-1 min-h-0 flex flex-col gap-4 px-4 pb-4">
        {/* Drop zone */}
        <div
          onDragOver={handleDragOver}
          onDragEnter={handleDragEnter}
          onDragLeave={handleDragLeave}
          onDrop={handleDrop}
          className={[
            "shrink-0 flex flex-col items-center justify-center gap-2 rounded-card border-2 border-dashed py-8 transition-colors",
            isDragging ? "border-accent bg-control-subtle" : "border-separator",
            processing ? "opacity-60" : "",
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
            Metadata is removed in place — no copies, no backups.
          </Text>
        </div>

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

        {/* Live log */}
        <div className="flex-1 min-h-0 rounded-card border border-separator overflow-hidden">
          {log.length === 0 ? (
            <div className="h-full flex items-center justify-center">
              <Text variant="small" color="tertiary">
                Processed files will appear here.
              </Text>
            </div>
          ) : (
            <ScrollArea
              scrollbars="vertical"
              className="h-full"
              autoScrollToBottom
              autoScrollDeps={[log.length]}
            >
              <div className="flex flex-col">
                {log.map((entry) => (
                  <LogRow key={entry.id} entry={entry} />
                ))}
              </div>
            </ScrollArea>
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
      <span className={`text-small-strong ${valueColor}`}>{value}</span>
      <Text variant="small" color="tertiary">
        {label}
      </Text>
    </div>
  );
}

function LogRow({ entry }: { entry: LogEntry }) {
  const name = entry.path.split("/").pop() || entry.path;
  const before = entry.metadataBefore ?? [];
  const after = entry.metadataAfter ?? [];
  const hasPreview = before.length > 0 || after.length > 0;

  const details = (
    <div className="flex-1 min-w-0 flex flex-col">
      <Text variant="small-strong" color="primary" className="truncate" title={entry.path}>
        {name}
      </Text>
      <Text variant="small" color="tertiary" className="truncate" title={entry.path}>
        {entry.path}
      </Text>
      {entry.reason ? (
        <Text variant="small" color="secondary">
          {entry.reason}
        </Text>
      ) : null}
    </div>
  );

  if (!hasPreview) {
    return (
      <div className="flex items-start gap-3 px-3 py-2 border-b border-separator last:border-b-0">
        <Badge color={BADGE_COLOR[entry.status]} size="small">
          {entry.status}
        </Badge>
        {details}
      </div>
    );
  }

  const afterTags = new Set(after.map((e) => e.tag));

  return (
    <CollapsibleRoot className="border-b border-separator last:border-b-0">
      <CollapsibleTrigger className="w-full flex items-start gap-3 px-3 py-2 text-left">
        <Badge color={BADGE_COLOR[entry.status]} size="small">
          {entry.status}
        </Badge>
        {details}
        <div className="shrink-0 flex items-center gap-1.5 mt-0.5">
          <Text variant="small" color="tertiary">
            {before.length} → {after.length}
          </Text>
          <CollapsibleChevron className="size-3.5 shrink-0 text-tertiary" />
        </div>
      </CollapsibleTrigger>
      <CollapsibleContent>
        <div className="pl-3 pr-3 pb-2 pt-0 grid grid-cols-2 gap-3">
          <div className="flex flex-col gap-1 min-w-0">
            <Text variant="small-strong" color="tertiary">
              Before ({before.length})
            </Text>
            <ScrollArea scrollbars="vertical" className="max-h-48">
              <div className="flex flex-col gap-0.5 pr-2">
                {before.length === 0 ? (
                  <Text variant="small" color="tertiary">
                    No metadata found
                  </Text>
                ) : (
                  before.map((e) => <MetadataLine key={e.tag} entry={e} removed={!afterTags.has(e.tag)} />)
                )}
              </div>
            </ScrollArea>
          </div>
          <div className="flex flex-col gap-1 min-w-0">
            <Text variant="small-strong" color="tertiary">
              After ({after.length})
            </Text>
            <ScrollArea scrollbars="vertical" className="max-h-48">
              <div className="flex flex-col gap-0.5 pr-2">
                {after.length === 0 ? (
                  <Text variant="small" color="tertiary">
                    No metadata remaining
                  </Text>
                ) : (
                  after.map((e) => <MetadataLine key={e.tag} entry={e} removed={false} />)
                )}
              </div>
            </ScrollArea>
          </div>
        </div>
      </CollapsibleContent>
    </CollapsibleRoot>
  );
}

function MetadataLine({ entry, removed }: { entry: MetadataEntry; removed: boolean }) {
  return (
    <Text variant="small" color={removed ? "red" : "secondary"} truncate title={`${entry.tag}: ${entry.value}`}>
      {entry.tag}: {entry.value}
    </Text>
  );
}
