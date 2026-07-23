import Foundation
import MetaBurnCore

typealias FileKind = SupportedTypes.FileKind
typealias FileClassification = SupportedTypes.FileClassification
typealias CleanStatus = MetadataCleaner.CleanStatus

enum RunState: String, Equatable {
    case waiting, scanning, cleaning, done, failed, cancelled
}

struct Counters: Equatable {
    var supported = 0
    var cleaned = 0
    var skipped = 0
    var failed = 0
    var partial = 0
}

/// Per-kind totals discovered during scan, plus how many have finished cleaning.
struct TypeCounts: Equatable {
    var images = 0
    var videos = 0
    var other = 0
    var imagesDone = 0
    var videosDone = 0
    var otherDone = 0

    var hasAny: Bool { images > 0 || videos > 0 || other > 0 }

    mutating func recordTotal(for path: String) {
        switch SupportedTypes.classify(filePath: path).kind {
        case .photo: images += 1
        case .video: videos += 1
        case .unsupported: other += 1
        }
    }

    mutating func recordDone(for path: String) {
        switch SupportedTypes.classify(filePath: path).kind {
        case .photo: imagesDone += 1
        case .video: videosDone += 1
        case .unsupported: otherDone += 1
        }
    }
}

struct ScanSummary: Equatable {
    let fileCount: Int
    let totalBytes: Int64
}

struct MetadataEntry: Equatable, Identifiable {
    let id = UUID()
    let group: String
    let tag: String
    let value: String
}

struct CleanResult: Equatable, Identifiable {
    let id = UUID()
    let path: String
    let status: CleanStatus
    let reason: String?
    let metadataBefore: [MetadataEntry]
    let metadataAfter: [MetadataEntry]

    init(
        path: String,
        status: CleanStatus,
        reason: String? = nil,
        metadataBefore: [MetadataEntry] = [],
        metadataAfter: [MetadataEntry] = []
    ) {
        self.path = path
        self.status = status
        self.reason = reason
        self.metadataBefore = metadataBefore
        self.metadataAfter = metadataAfter
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let result: CleanResult
    var path: String { result.path }
    var status: CleanStatus { result.status }
    var reason: String? { result.reason }
    var metadataBefore: [MetadataEntry] { result.metadataBefore }
    var metadataAfter: [MetadataEntry] { result.metadataAfter }
}

struct Summary: Equatable {
    let jobId: String
    let state: RunState
    let counters: Counters
    let message: String?
    let scanSummary: ScanSummary?
}

struct FieldRow: Identifiable {
    let id = UUID()
    let label: String
    let before: String
    let after: String
    let stripped: Bool
}
