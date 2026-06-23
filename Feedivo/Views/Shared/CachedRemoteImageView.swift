import AppKit
import SwiftUI

struct CachedRemoteImageView<Content: View, Placeholder: View>: View {
    let url: URL?
    let imageCache: ImageCacheService
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var nsImage: NSImage?

    init(
        url: URL?,
        imageCache: ImageCacheService = .shared,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
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
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        nsImage = nil

        guard let url else {
            return
        }

        nsImage = await imageCache.image(for: url)
    }
}
