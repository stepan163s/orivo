import Foundation
import Combine

@MainActor
public final class LibraryManager: ObservableObject {
    public static let shared = LibraryManager()
    
    @Published public var favorites: [TMDBMedia] = []
    @Published public var history: [TMDBMedia] = []
    
    private let favoritesURL: URL
    private let historyURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("Orivo/library")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        self.favoritesURL = dir.appendingPathComponent("favorites.json")
        self.historyURL = dir.appendingPathComponent("history.json")
        
        loadAll()
    }
    
    public func loadAll() {
        if let data = try? Data(contentsOf: favoritesURL),
           let decoded = try? JSONDecoder().decode([TMDBMedia].self, from: data) {
            self.favorites = decoded
        }
        if let data = try? Data(contentsOf: historyURL),
           let decoded = try? JSONDecoder().decode([TMDBMedia].self, from: data) {
            self.history = decoded
        }
    }
    
    public func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            try? data.write(to: favoritesURL)
        }
    }
    
    public func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL)
        }
    }
    
    public func toggleFavorite(media: TMDBMedia) {
        if favorites.contains(where: { $0.id == media.id }) {
            favorites.removeAll(where: { $0.id == media.id })
        } else {
            favorites.append(media)
        }
        saveFavorites()
    }
    
    public func isFavorite(media: TMDBMedia) -> Bool {
        return favorites.contains(where: { $0.id == media.id })
    }
    
    public func addToHistory(media: TMDBMedia) {
        history.removeAll(where: { $0.id == media.id })
        history.insert(media, at: 0)
        if history.count > 50 {
            history.removeLast()
        }
        saveHistory()
    }
    
    public func clearHistory() {
        history.removeAll()
        saveHistory()
    }
}
