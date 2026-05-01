import AppKit

@MainActor
final class AppIconProvider {
    static let shared = AppIconProvider()

    private var cachedAppIcon: NSImage?
    private var cachedMiniwindowIcon: NSImage?

    func configureApplicationIcon() {
        guard let icon = appIconImage() else { return }
        NSApp.applicationIconImage = icon
    }

    func appIconImage() -> NSImage? {
        if let cachedAppIcon {
            return cachedAppIcon
        }

        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            cachedAppIcon = icon
            return icon
        }

        let fallback = NSApp.applicationIconImage
        cachedAppIcon = fallback
        return fallback
    }

    func miniwindowIconImage() -> NSImage? {
        if let cachedMiniwindowIcon {
            return cachedMiniwindowIcon
        }

        if let url = Bundle.main.url(forResource: "AppMiniwindow", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            icon.size = NSSize(width: 128, height: 128)
            cachedMiniwindowIcon = icon
            return icon
        }

        guard let fallback = appIconImage()?.copy() as? NSImage else {
            return nil
        }
        fallback.size = NSSize(width: 128, height: 128)
        cachedMiniwindowIcon = fallback
        return fallback
    }
}
