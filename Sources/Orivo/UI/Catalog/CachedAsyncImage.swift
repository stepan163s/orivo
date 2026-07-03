import SwiftUI
import AppKit

public struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var phase: AsyncImagePhase = .empty
    
    public init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    public var body: some View {
        Group {
            switch phase {
            case .empty:
                placeholder()
            case .success(let image):
                content(image)
            case .failure:
                placeholder()
            @unknown default:
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard let url = url else {
            self.phase = .failure(URLError(.badURL))
            return
        }
        
        // Check cache first
        if let cachedImage = ImageCache.shared.get(for: url) {
            self.phase = .success(Image(nsImage: cachedImage))
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let nsImage = NSImage(data: data) else {
                self.phase = .failure(URLError(.cannotDecodeContentData))
                return
            }
            // Store in cache
            ImageCache.shared.set(nsImage, for: url)
            self.phase = .success(Image(nsImage: nsImage))
        } catch {
            self.phase = .failure(error)
        }
    }
}

private final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, NSImage>()
    
    private init() {
        cache.countLimit = 150 // Keep up to 150 images in memory cache
    }
    
    func get(for url: URL) -> NSImage? {
        return cache.object(forKey: url as NSURL)
    }
    
    func set(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}
