import AppKit

@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        guard let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else {
            fatalError("Missing menu bar icon resource")
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}
