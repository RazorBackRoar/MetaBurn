import Foundation
import MetaBurnCore

@MainActor
enum MetadataCleaner {
    enum CleanStatus: String, Equatable { case cleaned, skipped, failed, partial }

    private static let exiftoolCandidates = ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool"]
    private static let brewCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    private static var cachedExiftoolPath: String? = nil

    static func resolveExiftool() async -> String? {
        if let cached = cachedExiftoolPath { return cached }
        cachedExiftoolPath = await resolveBinary(name: "exiftool", candidates: exiftoolCandidates)
        return cachedExiftoolPath
    }

    static func resolveBrew() async -> String? {
        await resolveBinary(name: "brew", candidates: brewCandidates)
    }

    static func invalidateExiftoolCache() { cachedExiftoolPath = nil }

    private static func resolveBinary(name: String, candidates: [String]) async -> String? {
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) && FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        do {
            let output = try await ProcessRunner.runSimple(executablePath: "/usr/bin/which", arguments: [name], timeout: 5)
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }

    /// Omit all audio tracks via AVFoundation (no ffmpeg). Replaces the file in place.
    static func muteVideo(filePath: String) async -> (success: Bool, reason: String?) {
        await NativeVideoMute.stripAudio(atPath: filePath)
    }

    /// Copies to a local cache work file, cleans/mutes there, then moves to the final Desktop path.
    /// Photos prefer native ImageIO (fast, no ExifTool hang). Videos still use ExifTool.
    /// Mute uses AVFoundation remux (audio omitted from the cleaned copy).
    static func cleanFile(filePath: String, muteAudio: Bool) async -> CleanResult {
        if Task.isCancelled {
            return CleanResult(path: filePath, status: .failed, reason: "cancelled")
        }

        let info = SupportedTypes.classify(filePath: filePath)

        if info.kind == .unsupported {
            return CleanResult(path: filePath, status: .skipped, reason: "unsupported file type")
        }
        if info.kind == .video && !info.writable {
            return CleanResult(path: filePath, status: .skipped, reason: "container not safely writable")
        }

        // Photos can clean with ImageIO alone; videos still need ExifTool.
        let exiftoolPath = await resolveExiftool()
        if info.kind == .video, exiftoolPath == nil {
            return CleanResult(path: filePath, status: .failed, reason: "exiftool not found")
        }

        let outputDir: URL
        if info.kind == .photo {
            Paths.ensurePhotosOutputDirectory()
            outputDir = Paths.photosOutputDirectory()
        } else {
            Paths.ensureVideosOutputDirectory()
            outputDir = Paths.videosOutputDirectory()
        }
        let finalURL = Paths.uniqueOutputURL(forSourcePath: filePath, in: outputDir)
        let workURL = Paths.workURL(forFinal: finalURL)
        let workPath = workURL.path
        let fm = FileManager.default

        var promoted = false
        defer {
            if !promoted {
                try? fm.removeItem(at: workURL)
            }
        }

        // Baseline from the original path so the Before column always reflects the source file.
        let metadataBefore = await readMetadata(
            filePath: filePath,
            kind: info.kind,
            exiftoolPath: exiftoolPath
        )

        do {
            try Task.checkCancellation()
            try fm.copyItem(atPath: filePath, toPath: workPath)
            let stripped = WorkFileSafety.stripStallingXattrs(atPath: workPath)
            if !stripped.isEmpty {
                Log.shared.info(
                    "Stripped stalling xattrs on work file: \(stripped.joined(separator: ", "))",
                    scope: "cleaner"
                )
            }
        } catch is CancellationError {
            return CleanResult(path: filePath, status: .failed, reason: "cancelled", metadataBefore: metadataBefore)
        } catch {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: "could not copy to Desktop/\(Paths.desktopOutputFolderName): \(error.localizedDescription)",
                metadataBefore: metadataBefore
            )
        }

        if info.kind == .photo {
            return await cleanPhotoNativeOrExif(
                filePath: filePath,
                workURL: workURL,
                workPath: workPath,
                finalURL: finalURL,
                metadataBefore: metadataBefore,
                exiftoolPath: exiftoolPath,
                promoted: &promoted
            )
        }

