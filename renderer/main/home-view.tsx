// MetaCleaner — drag photos/videos/folders in to strip metadata in place.

import { type DragEvent as ReactDragEvent, useCallback, useEffect, useRef, useState } from "react";
import {
  Toolbar,
  ToolbarContent,
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
} from "@glaze/core/components";
import { ShieldCheck, UploadCloud, Loader2, CheckCircle2, XCircle, Ban } from "lucide-react";

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
}

interface LogEntry extends CleanResult {
  id: number;
}

interface StateEvent {
  jobId: string;
  state: RunState | "exiftool-missing";
  counters: Counters;
  message?: string;
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

  const [runState, setRunState] = useState<RunState>("waiting");
  const [counters, setCounters] = useState<Counters>(EMPTY_COUNTERS);
  const [runMessage, setRunMessage] = useState<string | undefined>(undefined);
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
      setRunState("scanning");
      void window.glazeAPI.glaze.ipc.invoke("clean:start", { paths });
    },
    [exiftoolReady, processing],
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
    setRunState("waiting");
  }, []);

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
      <div className="h-full flex flex-col border-2 border-support-red">
        <Toolbar>
          <ToolbarContent>
            <ToolbarTitle>MetaCleaner</ToolbarTitle>
          </ToolbarContent>
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
    <div className="h-full flex flex-col border-2 border-support-red">
      <Toolbar>
        <ToolbarContent>
          <ToolbarTitle>MetaCleaner</ToolbarTitle>
        </ToolbarContent>
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

        {/* Status + counters */}
        <div className="shrink-0 flex items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <Status variant={STATUS_VARIANT[runState]} />
            <Text variant="small-strong" color="primary">
              {STATUS_LABEL[runState]}
            </Text>
          </div>
          <div className="flex items-center gap-4 tabular-nums">
            <Counter label="Found" value={counters.supported} color="secondary" />
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
  return (
    <div className="flex items-start gap-3 px-3 py-2 border-b border-separator last:border-b-0">
      <Badge color={BADGE_COLOR[entry.status]} size="small">
        {entry.status}
      </Badge>
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
    </div>
  );
}
