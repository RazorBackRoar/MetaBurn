import Foundation
import MetaBurnCore

enum MetadataCleaner {
    enum CleanStatus: String, Equatable { case cleaned, skipped, failed, partial }

    /// Materializes source (iCloud-safe), cleans natively into a local cache work file, then promotes.
    /// Photos: ImageIO (HEIC/HEIF → stripped max-quality JPEG in one pass). Videos: AVFoundation remux.
    static func cleanFile(
        filePath: String,
        muteAudio: Bool,
        outputDestination: OutputDestination = OutputPreference.stored
    ) async -> CleanResult {
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

        do {
            try PathSafety.assertRegularFileNoFollow(at: filePath)
        } catch PathSafetyError.symlink(_) {
            return CleanResult(path: filePath, status: .skipped, reason: "symlink skipped for safety")
        } catch {
            return CleanResult(path: filePath, status: .failed, reason: "could not open source file")
        }

        let convertHeic = info.kind == .photo && HeicJpegConverter.shouldConvert(filePath: filePath)

        do {
            if UbiquityGate.needsDownload(atPath: filePath) {
                try await UbiquityGate.ensureDownloaded(atPath: filePath)
            }
        } catch is CancellationError {
            return CleanResult(path: filePath, status: .failed, reason: "cancelled")
        } catch let gate as UbiquityGate.GateError {
            return CleanResult(path: filePath, status: .failed, reason: gate.userMessage)
        } catch {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: "iCloud download failed: \(error.localizedDescription)"
            )
        }

