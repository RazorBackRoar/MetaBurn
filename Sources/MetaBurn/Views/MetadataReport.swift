import SwiftUI
import MetaBurnCore

struct MetadataReport: View {
    let entry: LogEntry

    private var fileName: String {
        URL(fileURLWithPath: entry.path).lastPathComponent
    }

    private var directory: String {
        URL(fileURLWithPath: entry.path).deletingLastPathComponent().path
    }

    private var kind: String {
        SupportedTypes.isVideo(filePath: entry.path) ? "Video" : "Photo"
    }

    private var ext: String {
        let value = (entry.path as NSString).pathExtension.uppercased()
        return value.isEmpty ? "—" : value
    }

    private var allRows: [FieldRow] {
        MetadataFieldBuilder.buildRows(
            filePath: entry.path,
            before: entry.metadataBefore,
            after: entry.metadataAfter
        )
    }

    /// Skip empty dash rows so screenshots don't show a tall empty table.
    private var visibleRows: [FieldRow] {
        allRows.filter { !$0.before.isEmpty || !$0.after.isEmpty || $0.stripped }
    }

    private var strippedCount: Int {
        allRows.filter(\.stripped).count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(MetaBurnTheme.divider)

            if entry.status == .failed || entry.status == .skipped {
                messageBlock
                Divider().overlay(MetaBurnTheme.divider)
            }

            if visibleRows.isEmpty {
                emptyMetadata
            } else {
                tableHeader
                Divider().overlay(MetaBurnTheme.divider)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                            compactRow(row)
                            if index < visibleRows.count - 1 {
                                Divider().overlay(MetaBurnTheme.divider.opacity(0.55))
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(MetaBurnTheme.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(fileName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusBadge
                Spacer(minLength: 0)
            }

            Text(directory)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(entry.path)

            HStack(spacing: 6) {
                metaChip("\(ext) · \(kind)")
                metaChip(outcomeLabel)
                if strippedCount > 0 {
                    metaChip("\(strippedCount) removed")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MetaBurnTheme.surface.opacity(0.45))
    }

    private var emptyMetadata: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 22))
                .foregroundStyle(.green.opacity(0.85))
            Text(entry.status == .cleaned ? "No removable metadata found" : "No metadata fields to compare")
                .font(.system(size: 13, weight: .medium))
            Text("This file had little or no EXIF/XMP to strip. Pixels were left unchanged.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var messageBlock: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.status == .failed ? "xmark.octagon.fill" : "slash.circle.fill")
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.status == .failed ? "Could not process this file" : "File was not cleaned")
                    .font(.system(size: 12, weight: .semibold))
                Text(entry.reason ?? "No additional details.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(statusColor.opacity(0.08))
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("Field")
                .frame(width: 110, alignment: .leading)
            Text("Before")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("After")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(MetaBurnTheme.surface.opacity(0.3))
    }

    private func compactRow(_ row: FieldRow) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(row.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            Text(display(row.before))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(display(row.after))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(row.stripped ? MetaBurnTheme.accent : .primary)
                .strikethrough(row.stripped && !row.after.isEmpty, color: MetaBurnTheme.accent.opacity(0.7))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(row.stripped ? MetaBurnTheme.accent.opacity(0.05) : Color.clear)
    }

    private func display(_ value: String) -> String {
        value.isEmpty ? "—" : value
    }

    private var statusBadge: some View {
        Text(entry.status.rawValue.capitalized)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.18))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch entry.status {
        case .cleaned: .green
        case .partial: .orange
        case .skipped: .secondary
        case .failed: .red
        }
    }

    private var outcomeLabel: String {
        switch entry.status {
        case .cleaned: "Saved to Desktop/MetaBurn"
        case .partial: "Partially cleaned"
        case .skipped: "Rejected / skipped"
        case .failed: "Error"
        }
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(MetaBurnTheme.surface)
            .clipShape(Capsule())
    }
}

@MainActor
enum MetadataFieldBuilder {
    private typealias Map = [String: String]

    private struct Spec {
        let label: String
        let mirror: Bool
        let resolve: (Map, String) -> String
    }

    static func buildRows(filePath: String, before: [MetadataEntry], after: [MetadataEntry]) -> [FieldRow] {
        let kind: SupportedTypes.FileKind = SupportedTypes.classify(filePath: filePath).kind
        let isVideo = kind == .video
        let specs = isVideo ? videoSpecs : photoSpecs
        let beforeMap = toMap(before)
        let afterMap = toMap(after)

        return specs.map { spec in
            let beforeValue = spec.resolve(beforeMap, filePath)
            let afterValue = spec.mirror ? beforeValue : spec.resolve(afterMap, filePath)
            return FieldRow(
                label: spec.label,
                before: beforeValue,
                after: afterValue,
                stripped: beforeValue != "" && afterValue == ""
            )
        }
    }

