import Foundation
import CryptoKit
import Domain

public enum StableID {
    public static func make(_ parts: [String]) -> String {
        let input = parts.joined(separator: "||")
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum DateParsing {
    private static let formatterCache = ISO8601FormatterCache()

    public static func parseISO8601(_ value: String?) -> Date? {
        guard let value, value.isEmpty == false else { return nil }
        return formatterCache.parse(value)
    }
}

private final class ISO8601FormatterCache: @unchecked Sendable {
    private let lock = NSLock()
    private let fractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let fallbackFormatter = ISO8601DateFormatter()

    func parse(_ value: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        if let result = fractionalSecondsFormatter.date(from: value) {
            return result
        }
        return fallbackFormatter.date(from: value)
    }
}

public enum FileDiscovery {
    public static func expandHome(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    public static func listFiles(recursive root: URL, suffixes: [String]) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            if suffixes.contains(where: { url.lastPathComponent.hasSuffix($0) }) {
                urls.append(url)
            }
        }
        return urls
    }
}

public enum FileFingerprint {
    public static func metadataSignature(for fileURL: URL) -> String {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values?.fileSize ?? 0
        return StableID.make([
            fileURL.path,
            String(fileSize),
            String(modifiedAt)
        ])
    }
}

public enum ParserDiagnosticsFactory {
    public static func warning(source: String, filePath: String, message: String) -> ParserDiagnostic {
        ParserDiagnostic(
            id: StableID.make([source, filePath, message, "warning"]),
            severity: .warning,
            source: source,
            filePath: filePath,
            message: message
        )
    }

    public static func error(source: String, filePath: String, message: String) -> ParserDiagnostic {
        ParserDiagnostic(
            id: StableID.make([source, filePath, message, "error"]),
            severity: .error,
            source: source,
            filePath: filePath,
            message: message
        )
    }
}
