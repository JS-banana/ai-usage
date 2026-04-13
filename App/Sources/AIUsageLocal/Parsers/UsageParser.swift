import Foundation

protocol UsageParser {
    var sourceID: String { get }
    var displayName: String { get }
    func discoverCandidates() -> [URL]
    func parse(files: [URL]) -> ParsedFileResult
}

enum ParserUtils {
    static func expandHome(_ path: String) -> URL {
        let ns = path as NSString
        return URL(fileURLWithPath: ns.expandingTildeInPath)
    }

    static func listFiles(recursive root: URL, suffixes: [String]) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
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

    static func projectName(from path: String) -> String {
        URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
    }

    static func isoDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formats = [ISO8601DateFormatter()]
        formats[0].formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formats[0].date(from: value) { return parsed }
        let fallback = ISO8601DateFormatter()
        return fallback.date(from: value)
    }

    static func hash(_ input: String) -> String {
        String(input.hashValue)
    }
}