        return await cleanVideoExif(
            filePath: filePath,
            workURL: workURL,
            workPath: workPath,
            finalURL: finalURL,
            metadataBefore: metadataBefore,
            muteAudio: muteAudio,
            exiftoolPath: exiftoolPath!,
            promoted: &promoted
        )
    }

    private static func cleanPhotoNativeOrExif(
        filePath: String,
        workURL: URL,
        workPath: String,
        finalURL: URL,
        metadataBefore: [MetadataEntry],
        exiftoolPath: String?,
        promoted: inout Bool
    ) async -> CleanResult {
        if Task.isCancelled {
            return CleanResult(path: filePath, status: .failed, reason: "cancelled", metadataBefore: metadataBefore)
        }

        var usedNative = false
        if NativeImageIO.canHandle(filePath: filePath), NativeImageIO.stripMetadata(atPath: workPath) {
            usedNative = true
            Log.shared.info("Native ImageIO strip OK: \(URL(fileURLWithPath: filePath).lastPathComponent)", scope: "cleaner")
        } else if let exiftoolPath {
            let stripped = await runExiftoolPhotoStrip(
                exiftoolPath: exiftoolPath,
                workPath: workPath,
                filePath: filePath,
                metadataBefore: metadataBefore
            )
            if case let .failure(result) = stripped { return result }
        } else {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: "could not strip photo metadata (ImageIO failed; ExifTool not installed)",
                metadataBefore: metadataBefore
            )
        }

        var metadataAfter = await readMetadata(filePath: workPath, kind: .photo, exiftoolPath: exiftoolPath)
        var verified = MetadataRules.verify(
            interpreted: MetadataRules.InterpretResult(outcome: .cleaned),
            kind: .photo,
            before: metadataBefore.map { MetadataRules.Tag(group: $0.group, tag: $0.tag, value: $0.value) },
            after: metadataAfter.map { MetadataRules.Tag(group: $0.group, tag: $0.tag, value: $0.value) }
        )

        // Native HEIC rewrite can still leave maker tags — finish with ExifTool when needed.
        if usedNative, verified.outcome != "cleaned", let exiftoolPath {
            Log.shared.info(
                "Native strip left removable tags; ExifTool fallback: \(URL(fileURLWithPath: filePath).lastPathComponent)",
                scope: "cleaner"
            )
            let stripped = await runExiftoolPhotoStrip(
                exiftoolPath: exiftoolPath,
                workPath: workPath,
                filePath: filePath,
                metadataBefore: metadataBefore
            )
            if case let .failure(result) = stripped { return result }
            metadataAfter = await readMetadata(filePath: workPath, kind: .photo, exiftoolPath: exiftoolPath)
            verified = MetadataRules.verify(
                interpreted: MetadataRules.InterpretResult(outcome: .cleaned),
                kind: .photo,
                before: metadataBefore.map { MetadataRules.Tag(group: $0.group, tag: $0.tag, value: $0.value) },
                after: metadataAfter.map { MetadataRules.Tag(group: $0.group, tag: $0.tag, value: $0.value) }
            )
        }

        let status = CleanStatus(rawValue: verified.outcome) ?? .failed
        var reason = verified.reason
        if status == .cleaned {
            reason = nil
        } else if status == .partial {
            reason = "some removable metadata remains after cleaning"
        }

        if status == .failed {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: reason,
                metadataBefore: metadataBefore,
                metadataAfter: metadataAfter
            )
        }

        do {
            try promoteWorkFile(workURL, to: finalURL)
            promoted = true
        } catch {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: "could not finalize cleaned copy: \(error.localizedDescription)",
                metadataBefore: metadataBefore,
                metadataAfter: metadataAfter
            )
        }

        return CleanResult(
            path: finalURL.path,
            status: status,
            reason: reason,
            metadataBefore: metadataBefore,
            metadataAfter: metadataAfter
        )
    }

    private enum ExifStripOutcome {
        case success
        case failure(CleanResult)
    }

    private static func runExiftoolPhotoStrip(
        exiftoolPath: String,
        workPath: String,
        filePath: String,
        metadataBefore: [MetadataEntry]
    ) async -> ExifStripOutcome {
        do {
            try Task.checkCancellation()
            let args = MetadataRules.buildArgs(kind: .photo, filePath: workPath)
            _ = try await ProcessRunner.run(executablePath: exiftoolPath, arguments: args, timeout: 45)
            return .success
        } catch ProcessRunnerError.cancelled {
            return .failure(CleanResult(path: filePath, status: .failed, reason: "cancelled", metadataBefore: metadataBefore))
        } catch is CancellationError {
            return .failure(CleanResult(path: filePath, status: .failed, reason: "cancelled", metadataBefore: metadataBefore))
        } catch ProcessRunnerError.timeout {
            return .failure(CleanResult(
                path: filePath,
                status: .failed,
                reason: "exiftool timed out — work copy discarded",
                metadataBefore: metadataBefore
            ))
        } catch {
            return .failure(CleanResult(
                path: filePath,
                status: .failed,
                reason: error.localizedDescription,
                metadataBefore: metadataBefore
            ))
        }
    }

    private static func cleanVideoExif(
        filePath: String,
        workURL: URL,
        workPath: String,
        finalURL: URL,
        metadataBefore: [MetadataEntry],
        muteAudio: Bool,
        exiftoolPath: String,
        promoted: inout Bool
    ) async -> CleanResult {
        var muteReason: String? = nil
        if muteAudio {
            if Task.isCancelled {
                return CleanResult(path: filePath, status: .failed, reason: "cancelled", metadataBefore: metadataBefore)
            }
            let muted = await muteVideo(filePath: workPath)
            if muted.reason == "cancelled" {
                return CleanResult(path: filePath, status: .failed, reason: "cancelled", metadataBefore: metadataBefore)
            }
            if !muted.success {
                muteReason = "audio removal failed: \(muted.reason ?? "AVFoundation mute failed")"
            }
        }

        do {
            try Task.checkCancellation()
            let args = MetadataRules.buildArgs(kind: .video, filePath: workPath)
            let output = try await ProcessRunner.run(executablePath: exiftoolPath, arguments: args, timeout: 60)
            let metadataAfter = await readMetadata(filePath: workPath, kind: .video, exiftoolPath: exiftoolPath)
            let interpreted = MetadataRules.interpretOutput(
                filePath: workPath,
                output: "\(output.stdout)\n\(output.stderr)"
            )
            let verified = MetadataRules.verify(
                interpreted: interpreted,
                kind: .video,
                before: metadataBefore.map { MetadataRules.Tag(group: $0.group, tag: $0.tag, value: $0.value) },
                after: metadataAfter.map { MetadataRules.Tag(group: $0.group, tag: $0.tag, value: $0.value) }
            )

            var status = CleanStatus(rawValue: verified.outcome) ?? .failed
            var reason = verified.reason
            if status == .partial {
                reason = "some removable metadata remains after cleaning"
            }
            if let muteReason, status == .cleaned {
                status = .partial
                reason = muteReason
            } else if let muteReason, status == .partial {
                reason = [reason, muteReason].compactMap { $0 }.joined(separator: "; ")
            }

            if status == .failed {
                return CleanResult(
                    path: filePath,
                    status: .failed,
                    reason: reason,
                    metadataBefore: metadataBefore,
                    metadataAfter: metadataAfter
                )
            }

            try promoteWorkFile(workURL, to: finalURL)
            promoted = true
            return CleanResult(
                path: finalURL.path,
                status: status,
                reason: reason,
                metadataBefore: metadataBefore,
                metadataAfter: metadataAfter
            )
        } catch ProcessRunnerError.cancelled {
            return CleanResult(path: filePath, status: .failed, reason: "cancelled", metadataBefore: metadataBefore)
        } catch is CancellationError {
            return CleanResult(path: filePath, status: .failed, reason: "cancelled", metadataBefore: metadataBefore)
        } catch ProcessRunnerError.timeout {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: "exiftool timed out — work copy discarded",
                metadataBefore: metadataBefore
            )
        } catch {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: error.localizedDescription,
                metadataBefore: metadataBefore
            )
        }
    }

    private static func promoteWorkFile(_ workURL: URL, to finalURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: finalURL.path) {
            try fm.removeItem(at: finalURL)
        }
        try fm.moveItem(at: workURL, to: finalURL)
    }

    static func installExiftool() async -> (success: Bool, message: String?) {
        guard let brew = await resolveBrew() else {
            return (false, "Homebrew not found. Install ExifTool manually: brew install exiftool")
        }
        do {
            _ = try await ProcessRunner.runSimple(executablePath: brew, arguments: ["install", "exiftool"], timeout: 600)
            invalidateExiftoolCache()
            let found = await resolveExiftool() != nil
            return (found, found ? nil : "exiftool installed but not found on PATH")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private static func readMetadata(
        filePath: String,
        kind: SupportedTypes.FileKind,
        exiftoolPath: String?
    ) async -> [MetadataEntry] {
        if kind == .photo {
            let native = NativeImageIO.readEntries(atPath: filePath)
            if !native.isEmpty { return native }
        }
        guard let exiftoolPath else { return NativeImageIO.readEntries(atPath: filePath) }
        return await readMetadataExiftool(exiftoolPath: exiftoolPath, filePath: filePath)
    }

    private static func readMetadataExiftool(exiftoolPath: String, filePath: String) async -> [MetadataEntry] {
        do {
            let output = try await ProcessRunner.runSimple(
                executablePath: exiftoolPath,
                arguments: ["-G1", "-j", filePath],
                timeout: 30
            )
            guard let data = output.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let record = json.first else { return [] }
            var entries: [MetadataEntry] = []
            let blocklist: Set<String> = [
                "SourceFile", "ExifTool:ExifToolVersion", "System:FileName", "System:Directory",
                "System:FileAccessDate", "System:FileInodeChangeDate", "System:FilePermissions",
                "Warning", "Error"
            ]
            for (key, value) in record {
                if blocklist.contains(key) || value is NSNull { continue }
                let text: String
                if let str = value as? String {
                    text = str
                } else if let arr = value as? [Any] {
                    text = arr.map { String(describing: $0) }.joined(separator: ", ")
                } else {
                    text = String(describing: value)
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let parts = key.split(separator: ":", maxSplits: 1)
                let group = parts.count == 2 ? String(parts[0]) : ""
                let tag = parts.count == 2 ? String(parts[1]) : key
                entries.append(MetadataEntry(group: group, tag: tag, value: trimmed))
            }
            return entries.sorted { "\($0.group):\($0.tag)" < "\($1.group):\($1.tag)" }
        } catch {
            return NativeImageIO.readEntries(atPath: filePath)
        }
    }
}

private extension FileManager {
    func isExecutableFile(atPath path: String) -> Bool {
        guard fileExists(atPath: path) else { return false }
        guard let attributes = try? attributesOfItem(atPath: path),
              let permissions = attributes[.posixPermissions] as? NSNumber else { return false }
        return permissions.int16Value & 0o111 != 0
    }
}
