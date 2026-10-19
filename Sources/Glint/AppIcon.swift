import AppKit
import SwiftUI

struct AppIcon: View {
    static let image: NSImage = {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else {
            fatalError("Missing app icon resource")
        }
        return image
    }()
    let size: CGFloat
    var body: some View {
        Image(nsImage: Self.image).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
}
