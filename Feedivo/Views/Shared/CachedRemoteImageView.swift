import AppKit
import SwiftUI

struct CachedRemoteImageView<Content: View, Placeholder: View>: View {
    let url: URL?
    let targetPixelSize: CGSize?
    let imageCache: ImageCacheService
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var nsImage: NSImage?

    init(
        url: URL?,
        targetPixelSize: CGSize? = nil,
        imageCache: ImageCacheService = .shared,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetPixelSize = targetPixelSize
        self.imageCache = imageCache
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let nsImage {
                content(Image(nsImage: nsImage))
            } else {
                placeholder()
            }
        }
        .task(id: imageLoadID) {
            await loadImage()
        }
    }

    private var imageLoadID: String {
        guard let url else {
            return "nil"
        }

        guard let targetPixelSize else {
            return url.absoluteString
        }

        return "\(url.absoluteString)#\(Int(targetPixelSize.width.rounded(.up)))x\(Int(targetPixelSize.height.rounded(.up)))"
    }

    @MainActor
    private func loadImage() async {
        nsImage = nil

        guard let url else {
            return
        }

        let requestedTargetPixelSize = targetPixelSize
        let loadedImage: NSImage?
        if let requestedTargetPixelSize {
            loadedImage = await imageCache.image(for: url, targetPixelSize: requestedTargetPixelSize)
        } else {
            loadedImage = await imageCache.image(for: url)
        }

        // Prüfen nach dem await: Wenn die URL sich geändert oder der Task
        // abgebrochen wurde, dürfen wir das Bild der alten URL nicht mehr setzen
        // — sonst flackert beim schnellen Scrollen kurz ein falsches Bild auf.
        guard !Task.isCancelled,
              url == self.url,
              requestedTargetPixelSize == self.targetPixelSize else {
            return
        }

        nsImage = loadedImage
    }
}
