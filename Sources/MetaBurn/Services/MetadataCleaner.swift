import Foundation
import MetaBurnCore

@MainActor
enum MetadataCleaner {
    enum CleanStatus: String, Equatable { case cleaned, skipped, failed, partial }

    /// Copies to a local cache work file, cleans (and optionally mutes) natively, then promotes to Desktop.
    /// Photos: ImageIO. Videos: AVFoundation remux with metadata stripped (optional audio omit).
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

        let metadataBefore = await readMetadata(filePath: filePath, kind: info.kind)

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
            return await cleanPhoto(
                filePath: filePath,
                workURL: workURL,
                workPath: workPath,
                finalURL: finalURL,
                metadataBefore: metadataBefore,
                promoted: &promoted
            )
        }

        return await cleanVideo(
            filePath: filePath,
            workURL: workURL,
            workPath: workPath,
            finalURL: finalURL,
            metadataBefore: metadataBefore,
            muteAudio: muteAudio,
            promoted: &promoted
        )
    }

    private static func cleanPhoto(
        filePath: String,
        workURL: URL,
        workPath: String,
        finalURL: URL,
        metadataBefore: [MetadataEntry],
        promoted: inout Bool
    ) async -> CleanResult {
        if Task.isCancelled {
            return CleanResult(path: filePath, status: .failed, reason: "cancelled", metadataBefore: metadataBefore)
        }

        guard NativeImageIO.canHandle(filePath: filePath), NativeImageIO.stripMetadata(atPath: workPath) else {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: "could not strip photo metadata (ImageIO)",
                metadataBefore: metadataBefore
            )
        }
        if Task.isCancelled {
            return CleanResult(path: filePath, status: .failed, reason: "cancelled", metadataBefore: metadataBefore)
        }
        Log.shared.info(
            "Native ImageIO strip OK: \(URL(fileURLWithPath: filePath).lastPathComponent)",
            scope: "cleaner"
        )

        let metadataAfter = await readMetadata(filePath: workPath, kind: .photo)
        if Task.isCancelled {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: "cancelled",
                metadataBefore: metadataBefore,
                metadataAfter: metadataAfter
            )
        }
        let verified = MetadataRules.verify(
            interpreted: MetadataRules.InterpretResult(outcome: .cleaned),
            kind: .photo,
            before: metadataBefore.map { MetadataRules.Tag(group: $0.group, tag: $0.tag, value: $0.value) },
            after: metadataAfter.map { MetadataRules.Tag(group: $0.group, tag: $0.tag, value: $0.value) }
        )

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

        if Task.isCancelled {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: "cancelled",
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

    private static func cleanVideo(
        filePath: String,
        workURL: URL,
        workPath: String,
        finalURL: URL,
        metadataBefore: [MetadataEntry],
        muteAudio: Bool,
        promoted: inout Bool
    ) async -> CleanResult {
        if Task.isCancelled {
            return CleanResult(path: filePath, status: .failed, reason: "cancelled", metadataBefore: metadataBefore)
        }

        let cleaned = await NativeVideoClean.clean(atPath: workPath, muteAudio: muteAudio)
        if cleaned.reason == "cancelled" {
            return CleanResult(path: filePath, status: .failed, reason: "cancelled", metadataBefore: metadataBefore)
        }
        if !cleaned.success {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: cleaned.reason ?? "AVFoundation clean failed",
                metadataBefore: metadataBefore
            )
        }

        let metadataAfter = await readMetadata(filePath: workPath, kind: .video)
        if Task.isCancelled {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: "cancelled",
                metadataBefore: metadataBefore,
                metadataAfter: metadataAfter
            )
        }
        let verified = MetadataRules.verify(
            interpreted: MetadataRules.InterpretResult(outcome: .cleaned),
            kind: .video,
            before: metadataBefore.map { MetadataRules.Tag(group: $0.group, tag: $0.tag, value: $0.value) },
            after: metadataAfter.map { MetadataRules.Tag(group: $0.group, tag: $0.tag, value: $0.value) }
        )

        var status = CleanStatus(rawValue: verified.outcome) ?? .failed
        var reason = verified.reason
        if status == .cleaned {
            reason = nil
        } else if status == .partial {
            reason = "some removable metadata remains after cleaning"
        } else if status == .failed {
            // Remux succeeded; leftover container dates are expected — treat as cleaned when
            // identifying tags (GPS / make / model / lens) are gone.
            let afterRemovable = MetadataRules.removableTags(
                metadataAfter.map { MetadataRules.Tag(group: $0.group, tag: $0.tag, value: $0.value) },
                kind: .video
            )
            let identifying = afterRemovable.filter { tag in
                let name = tag.tag.lowercased()
                return name.contains("gps")
                    || name.contains("location")
                    || name == "make"
                    || name == "model"
                    || name.contains("lens")
                    || name.contains("artist")
                    || name.contains("comment")
                    || name.contains("description")
            }
            if identifying.isEmpty {
                status = .cleaned
                reason = nil
            }
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

        if Task.isCancelled {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: "cancelled",
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

    private static func promoteWorkFile(_ workURL: URL, to finalURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: finalURL.path) {
            try fm.removeItem(at: finalURL)
        }
        try fm.moveItem(at: workURL, to: finalURL)
    }

    private static func readMetadata(
        filePath: String,
        kind: SupportedTypes.FileKind
    ) async -> [MetadataEntry] {
        if kind == .video {
            return await NativeVideoClean.readEntries(atPath: filePath)
        }
        return NativeImageIO.readEntries(atPath: filePath)
    }
}
