import Foundation

/// Builds the numbered Skippable audit log (`skipped-summary.txt`).
public enum SkipSummary: Sendable {
    public static func line(index: Int, filePath: String, reason: String) -> String {
        let name = URL(fileURLWithPath: filePath).lastPathComponent
        return "\(index). \(name) - \(reason)"
    }

    @preconcurrency private static let dateFormatter = ISO8601DateFormatter()

    public static func document(entries: [(path: String, reason: String)]) -> String {
        guard !entries.isEmpty else {
            return "No files were skipped.\n"
        }
        var lines: [String] = [
            "MetaBurn skipped-file summary",
            "Generated: \(dateFormatter.string(from: Date()))",
            "Count: \(entries.count)",
            ""
        ]
        for (index, entry) in entries.enumerated() {
            lines.append(line(index: index + 1, filePath: entry.path, reason: entry.reason))
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
