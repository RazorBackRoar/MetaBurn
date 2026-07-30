import Foundation

/// Ensures iCloud Drive (ubiquitous) items are local before MetaBurn reads them.
/// Mutations always happen on local cache copies — never mid-write on iCloud paths.
enum UbiquityGate {
    enum GateError: Error, Equatable {
        case cancelled
        case timedOut
        case downloadFailed(String)
        case copyFailed(String)
        case unavailableOffline
    }

    private static let defaultTimeout: TimeInterval = 300
    private static let pollIntervalNanos: UInt64 = 250_000_000

    /// True when the item is ubiquitous and not yet fully downloaded.
    static func needsDownload(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]) else {
            return false
        }
        guard values.isUbiquitousItem == true else { return false }
        return values.ubiquitousItemDownloadingStatus != .current
    }

    static func isUbiquitous(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
            || OutputRootResolver.pathLooksLikeICloud(url)
    }

    /// Download if needed, then coordinated-copy bytes into `destinationURL` (local cache).
    static func materialize(
        fromPath path: String,
        to destinationURL: URL,
        timeout: TimeInterval = defaultTimeout
    ) async throws {
        try Task.checkCancellation()
        let sourceURL = URL(fileURLWithPath: path)

        if needsDownload(atPath: path) {
            try await downloadUntilCurrent(url: sourceURL, timeout: timeout)
        }

        try Task.checkCancellation()
        try coordinatedCopy(from: sourceURL, to: destinationURL)
    }

    /// Wait until a ubiquitous item is current (or throw).
    static func ensureDownloaded(atPath path: String, timeout: TimeInterval = defaultTimeout) async throws {
        guard needsDownload(atPath: path) else { return }
        try await downloadUntilCurrent(url: URL(fileURLWithPath: path), timeout: timeout)
    }

    // MARK: - Private

    private static func downloadUntilCurrent(url: URL, timeout: TimeInterval) async throws {
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            // Already local / not ubiquitous — treat as OK if status is current next.
            await MainActor.run {
                Log.shared.warn(
                    "startDownloadingUbiquitousItem: \(error.localizedDescription)",
                    scope: "ubiquity"
                )
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()

            let values = try? url.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey,
                .ubiquitousItemDownloadingErrorKey
            ])

            if let err = values?.ubiquitousItemDownloadingError {
                throw GateError.downloadFailed(err.localizedDescription)
            }
            if values?.ubiquitousItemDownloadingStatus == .current {
                return
            }

            // Offline with no progress — fail fast when not downloading.
            if values?.ubiquitousItemIsDownloading != true,
               values?.ubiquitousItemDownloadingStatus == .notDownloaded {
                // Keep polling briefly; iCloud may not set isDownloading immediately.
            }

            try await Task.sleep(nanoseconds: pollIntervalNanos)
        }

        let final = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if final?.ubiquitousItemDownloadingStatus == .current {
            return
        }
        throw GateError.timedOut
    }

    private static func coordinatedCopy(from sourceURL: URL, to destinationURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        Paths.ensureDirectory(destinationURL.deletingLastPathComponent())

        var coordinatorError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinatorError) { readURL in
            do {
                try fm.copyItem(at: readURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }
        if let coordinatorError {
            throw GateError.copyFailed(coordinatorError.localizedDescription)
        }
        if let copyError {
            throw GateError.copyFailed(copyError.localizedDescription)
        }
        guard fm.fileExists(atPath: destinationURL.path) else {
            throw GateError.copyFailed("coordinated copy produced no file")
        }
    }
}

extension UbiquityGate.GateError {
    var userMessage: String {
        switch self {
        case .cancelled:
            return "cancelled"
        case .timedOut:
            return "timed out waiting for iCloud download"
        case .downloadFailed(let detail):
            return "iCloud download failed: \(detail)"
        case .copyFailed(let detail):
            return "could not read iCloud file: \(detail)"
        case .unavailableOffline:
            return "iCloud file unavailable offline"
        }
    }
}
