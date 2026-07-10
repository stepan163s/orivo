import SwiftUI
import AppKit

public struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var loadedImage: NSImage? = nil
    @State private var hasFailed = false
    
    public init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        
        // Synchronously check memory cache during initialization
        if let url = url, let cachedImage = ImageCache.shared.get(for: url) {
            self._loadedImage = State(initialValue: cachedImage)
        } else {
            self._loadedImage = State(initialValue: nil)
        }
    }
    
    public var body: some View {
        ZStack {
            if let nsImage = loadedImage {
                content(Image(nsImage: nsImage))
                    .transition(.opacity)
            } else {
                placeholder()
                    .transition(.opacity)
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard let url = url else {
            await MainActor.run {
                self.hasFailed = true
            }
            return
        }
        
        // If already loaded synchronously during init, skip fetching
        if loadedImage != nil {
            return
        }
        
        // Re-check cache just in case it was cached after init
        if let cachedImage = ImageCache.shared.get(for: url) {
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.35)) {
                    self.loadedImage = cachedImage
                }
            }
            return
        }
        
        let eventName = "Image Load: \(url.lastPathComponent)"
        AppPerfTracker.shared.start(eventName)
        defer { AppPerfTracker.shared.stop(eventName) }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                LogManager.shared.log(serviceId: "system", text: "CachedAsyncImage: HTTP Error \(httpResponse.statusCode) loading image: \(url.absoluteString)", isError: true)
            }
            guard let nsImage = NSImage(data: data) else {
                LogManager.shared.log(serviceId: "system", text: "CachedAsyncImage: Failed to decode NSImage from \(data.count) bytes for: \(url.absoluteString)", isError: true)
                await MainActor.run {
                    self.hasFailed = true
                }
                return
            }
            // Store in cache
            ImageCache.shared.set(nsImage, for: url)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.45)) {
                    self.loadedImage = nsImage
                }
            }
        } catch {
            LogManager.shared.log(serviceId: "system", text: "CachedAsyncImage: Network error: \(error.localizedDescription) loading image: \(url.absoluteString)", isError: true)
            await MainActor.run {
                self.hasFailed = true
            }
        }
    }
}

public final class ImageCache: @unchecked Sendable {
    public static let shared = ImageCache()
    private let cache = NSCache<NSURL, NSImage>()
    
    private init() {
        cache.countLimit = 150 // Keep up to 150 images in memory cache
    }
    
    public func get(for url: URL) -> NSImage? {
        return cache.object(forKey: url as NSURL)
    }
    
    public func set(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}