        do {
            if info.kind == .photo {
                try OutputRootResolver.ensurePhotosDirectory(forSourcePath: filePath, destination: outputDestination)
            } else {
                try OutputRootResolver.ensureVideosDirectory(forSourcePath: filePath, destination: outputDestination)
            }
        } catch PathSafetyError.symlink(_) {
            return CleanResult(path: filePath, status: .failed, reason: "output path is a symlink")
        } catch {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: "could not create output folder: \(error.localizedDescription)"
            )
        }

        let outputDir = info.kind == .photo
            ? OutputRootResolver.photosDirectory(forSourcePath: filePath, destination: outputDestination)
            : OutputRootResolver.videosDirectory(forSourcePath: filePath, destination: outputDestination)
        let sourceDir = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        if !PathSafety.isPhysicallyInside(outputDir.path, ancestor: sourceDir) {
            return CleanResult(path: filePath, status: .failed, reason: "output path is outside the source folder")
        }

        let finalURL: URL
        if convertHeic {
            finalURL = OutputNaming.uniqueURL(
                forSourcePath: filePath,
                in: outputDir,
                replacingExtension: HeicRules.jpegExtension
            )
        } else {
            finalURL = Paths.uniqueOutputURL(forSourcePath: filePath, in: outputDir)
        }
        let workURL = Paths.workURL(forFinal: finalURL)
        let workPath = workURL.path

        var promoted = false
        defer {
            if !promoted {
                cleanupTemporaryFile(at: workURL)
            }
        }

        let metadataBefore = await readMetadata(filePath: filePath, kind: info.kind)

        do {
            try PathSafety.assertRegularFileNoFollow(at: filePath)
            try Task.checkCancellation()

            if convertHeic {
                // Phase D: single-pass JPEG+strip. Materialize iCloud HEIC to cache first.
                var heicStage: URL?
                defer {
                    if let heicStage {
                        cleanupTemporaryFile(at: heicStage)
                    }
                }

                let convertSource: String
                if UbiquityGate.isUbiquitous(atPath: filePath) || UbiquityGate.needsDownload(atPath: filePath) {
                    let stage = Paths.workURL(
                        forFinal: URL(fileURLWithPath: filePath)
                            .deletingPathExtension()
                            .appendingPathExtension("heic")
                    )
                    heicStage = stage
                    try await stageSource(filePath: filePath, to: stage)
                    _ = WorkFileSafety.stripStallingXattrs(atPath: stage.path)
                    convertSource = stage.path
                } else {
                    convertSource = filePath
                }

                switch HeicJpegConverter.convertAndStrip(from: convertSource, to: workURL) {
                case .success:
                    logInfo(
                        "HEIC→JPEG strip OK: \(URL(fileURLWithPath: filePath).lastPathComponent) → \(workURL.lastPathComponent)"
                    )
                case .failure(let error):
                    return CleanResult(
                        path: filePath,
                        status: .failed,
                        reason: heicFailureReason(error),
                        metadataBefore: metadataBefore
                    )
                }
                _ = WorkFileSafety.stripStallingXattrs(atPath: workPath)

                return await finishPhoto(
                    filePath: filePath,
                    workURL: workURL,
                    workPath: workPath,
                    finalURL: finalURL,
                    metadataBefore: metadataBefore,
                    alreadyStripped: true,
                    promoted: &promoted
                )
            }

            try await stageSource(filePath: filePath, to: workURL)
            let stripped = WorkFileSafety.stripStallingXattrs(atPath: workPath)
            if !stripped.isEmpty {
                logInfo(
                    "Stripped stalling xattrs on work file: \(stripped.joined(separator: ", "))"
                )
            }
        } catch is CancellationError {
            return CleanResult(path: filePath, status: .failed, reason: "cancelled", metadataBefore: metadataBefore)
        } catch let gate as UbiquityGate.GateError {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: gate.userMessage,
                metadataBefore: metadataBefore
            )
        } catch {
            return CleanResult(
                path: filePath,
                status: .failed,
                reason: "could not stage work file: \(error.localizedDescription)",
                metadataBefore: metadataBefore
            )
        }

        if info.kind == .photo {
            return await finishPhoto(
                filePath: filePath,
                workURL: workURL,
                workPath: workPath,
                finalURL: finalURL,
                metadataBefore: metadataBefore,
                alreadyStripped: false,
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

    /// Coordinated iCloud-safe copy into a local cache URL (or plain copy for local files).
    private static func stageSource(filePath: String, to destinationURL: URL) async throws {
        if UbiquityGate.isUbiquitous(atPath: filePath) || UbiquityGate.needsDownload(atPath: filePath) {
            try await UbiquityGate.materialize(fromPath: filePath, to: destinationURL)
        } else {
            safeRemove(at: destinationURL)
            try PathSafety.copyNoFollow(from: filePath, to: destinationURL)
        }
    }

    private static func heicFailureReason(_ error: HeicJpegConverter.ConversionError) -> String {
        switch error {
        case .unreadable:
            return "could not read HEIC/HEIF for JPEG conversion"
        case .notHeif:
            return "file is not a HEIC/HEIF image"
        case .destinationFailed:
            return "could not create JPEG destination for HEIC conversion"
        case .finalizeFailed:
            return "HEIC→JPEG conversion failed (Image I/O)"
        }
    }

    private static func finishPhoto(
        filePath: String,
        workURL: URL,
        workPath: String,
        finalURL: URL,
        metadataBefore: [MetadataEntry],
        alreadyStripped: Bool,
        promoted: inout Bool
    ) async -> CleanResult {
        if Task.isCancelled {
            return CleanResult(path: filePath, status: .failed, reason: "cancelled", metadataBefore: metadataBefore)
        }

        if !alreadyStripped {
            guard NativeImageIO.canHandle(filePath: filePath), NativeImageIO.stripMetadata(atPath: workPath) else {
                return CleanResult(
                    path: filePath,
                    status: .failed,
                    reason: "could not strip photo metadata (ImageIO)",
                    metadataBefore: metadataBefore
                )
            }
            logInfo(
                "Native ImageIO strip OK: \(URL(fileURLWithPath: filePath).lastPathComponent)"
            )
        }

        let metadataAfter = await readMetadata(filePath: workPath, kind: .photo)
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
        if PathSafety.isSymlink(finalURL.path) {
            throw PathSafetyError.symlink(finalURL.path)
        }
        let parent = finalURL.deletingLastPathComponent()
        try PathSafety.ensureDirectoryNoFollow(parent, within: parent.path)
        let fm = FileManager.default

        let destIsICloud = UbiquityGate.isUbiquitous(atPath: finalURL.path)
            || OutputRootResolver.pathLooksLikeICloud(finalURL)

        if destIsICloud {
            try promoteICloudWorkFile(workURL, to: finalURL)
            return
        }

        safeRemove(at: finalURL)
        try fm.moveItem(at: workURL, to: finalURL)
    }

    private static func promoteICloudWorkFile(_ workURL: URL, to finalURL: URL) throws {
        let fm = FileManager.default
        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: finalURL,
            options: .forReplacing,
            error: &coordinatorError
        ) { writeURL in
            do {
                safeRemove(at: writeURL)
                // Copy then remove work — move can fail across volumes / iCloud.
                try fm.copyItem(at: workURL, to: writeURL)
                cleanupTemporaryFile(at: workURL)
            } catch {
                writeError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
    }

    private static func cleanupTemporaryFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            logDebug("Deleted temporary file: \(url.path)")
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError {
                // Ignore if file doesn't exist anymore
            } else {
                logError("Failed to delete temporary file: \(error.localizedDescription)")
            }
        }
    }

    private static func safeRemove(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError {
                // Ignore if file doesn't exist
            } else {
                logWarn("Could not safely remove file at \(url.path): \(error.localizedDescription)")
            }
        }
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

    private static func logInfo(_ message: String) {
        Task { @MainActor in Log.shared.info(message, scope: "cleaner") }
    }

    private static func logDebug(_ message: String) {
        Task { @MainActor in Log.shared.debug(message, scope: "cleaner") }
    }

    private static func logWarn(_ message: String) {
        Task { @MainActor in Log.shared.warn(message, scope: "cleaner") }
    }

    private static func logError(_ message: String) {
        Task { @MainActor in Log.shared.error(message, scope: "cleaner") }
    }
}
