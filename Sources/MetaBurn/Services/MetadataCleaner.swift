import Foundation
import MetaBurnCore

@MainActor
enum MetadataCleaner {
    enum CleanStatus: String, Equatable { case cleaned, skipped, failed, partial }

    private static let exiftoolCandidates = ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool"]
    private static let ffmpegCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
    private static let brewCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    private static var cachedExiftoolPath: String? = nil
    private static var cachedFfmpegPath: String? = nil

    static func resolveExiftool() async -> String? {
        if let cached = cachedExiftoolPath { return cached }
        cachedExiftoolPath = await resolveBinary(name: "exiftool", candidates: exiftoolCandidates)
        return cachedExiftoolPath
    }

    static func resolveFfmpeg() async -> String? {
        if let cached = cachedFfmpegPath { return cached }
        cachedFfmpegPath = await resolveBinary(name: "ffmpeg", candidates: ffmpegCandidates)
        return cachedFfmpegPath
    }

    static func resolveBrew() async -> String? {
        await resolveBinary(name: "brew", candidates: brewCandidates)
    }

    static func invalidateExiftoolCache() { cachedExiftoolPath = nil }
    static func invalidateFfmpegCache() { cachedFfmpegPath = nil }

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

    static func muteVideo(ffmpegPath: String, filePath: String) async -> (success: Bool, reason: String?) {
        let url = URL(fileURLWithPath: filePath)
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let tempURL = dir.appendingPathComponent(".\(base).muted.tmp.\(ext)")
        let fm = FileManager.default

        do {
            _ = try await ProcessRunner.runSimple(
                executablePath: ffmpegPath,
                arguments: ["-y", "-i", filePath, "-map", "0:v", "-c", "copy", "-an", tempURL.path],
                timeout: 300
            )
            // `moveItem` fails when the destination already exists — replace explicitly.
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            try fm.moveItem(at: tempURL, to: url)
            return (true, nil)
        } catch {
            try? fm.removeItem(at: tempURL)
            return (false, error.localizedDescription)
        }
    }

    /// Copies to a hidden work file, cleans/mutes there, then atomically promotes to the final
    /// Desktop/MetaBurn path. Failures/timeouts delete the work file and never leave a half-written
    /// destination (important for HEIC where ExifTool may hang mid-`-overwrite_original`).
    static func cleanFile(filePath: String, muteAudio: Bool, ffmpegPath: String?) async -> CleanResult {
        let info = SupportedTypes.classify(filePath: filePath)

        if info.kind == .unsupported {
            return CleanResult(path: filePath, status: .skipped, reason: "unsupported file type")
        }
        if info.kind == .video && !info.writable {
            return CleanResult(path: filePath, status: .skipped, reason: "container not safely writable by ExifTool")
        }

        guard let exiftoolPath = await resolveExiftool() else {
            return CleanResult(path: filePath, status: .failed, reason: "exiftool not found")
        }

        Paths.ensureDesktopOutputDirectories()
        let outputDir = info.kind == .photo ? Paths.photosOutputDirectory() : Paths.videosOutputDirectory()
        let finalURL = Paths.uniqueOutputURL(forSourcePath: filePath, in: outputDir)
        let workURL = Paths.workURL(forFinal: finalURL)
        let workPath = workURL.path
        let fm = FileManager.default

        do {
            try fm.copyItem(atPath: filePath, toPath: workPath)
        } catch {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: "could not copy to Desktop/\(Paths.desktopOutputFolderName): \(error.localizedDescription)"
            )
        }

        let metadataBefore = await readMetadata(exiftoolPath: exiftoolPath, filePath: workPath)

        var muteReason: String? = nil
        if muteAudio && info.kind == .video {
            let resolvedFfmpeg: String?
            if let path = ffmpegPath {
                resolvedFfmpeg = path
            } else {
                resolvedFfmpeg = await resolveFfmpeg()
            }
            if let ffmpeg = resolvedFfmpeg {
                let muted = await muteVideo(ffmpegPath: ffmpeg, filePath: workPath)
                if !muted.success {
                    muteReason = "audio removal failed: \(muted.reason ?? "ffmpeg failed")"
                }
            } else {
                muteReason = "ffmpeg not installed — audio not removed"
            }
        }

        let args = MetadataRules.buildArgs(kind: info.kind, filePath: workPath)
        do {
            let output = try await ProcessRunner.run(
                executablePath: exiftoolPath,
                arguments: args,
                timeout: 60
            )
            let metadataAfter = await readMetadata(exiftoolPath: exiftoolPath, filePath: workPath)
            let interpreted = MetadataRules.interpretOutput(
                filePath: workPath,
                output: "\(output.stdout)\n\(output.stderr)"
            )
            let verified = MetadataRules.verify(
                interpreted: interpreted,
                kind: info.kind,
                before: metadataBefore.map { MetadataRules.Tag(group: $0.group, tag: $0.tag, value: $0.value) },
                after: metadataAfter.map { MetadataRules.Tag(group: $0.group, tag: $0.tag, value: $0.value) }
            )

            var status = CleanStatus(rawValue: verified.outcome) ?? .failed
            var reason = verified.reason

            if let muteReason, status == .cleaned {
                status = .partial
                reason = muteReason
            } else if let muteReason, status == .partial {
                reason = [reason, muteReason].compactMap { $0 }.joined(separator: "; ")
            }

            if status == .failed {
                try? fm.removeItem(at: workURL)
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
            } catch {
                try? fm.removeItem(at: workURL)
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
        } catch ProcessRunnerError.timeout {
            try? fm.removeItem(at: workURL)
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: "exiftool timed out — work copy discarded (destination untouched)",
                metadataBefore: metadataBefore,
                metadataAfter: []
            )
        } catch {
            try? fm.removeItem(at: workURL)
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: error.localizedDescription,
                metadataBefore: metadataBefore,
                metadataAfter: []
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

    static func installFfmpeg() async -> (success: Bool, message: String?) {
        guard let brew = await resolveBrew() else {
            return (false, "Homebrew not found. Install ffmpeg manually: brew install ffmpeg")
        }
        do {
            _ = try await ProcessRunner.runSimple(executablePath: brew, arguments: ["install", "ffmpeg"], timeout: 600)
            invalidateFfmpegCache()
            let found = await resolveFfmpeg() != nil
            return (found, found ? nil : "ffmpeg installed but not found on PATH")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private static func readMetadata(exiftoolPath: String, filePath: String) async -> [MetadataEntry] {
        do {
            let output = try await ProcessRunner.runSimple(executablePath: exiftoolPath, arguments: ["-G1", "-j", filePath], timeout: 60)
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
            return []
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
