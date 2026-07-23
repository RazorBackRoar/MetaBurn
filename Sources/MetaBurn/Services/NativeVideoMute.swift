import AVFoundation
import Foundation

/// Strip all audio tracks from a video via AVFoundation remux (no ffmpeg).
/// Output replaces the file at `path`. Audio data is omitted — not soft-muted.
enum NativeVideoMute {
    /// - Returns: `(success, reason)` where reason is `"cancelled"` or an error message.
    static func stripAudio(atPath path: String) async -> (success: Bool, reason: String?) {
        if Task.isCancelled {
            return (false, "cancelled")
        }

        let sourceURL = URL(fileURLWithPath: path)
        let ext = sourceURL.pathExtension.lowercased()
        guard let fileType = fileType(forExtension: ext) else {
            return (false, "unsupported container for mute (.\(ext))")
        }

        let tempURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).metaburn.mute.tmp.\(ext)")
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

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if audioTracks.isEmpty {
                return (true, nil)
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
            guard composition.tracks(withMediaType: .video).count > 0 else {
                return (false, "could not build video-only composition")
            }

            try await exportVideoOnly(
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

    private static func fileType(forExtension ext: String) -> AVFileType? {
        switch ext {
        case "mp4": .mp4
        case "m4v": .m4v
        case "mov": .mov
        default: nil
        }
    }

    private static func exportVideoOnly(
        composition: AVMutableComposition,
        to outputURL: URL,
        fileType: AVFileType
    ) async throws {
        // Prefer passthrough (remux, no re-encode). Fall back to a quality preset if needed.
        let presets = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        var lastError: String = "export failed"
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

    private struct ExportFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}

/// Tiny cancel bridge so `onCancel` can call into a non-Sendable export session.
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
