import SwiftUI

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

    private var rows: [FieldRow] {
        MetadataFieldBuilder.buildRows(
            filePath: entry.path,
            before: entry.metadataBefore,
            after: entry.metadataAfter
        )
    }

    private var strippedCount: Int {
        rows.filter(\.stripped).count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(MetaBurnTheme.divider)
            if entry.status == .failed || entry.status == .skipped {
                messageBlock
                Divider().overlay(MetaBurnTheme.divider)
            }
            columnHeaders
            Divider().overlay(MetaBurnTheme.divider)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        fieldRow(row)
                        Divider().overlay(MetaBurnTheme.divider.opacity(0.6))
                    }
                }
            }
        }
        .background(MetaBurnTheme.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(fileName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                statusBadge
            }

            Text(directory)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(entry.path)

            HStack(spacing: 8) {
                metaChip("\(ext) · \(kind)")
                metaChip(outcomeLabel)
                if strippedCount > 0 {
                    metaChip("\(strippedCount) fields removed")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MetaBurnTheme.surface.opacity(0.55))
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
        .padding(12)
        .background(statusColor.opacity(0.08))
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("Before")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("After")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(MetaBurnTheme.surface.opacity(0.35))
    }

    private func fieldRow(_ row: FieldRow) -> some View {
        HStack(alignment: .top, spacing: 0) {
            valueColumn(label: row.label, value: row.before, removed: false)
            valueColumn(label: row.label, value: row.after, removed: row.stripped)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    private func valueColumn(label: String, value: String, removed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(removed ? MetaBurnTheme.accent : .primary)
                .strikethrough(removed && !value.isEmpty, color: MetaBurnTheme.accent.opacity(0.8))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusBadge: some View {
        Text(entry.status.rawValue.capitalized)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
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
        case .cleaned: "Modified in place"
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
            .padding(.vertical, 3)
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
        let w = get(map, "ImageWidth", "ExifImageWidth", "SourceImageWidth")
        let h = get(map, "ImageHeight", "ExifImageHeight", "SourceImageHeight")
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
        Spec(label: "Model", mirror: false, resolve: { m, _ in get(m, "Model", "CameraModelName", "HostComputer") }),
        Spec(label: "Make", mirror: false, resolve: { m, _ in get(m, "Make") }),
        Spec(label: "File Size", mirror: true, resolve: { m, _ in get(m, "FileSize") }),
        Spec(label: "File Type", mirror: false, resolve: { m, _ in get(m, "FileType", "MIMEType") }),
        Spec(label: "Resolution", mirror: false, resolve: { m, _ in resolution(m) }),
        Spec(label: "Date Created", mirror: false, resolve: { m, _ in get(m, "CreateDate", "CreationDate", "DateTimeOriginal") }),
        Spec(label: "Date Modified", mirror: true, resolve: { m, _ in get(m, "ModifyDate", "FileModifyDate") }),
        Spec(label: "Camera", mirror: false, resolve: { m, _ in camera(m) }),
        Spec(label: "Lens", mirror: false, resolve: { m, _ in get(m, "LensModel", "LensInfo", "LensMake", "Lens") }),
        Spec(label: "Software", mirror: false, resolve: { m, _ in get(m, "Software", "HostComputer") })
    ]

    private static let videoSpecs: [Spec] = [
        Spec(label: "FPS", mirror: false, resolve: { m, _ in get(m, "VideoFrameRate", "FrameRate") }),
        Spec(label: "GPS", mirror: false, resolve: { m, _ in gps(m) }),
        Spec(label: "Model", mirror: false, resolve: { m, _ in get(m, "Model", "CameraModelName") }),
        Spec(label: "Make", mirror: false, resolve: { m, _ in get(m, "Make") }),
        Spec(label: "File Size", mirror: true, resolve: { m, _ in get(m, "FileSize") }),
        Spec(label: "File Type", mirror: false, resolve: { m, _ in get(m, "FileType", "MIMEType") }),
        Spec(label: "Resolution", mirror: false, resolve: { m, _ in resolution(m) }),
        Spec(label: "Duration", mirror: false, resolve: { m, _ in get(m, "Duration", "MediaDuration", "TrackDuration") }),
        Spec(label: "Date Created", mirror: false, resolve: { m, _ in get(m, "CreateDate", "CreationDate") }),
        Spec(label: "Date Modified", mirror: true, resolve: { m, _ in get(m, "ModifyDate", "FileModifyDate") }),
        Spec(label: "Date Recorded", mirror: false, resolve: { m, _ in get(m, "CreationDate", "MediaCreateDate", "DateTimeOriginal", "CreateDate") }),
        Spec(label: "Camera", mirror: false, resolve: { m, _ in camera(m) }),
        Spec(label: "Lens", mirror: false, resolve: { m, _ in get(m, "LensModel", "Lens") }),
        Spec(label: "Video Codec", mirror: false, resolve: { m, _ in get(m, "CompressorName", "VideoCodec", "CompressorID") }),
        Spec(label: "Audio / Sound", mirror: false, resolve: { m, _ in get(m, "AudioFormat", "AudioChannels", "AudioSampleRate", "AudioBitsPerSample") }),
        Spec(label: "Software", mirror: false, resolve: { m, _ in get(m, "Software", "Encoder", "HandlerDescription") })
    ]
}
