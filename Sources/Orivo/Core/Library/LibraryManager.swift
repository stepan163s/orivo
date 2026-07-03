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
        
        Task {
            await syncWithCUB()
        }
    }
    
    public func syncWithCUB() async {
        let settings = SettingsManager.shared.settings
        guard !settings.cubToken.isEmpty else { return }
        
        LogManager.shared.log(serviceId: "system", text: "LibraryManager: Starting CUB synchronization...")
        do {
            let cubBookmarks = try await CUBClient.shared.fetchBookmarks()
            
            await MainActor.run {
                var updated = false
                for cubItem in cubBookmarks {
                    if !self.favorites.contains(where: { $0.id == cubItem.id }) {
                        let media = TMDBMedia(
                            id: cubItem.id,
                            title: cubItem.title,
                            name: cubItem.title,
                            overview: nil,
                            posterPath: nil,
                            backdropPath: nil,
                            voteAverage: nil,
                            releaseDate: nil,
                            firstAirDate: nil,
                            mediaType: cubItem.type
                        )
                        self.favorites.append(media)
                        updated = true
                    }
                }
                if updated {
                    self.saveFavorites()
                }
            }
            
            let cubHistory = try await CUBClient.shared.fetchTimeline()
            await MainActor.run {
                var updated = false
                for cubItem in cubHistory {
                    if !self.history.contains(where: { $0.id == cubItem.id }) {
                        let media = TMDBMedia(
                            id: cubItem.id,
                            title: "ID \(cubItem.id)",
                            name: nil,
                            overview: nil,
                            posterPath: nil,
                            backdropPath: nil,
                            voteAverage: nil,
                            releaseDate: nil,
                            firstAirDate: nil,
                            mediaType: "movie"
                        )
                        self.history.append(media)
                        updated = true
                    }
                }
                if updated {
                    self.saveHistory()
                }
            }
        } catch {
            LogManager.shared.log(serviceId: "system", text: "LibraryManager: CUB sync failed: \(error.localizedDescription)", isError: true)
        }
    }
    
    public func saveFavorites() {
        let favs = favorites
        let url = favoritesURL
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(favs) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
    
    public func saveHistory() {
        let hist = history
        let url = historyURL
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(hist) {
                try? data.write(to: url, options: .atomic)
            }
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