    private static func toMap(_ entries: [MetadataEntry]) -> Map {
        var map: Map = [:]
        for entry in entries {
            if map[entry.tag] == nil { map[entry.tag] = entry.value }
        }
        return map
    }

    private static func get(_ map: Map, _ tags: String...) -> String {
        for tag in tags {
            if let value = map[tag], !value.trimmingCharacters(in: .whitespaces).isEmpty {
                return value.trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    private static func resolution(_ map: Map) -> String {
        if let size = map["ImageSize"], !size.isEmpty { return size }
        let w = get(map, "ImageWidth", "ExifImageWidth", "SourceImageWidth", "PNG:ImageWidth")
        let h = get(map, "ImageHeight", "ExifImageHeight", "SourceImageHeight", "PNG:ImageHeight")
        return w.isEmpty || h.isEmpty ? "" : "\(w) × \(h)"
    }

    private static func camera(_ map: Map) -> String {
        let make = get(map, "Make")
        let model = get(map, "Model", "CameraModelName")
        if !make.isEmpty && !model.isEmpty {
            return model.contains(make) ? model : "\(make) \(model)"
        }
        return model.isEmpty ? make : model
    }

    private static func gps(_ map: Map) -> String {
        get(map, "GPSPosition", "GPSCoordinates", "GPSLatitude", "LocationInformation", "Location", "City", "Sub-location", "Country")
    }

    private static let photoSpecs: [Spec] = [
        Spec(label: "GPS", mirror: false, resolve: { m, _ in gps(m) }),
        Spec(label: "Make", mirror: false, resolve: { m, _ in get(m, "Make") }),
        Spec(label: "Model", mirror: false, resolve: { m, _ in get(m, "Model", "CameraModelName", "HostComputer") }),
        Spec(label: "Camera", mirror: false, resolve: { m, _ in camera(m) }),
        Spec(label: "Software", mirror: false, resolve: { m, _ in get(m, "Software", "HostComputer", "CreatorTool") }),
        Spec(label: "Created", mirror: false, resolve: { m, _ in get(m, "CreateDate", "CreationDate", "DateTimeOriginal", "CreationTime") }),
        Spec(label: "Lens", mirror: false, resolve: { m, _ in get(m, "LensModel", "LensInfo", "LensMake", "Lens") }),
        Spec(label: "Comment", mirror: false, resolve: { m, _ in get(m, "Comment", "Description", "UserComment", "ImageDescription") }),
        Spec(label: "Modified", mirror: true, resolve: { m, _ in get(m, "ModifyDate", "FileModifyDate") }),
        Spec(label: "Size", mirror: true, resolve: { m, _ in get(m, "FileSize") }),
        Spec(label: "Type", mirror: false, resolve: { m, _ in get(m, "FileType", "MIMEType") }),
        Spec(label: "Resolution", mirror: true, resolve: { m, _ in resolution(m) })
    ]

    private static let videoSpecs: [Spec] = [
        Spec(label: "GPS", mirror: false, resolve: { m, _ in gps(m) }),
        Spec(label: "Make", mirror: false, resolve: { m, _ in get(m, "Make") }),
        Spec(label: "Model", mirror: false, resolve: { m, _ in get(m, "Model", "CameraModelName") }),
        Spec(label: "Camera", mirror: false, resolve: { m, _ in camera(m) }),
        Spec(label: "Software", mirror: false, resolve: { m, _ in get(m, "Software", "Encoder", "HandlerDescription") }),
        Spec(label: "Created", mirror: false, resolve: { m, _ in get(m, "CreateDate", "CreationDate") }),
        Spec(label: "Recorded", mirror: false, resolve: { m, _ in get(m, "CreationDate", "MediaCreateDate", "DateTimeOriginal", "CreateDate") }),
        Spec(label: "Codec", mirror: false, resolve: { m, _ in get(m, "CompressorName", "VideoCodec", "CompressorID") }),
        Spec(label: "Audio", mirror: false, resolve: { m, _ in get(m, "AudioFormat", "AudioChannels", "AudioSampleRate", "AudioBitsPerSample") }),
        Spec(label: "Lens", mirror: false, resolve: { m, _ in get(m, "LensModel", "Lens") }),
        Spec(label: "Modified", mirror: true, resolve: { m, _ in get(m, "ModifyDate", "FileModifyDate") }),
        Spec(label: "Size", mirror: true, resolve: { m, _ in get(m, "FileSize") }),
        Spec(label: "Type", mirror: false, resolve: { m, _ in get(m, "FileType", "MIMEType") }),
        Spec(label: "Resolution", mirror: true, resolve: { m, _ in resolution(m) }),
        Spec(label: "Duration", mirror: true, resolve: { m, _ in get(m, "Duration", "MediaDuration", "TrackDuration") }),
        Spec(label: "FPS", mirror: true, resolve: { m, _ in get(m, "VideoFrameRate", "FrameRate") })
    ]
}
