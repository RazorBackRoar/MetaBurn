import AVFoundation
import Foundation

/// Native AVFoundation video clean: strip container metadata and optionally omit all audio.
/// Replaces the file at `path`. Passthrough remux when possible (no quality loss).
enum NativeVideoClean {
    /// - Parameters:
    ///   - muteAudio: when true, omit every audio track from the cleaned copy.
    static func clean(atPath path: String, muteAudio: Bool) async -> (success: Bool, reason: String?) {
        if Task.isCancelled {
            return (false, "cancelled")
        }

        let sourceURL = URL(fileURLWithPath: path)
        let ext = sourceURL.pathExtension.lowercased()
        guard let fileType = fileType(forExtension: ext) else {
            return (false, "unsupported container (.\(ext))")
        }

        let tempURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).metaburn.video.tmp.\(ext)")
        let fm = FileManager.default
        var replaced = false
        defer {
            if !replaced {
                try? fm.removeItem(at: tempURL)
            }
        }

        do {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: sourceURL)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard !videoTracks.isEmpty else {
                return (false, "no video track")
            }

            let duration = try await asset.load(.duration)
            let composition = AVMutableComposition()

            for track in videoTracks {
                guard let compTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { continue }
                try compTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: track,
                    at: .zero
                )
                if let transform = try? await track.load(.preferredTransform) {
                    compTrack.preferredTransform = transform
                }
            }
            guard !composition.tracks(withMediaType: .video).isEmpty else {
                return (false, "could not build video composition")
            }

            if !muteAudio {
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                for track in audioTracks {
                    guard let compTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    ) else { continue }
                    try? compTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: duration),
                        of: track,
                        at: .zero
                    )
                }
            }

            try await exportStripped(
                composition: composition,
                to: tempURL,
                fileType: fileType
            )

            try Task.checkCancellation()
            if fm.fileExists(atPath: sourceURL.path) {
                try fm.removeItem(at: sourceURL)
            }
            try fm.moveItem(at: tempURL, to: sourceURL)
            replaced = true
            return (true, nil)
        } catch is CancellationError {
            return (false, "cancelled")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Read display metadata without ExifTool (AVFoundation + filesystem).
    static func readEntries(atPath path: String) async -> [MetadataEntry] {
        var entries: [MetadataEntry] = fileSystemEntries(atPath: path)
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)

        do {
            if let tracks = try? await asset.loadTracks(withMediaType: .video),
               let track = tracks.first {
                if let size = try? await track.load(.naturalSize), size.width > 0, size.height > 0 {
                    let transform = (try? await track.load(.preferredTransform)) ?? .identity
                    let rect = CGRect(origin: .zero, size: size).applying(transform)
                    let w = Int(abs(rect.width).rounded())
                    let h = Int(abs(rect.height).rounded())
                    entries.append(MetadataEntry(group: "Video", tag: "ImageWidth", value: "\(w)"))
                    entries.append(MetadataEntry(group: "Video", tag: "ImageHeight", value: "\(h)"))
                    entries.append(MetadataEntry(group: "Video", tag: "ImageSize", value: "\(w)x\(h)"))
                }
                if let fps = try? await track.load(.nominalFrameRate), fps > 0 {
                    entries.append(MetadataEntry(group: "Video", tag: "VideoFrameRate", value: String(format: "%.3f", fps)))
                }
            }

            if let duration = try? await asset.load(.duration), duration.isNumeric, duration.seconds > 0 {
                entries.append(MetadataEntry(group: "Video", tag: "Duration", value: formatDuration(duration.seconds)))
            }

            let metadata = try await asset.load(.metadata)
            for item in metadata {
                guard let value = try? await item.load(.stringValue),
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let key = (item.commonKey?.rawValue ?? item.identifier?.rawValue ?? "Meta").trimmingCharacters(in: .whitespaces)
                let tag = friendlyTag(for: key)
                let group = groupFor(key: key)
                if !entries.contains(where: { $0.group == group && $0.tag == tag }) {
                    entries.append(MetadataEntry(group: group, tag: tag, value: value))
                }
            }

            // Common keys sometimes only appear under availableMetadataFormats.
            let formats = try await asset.load(.availableMetadataFormats)
            for format in formats {
                let items = try await asset.loadMetadata(for: format)
                for item in items {
                    guard let value = try? await item.load(.stringValue),
                          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let key = (item.commonKey?.rawValue ?? item.identifier?.rawValue ?? "Meta")
                    let tag = friendlyTag(for: key)
                    let group = groupFor(key: key)
                    if !entries.contains(where: { $0.group == group && $0.tag == tag }) {
                        entries.append(MetadataEntry(group: group, tag: tag, value: value))
                    }
                }
            }
        } catch {
            // Filesystem entries alone are still useful for the table.
        }

        let ext = (path as NSString).pathExtension.uppercased()
        if !ext.isEmpty {
            entries.append(MetadataEntry(group: "File", tag: "FileType", value: ext))
        }
        return entries
    }

    private static func fileType(forExtension ext: String) -> AVFileType? {
        switch ext {
        case "mp4": .mp4
        case "m4v": .m4v
        case "mov": .mov
        default: nil
        }
    }

    private static func exportStripped(
        composition: AVMutableComposition,
        to outputURL: URL,
        fileType: AVFileType
    ) async throws {
        let presets = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        var lastError = "export failed"
        for preset in presets {
            guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
                continue
            }
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            session.outputURL = outputURL
            session.outputFileType = fileType
            session.shouldOptimizeForNetworkUse = false
            // Drop identifying / location / creation metadata from the remuxed file.
            session.metadata = []
            session.metadataItemFilter = .forSharing()

            do {
                let canceller = ExportCanceller(session)
                try await withTaskCancellationHandler {
                    try await runExport(session)
                } onCancel: {
                    canceller.cancel()
                }
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error.localizedDescription
                try? FileManager.default.removeItem(at: outputURL)
                continue
            }
        }
        throw ExportFailure(message: lastError)
    }

    private static func runExport(_ session: AVAssetExportSession) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }
        if Task.isCancelled || session.status == .cancelled {
            throw CancellationError()
        }
        switch session.status {
        case .completed:
            return
        case .failed:
            throw ExportFailure(message: session.error?.localizedDescription ?? "export failed")
        case .cancelled:
            throw CancellationError()
        default:
            throw ExportFailure(message: "unexpected export status")
        }
    }

    private static func fileSystemEntries(atPath path: String) -> [MetadataEntry] {
        var entries: [MetadataEntry] = []
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? NSNumber {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            entries.append(MetadataEntry(group: "File", tag: "FileSize", value: formatter.string(fromByteCount: size.int64Value)))
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let date = attrs[.modificationDate] as? Date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            entries.append(MetadataEntry(group: "File", tag: "FileModifyDate", value: formatter.string(from: date)))
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let date = attrs[.creationDate] as? Date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            entries.append(MetadataEntry(group: "File", tag: "CreateDate", value: formatter.string(from: date)))
            entries.append(MetadataEntry(group: "QuickTime", tag: "CreationDate", value: formatter.string(from: date)))
        }
        return entries
    }

    private static func friendlyTag(for key: String) -> String {
        let lower = key.lowercased()
        if lower.contains("creationdate") || lower.contains("createdate") || lower == "creationdate" {
            return "CreateDate"
        }
        if lower.contains("location") || lower.contains("gps") {
            return "GPSPosition"
        }
        if lower.contains("make") { return "Make" }
        if lower.contains("model") { return "Model" }
        if lower.contains("software") { return "Software" }
        if lower.contains("description") || lower.contains("comment") { return "Comment" }
        if lower.contains("artist") || lower.contains("author") { return "Artist" }
        // Last path component of identifiers like "mdta/com.apple.quicktime.location.ISO6709"
        if let last = key.split(separator: "/").last {
            return String(last)
        }
        return key
    }

    private static func groupFor(key: String) -> String {
        let lower = key.lowercased()
        if lower.contains("gps") || lower.contains("location") { return "GPS" }
        if lower.contains("quicktime") || lower.contains("mdta") { return "QuickTime" }
        return "EXIF"
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private struct ExportFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}

private final class ExportCanceller: @unchecked Sendable {
    private let lock = NSLock()
    private var session: AVAssetExportSession?

    init(_ session: AVAssetExportSession) {
        self.session = session
    }

    func cancel() {
        lock.lock()
        let current = session
        lock.unlock()
        current?.cancelExport()
    }
}
