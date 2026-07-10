import Foundation

typealias FileKind = SupportedTypes.FileKind
typealias FileClassification = SupportedTypes.FileClassification
typealias CleanStatus = MetadataCleaner.CleanStatus

enum RunState: String, Equatable {
    case waiting, scanning, cleaning, done, failed, cancelled, exiftoolMissing
}

struct Counters: Equatable {
    var supported = 0
    var cleaned = 0
    var skipped = 0
    var failed = 0
    var partial = 0
}

struct ScanSummary: Equatable {
    let fileCount: Int
    let totalBytes: Int64
}

struct MetadataEntry: Equatable, Identifiable {
    let id = UUID()
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
