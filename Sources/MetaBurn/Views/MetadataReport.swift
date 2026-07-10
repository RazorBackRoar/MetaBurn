import SwiftUI

struct MetadataReport: View {
    let entry: LogEntry

    private var fileName: String {
        URL(fileURLWithPath: entry.path).lastPathComponent
    }

    private var kind: String {
        SupportedTypes.isVideo(filePath: entry.path) ? "Video" : "Photo"
    }

    private var ext: String {
        (entry.path as NSString).pathExtension.uppercased()
    }

    private var rows: [FieldRow] {
        MetadataFieldBuilder.buildRows(
            filePath: entry.path,
            before: entry.metadataBefore,
            after: entry.metadataAfter
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            sectionTitle
            columnHeaders
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                    ForEach(rows) { row in
                        metaCell(label: row.label, value: row.before, tone: row.stripped ? .removed : .normal, leftBorder: false)
                        metaCell(label: row.label, value: row.after, tone: .normal, leftBorder: true)
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(fileName)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            HStack(spacing: 8) {
                statusBadge
                Text("\(ext.isEmpty ? "—" : ext) · \(kind)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            if let reason = entry.reason {
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
        .overlay(Divider(), alignment: .bottom)
    }

    private var statusBadge: some View {
        Text(entry.status.rawValue)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15))
            .foregroundColor(statusColor)
            .cornerRadius(4)
    }

    private var statusColor: Color {
        switch entry.status {
        case .cleaned: .green
        case .partial: .orange
        case .skipped: .gray
        case .failed: .red
        }
    }

    private var sectionTitle: some View {
        Text("\(kind) Metadata")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.05))
            .overlay(Divider(), alignment: .bottom)
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            columnHeader("Before Burn")
            Divider()
            columnHeader("After Burn")
        }
        .frame(height: 36)
        .background(Color.gray.opacity(0.05))
        .overlay(Divider(), alignment: .bottom)
    }

    private func columnHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Rectangle()
                .fill(Color.green)
                .frame(height: 2)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func metaCell(label: String, value: String, tone: Tone, leftBorder: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(value.isEmpty ? "Empty" : value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tone == .removed ? .red : .primary)
                .lineLimit(nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(leftBorder ? Color.gray.opacity(0.04) : Color.clear)
        .overlay(
            leftBorder ? Divider().offset(x: -1) : nil,
            alignment: .leading
        )
        .overlay(Divider(), alignment: .bottom)
    }

    enum Tone { case normal, removed }
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
