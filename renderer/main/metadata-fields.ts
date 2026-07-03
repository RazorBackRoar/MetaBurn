// metadata-fields — maps raw ExifTool tag/value pairs into the curated,
// human-readable Photo/Video label sets shown in the per-file report.
//
// The main UI never shows raw ExifTool tag names. Each label resolves from a
// small ordered list of candidate tags; when nothing matches, the value is ""
// and the UI renders it as "Empty".

export interface MetadataEntry {
  tag: string;
  value: string;
}

export type FileKind = "photo" | "video";

const VIDEO_EXTS = new Set(["mov", "mp4", "m4v", "avi", "mkv", "webm"]);

/** Uppercase extension without the dot (e.g. "JPG"), or "" if none. */
export function extOf(filePath: string): string {
  const base = filePath.split("/").pop() ?? filePath;
  const dot = base.lastIndexOf(".");
  return dot > 0 ? base.slice(dot + 1).toUpperCase() : "";
}

/** Classify a file as photo or video by extension (defaults to photo). */
export function fileKind(filePath: string): FileKind {
  return VIDEO_EXTS.has(extOf(filePath).toLowerCase()) ? "video" : "photo";
}

/** Build a tag → value lookup, keeping the first occurrence of each tag. */
function toMap(entries?: MetadataEntry[]): Record<string, string> {
  const map: Record<string, string> = {};
  if (!entries) return map;
  for (const e of entries) {
    if (!(e.tag in map)) map[e.tag] = e.value;
  }
  return map;
}

/** First non-empty value among the candidate tags. */
function get(map: Record<string, string>, ...tags: string[]): string {
  for (const t of tags) {
    const v = map[t];
    if (v && v.trim()) return v.trim();
  }
  return "";
}

function resolution(map: Record<string, string>): string {
  const size = get(map, "ImageSize");
  if (size) return size;
  const w = get(map, "ImageWidth", "ExifImageWidth", "SourceImageWidth");
  const h = get(map, "ImageHeight", "ExifImageHeight", "SourceImageHeight");
  return w && h ? `${w} × ${h}` : "";
}

function camera(map: Record<string, string>): string {
  const make = get(map, "Make");
  const model = get(map, "Model", "CameraModelName");
  if (make && model) return model.includes(make) ? model : `${make} ${model}`;
  return model || make;
}

interface FieldSpec {
  label: string;
  resolve: (map: Record<string, string>, filePath: string) => string;
  /**
   * When true, the After column reuses the Before value instead of re-reading
   * the cleaned file — used for structural fields (File Size, Date Modified)
   * that technically change on write but should mirror identically for an
   * apples-to-apples comparison.
   */
  mirror?: boolean;
}

/** Single GPS/location row (no separate "Location") — first non-empty wins. */
function gps(map: Record<string, string>): string {
  return get(
    map,
    "GPSPosition",
    "GPSCoordinates",
    "GPSLatitude",
    "LocationInformation",
    "Location",
    "City",
    "Sub-location",
    "Country",
  );
}

const PHOTO_FIELDS: FieldSpec[] = [
  { label: "GPS", resolve: (m) => gps(m) },
  { label: "Model", resolve: (m) => get(m, "Model", "CameraModelName", "HostComputer") },
  { label: "Make", resolve: (m) => get(m, "Make") },
  { label: "File Size", resolve: (m) => get(m, "FileSize"), mirror: true },
  { label: "File Type", resolve: (m) => get(m, "FileType", "MIMEType") },
  { label: "Resolution", resolve: (m) => resolution(m) },
  { label: "Date Created", resolve: (m) => get(m, "CreateDate", "CreationDate", "DateTimeOriginal") },
  { label: "Date Modified", resolve: (m) => get(m, "ModifyDate", "FileModifyDate"), mirror: true },
  { label: "Camera", resolve: (m) => camera(m) },
  { label: "Lens", resolve: (m) => get(m, "LensModel", "LensInfo", "LensMake", "Lens") },
  { label: "Software", resolve: (m) => get(m, "Software", "HostComputer") },
];

const VIDEO_FIELDS: FieldSpec[] = [
  { label: "FPS", resolve: (m) => get(m, "VideoFrameRate", "FrameRate") },
  { label: "GPS", resolve: (m) => gps(m) },
  { label: "Model", resolve: (m) => get(m, "Model", "CameraModelName") },
  { label: "Make", resolve: (m) => get(m, "Make") },
  { label: "File Size", resolve: (m) => get(m, "FileSize"), mirror: true },
  { label: "File Type", resolve: (m) => get(m, "FileType", "MIMEType") },
  { label: "Resolution", resolve: (m) => resolution(m) },
  { label: "Duration", resolve: (m) => get(m, "Duration", "MediaDuration", "TrackDuration") },
  { label: "Date Created", resolve: (m) => get(m, "CreateDate", "CreationDate") },
  { label: "Date Modified", resolve: (m) => get(m, "ModifyDate", "FileModifyDate"), mirror: true },
  { label: "Date Recorded", resolve: (m) => get(m, "CreationDate", "MediaCreateDate", "DateTimeOriginal", "CreateDate") },
  { label: "Camera", resolve: (m) => camera(m) },
  { label: "Lens", resolve: (m) => get(m, "LensModel", "Lens") },
  { label: "Video Codec", resolve: (m) => get(m, "CompressorName", "VideoCodec", "CompressorID") },
  { label: "Audio / Sound", resolve: (m) => get(m, "AudioFormat", "AudioChannels", "AudioSampleRate", "AudioBitsPerSample") },
  { label: "Software", resolve: (m) => get(m, "Software", "Encoder", "HandlerDescription") },
];

export interface FieldRow {
  label: string;
  before: string;
  after: string;
}

/** Resolve the curated label set for a file into mirrored Before/After rows. */
export function buildFieldRows(
  kind: FileKind,
  filePath: string,
  before?: MetadataEntry[],
  after?: MetadataEntry[],
): FieldRow[] {
  const specs = kind === "video" ? VIDEO_FIELDS : PHOTO_FIELDS;
  const beforeMap = toMap(before);
  const afterMap = toMap(after);
  return specs.map((s) => {
    const before = s.resolve(beforeMap, filePath);
    // Mirror structural fields so both columns match exactly.
    const after = s.mirror ? before : s.resolve(afterMap, filePath);
    return { label: s.label, before, after };
  });
}
