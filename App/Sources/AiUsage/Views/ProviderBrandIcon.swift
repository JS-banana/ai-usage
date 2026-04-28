import AppKit

enum ProviderBrandIcon {
    private static let size = NSSize(width: 16, height: 16)

    static func image(for branding: ProviderTabBranding) -> NSImage? {
        guard let resource = branding.logoResource,
              let url = Bundle.module.url(
                forResource: resource.name,
                withExtension: resource.fileExtension,
                subdirectory: resource.subdirectory
              ),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        image.size = self.size
        image.isTemplate = true
        return image
    }
}
