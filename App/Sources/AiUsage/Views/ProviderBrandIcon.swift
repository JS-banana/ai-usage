import AppKit

enum ProviderBrandIcon {
    private static let size = NSSize(width: 16, height: 16)
    private static let appResourceBundleName = "AiUsage_AiUsage.bundle"

    static func image(for branding: ProviderTabBranding) -> NSImage? {
        guard let resource = branding.logoResource,
              let url = url(for: resource),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        image.size = self.size
        image.isTemplate = true
        return image
    }

    static func url(
        for resource: ProviderLogoResource,
        mainResourceURL: URL? = Bundle.main.resourceURL,
        mainBundleURL: URL = Bundle.main.bundleURL,
        sourceFilePath: String = #filePath
    ) -> URL? {
        let relativePath = resource.subdirectory
            .appending("/")
            .appending(resource.name)
            .appending(".")
            .appending(resource.fileExtension)

        return resourceSearchRoots(
            mainResourceURL: mainResourceURL,
            mainBundleURL: mainBundleURL,
            sourceFilePath: sourceFilePath
        )
        .map { $0.appendingPathComponent(relativePath) }
        .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func resourceSearchRoots(
        mainResourceURL: URL?,
        mainBundleURL: URL,
        sourceFilePath: String
    ) -> [URL] {
        var roots: [URL] = []

        if let mainResourceURL {
            roots.append(mainResourceURL)
            roots.append(
                mainResourceURL
                    .appendingPathComponent(appResourceBundleName, isDirectory: true)
                    .appendingPathComponent("Resources", isDirectory: true)
            )
        }

        roots.append(
            mainBundleURL
                .appendingPathComponent(appResourceBundleName, isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
        )

        let sourceURL = URL(fileURLWithPath: sourceFilePath)
        roots.append(
            sourceURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources", isDirectory: true)
        )

        return roots.uniqued()
    }
}

private extension Array where Element == URL {
    func uniqued() -> [URL] {
        var seen: Set<String> = []
        return filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
