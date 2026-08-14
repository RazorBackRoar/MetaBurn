import Foundation

/// Formats metadata timestamps for the details table as `MM/dd/yyyy`.
public enum MetadataDateFormat: Sendable {
    public static func display(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let date = parse(trimmed) {
            return formatted(date)
        }
        return trimmed
    }

    private static func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.string(from: date)
    }

    private static func parse(_ raw: String) -> Date? {
        let formats = [
            "yyyy:MM:dd HH:mm:ss",
            "yyyy:MM:dd",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "M/d/yyyy"
        ]
        let posix = Locale(identifier: "en_US_POSIX")
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = posix
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) {
            return date
        }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}
