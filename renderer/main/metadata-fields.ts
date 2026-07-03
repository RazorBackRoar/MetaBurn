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

/** First candidate value that matches the pattern (e.g. "iPhone", "Apple"). */
function match(map: Record<string, string>, re: RegExp, ...tags: string[]): string {
  for (const t of tags) {
    const v = map[t];
    if (v && re.test(v)) return v.trim();
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
}

const PHOTO_FIELDS: FieldSpec[] = [
  { label: "Extension", resolve: (_m, p) => extOf(p) },
  { label: "File Type", resolve: (m) => get(m, "FileType", "MIMEType") },
  { label: "File Size", resolve: (m) => get(m, "FileSize") },
  { label: "Resolution", resolve: (m) => resolution(m) },
  { label: "GPS", resolve: (m) => get(m, "GPSPosition", "GPSCoordinates", "GPSLatitude") },
  {
    label: "Location",
    resolve: (m) => get(m, "GPSPosition", "Location", "City", "Sub-location", "ProvinceState", "Country", "CountryCode"),
  },
  { label: "Apple", resolve: (m) => match(m, /apple/i, "Make", "HostComputer", "Software") },
  { label: "Device Model", resolve: (m) => get(m, "Model", "CameraModelName", "HostComputer") },
  { label: "iPhone Model", resolve: (m) => match(m, /iphone|ipad/i, "Model", "HostComputer") },
  { label: "Camera", resolve: (m) => camera(m) },
  { label: "Front Camera", resolve: (m) => match(m, /front/i, "LensModel", "LensInfo", "Lens") },
  { label: "Back Camera", resolve: (m) => match(m, /back/i, "LensModel", "LensInfo", "Lens") },
  { label: "Lens", resolve: (m) => get(m, "LensModel", "LensInfo", "LensMake", "Lens") },
  { label: "Date Created", resolve: (m) => get(m, "CreateDate", "CreationDate", "DateTimeOriginal") },
  { label: "Date Modified", resolve: (m) => get(m, "ModifyDate", "FileModifyDate") },
  { label: "Date Taken", resolve: (m) => get(m, "DateTimeOriginal", "CreateDate") },
  { label: "Software", resolve: (m) => get(m, "Software", "HostComputer") },
  { label: "Orientation", resolve: (m) => get(m, "Orientation") },
];

const VIDEO_FIELDS: FieldSpec[] = [
  { label: "Extension", resolve: (_m, p) => extOf(p) },
  { label: "File Type", resolve: (m) => get(m, "FileType", "MIMEType") },
  { label: "File Size", resolve: (m) => get(m, "FileSize") },
  { label: "Duration", resolve: (m) => get(m, "Duration", "MediaDuration", "TrackDuration") },
  { label: "Resolution", resolve: (m) => resolution(m) },
  { label: "Frame Rate", resolve: (m) => get(m, "VideoFrameRate", "FrameRate") },
  { label: "Video Codec", resolve: (m) => get(m, "CompressorName", "VideoCodec", "CompressorID") },
  { label: "Audio / Sound", resolve: (m) => get(m, "AudioFormat", "AudioChannels", "AudioSampleRate", "AudioBitsPerSample") },
  { label: "GPS", resolve: (m) => get(m, "GPSPosition", "GPSCoordinates", "GPSLatitude") },
  { label: "Location", resolve: (m) => get(m, "GPSPosition", "GPSCoordinates", "LocationInformation", "Location") },
  { label: "Apple", resolve: (m) => match(m, /apple/i, "Make", "Model", "HandlerDescription", "Software") },
  { label: "Device Model", resolve: (m) => get(m, "Model", "Make") },
  { label: "iPhone Model", resolve: (m) => match(m, /iphone|ipad/i, "Model") },
  { label: "Camera", resolve: (m) => camera(m) },
  { label: "Front Camera", resolve: (m) => match(m, /front/i, "LensModel", "Lens") },
  { label: "Back Camera", resolve: (m) => match(m, /back/i, "LensModel", "Lens") },
  { label: "Lens", resolve: (m) => get(m, "LensModel", "Lens") },
  { label: "Date Created", resolve: (m) => get(m, "CreateDate", "CreationDate") },
  { label: "Date Modified", resolve: (m) => get(m, "ModifyDate", "FileModifyDate") },
  { label: "Date Recorded", resolve: (m) => get(m, "CreationDate", "MediaCreateDate", "DateTimeOriginal", "CreateDate") },
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
  return specs.map((s) => ({
    label: s.label,
    before: s.resolve(beforeMap, filePath),
    after: s.resolve(afterMap, filePath),
  }));
}
