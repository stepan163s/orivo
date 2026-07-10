import Foundation

public struct TMDBPageResponse<T: Codable>: Codable {
    public let page: Int?
    public let results: [T]
    public let totalPages: Int?
    public let totalResults: Int?
    
    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

public struct TMDBMedia: Codable, Identifiable, Hashable {
    public let id: Int
    public let title: String?
    public let name: String? // For TV Shows
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let voteAverage: Double?
    public let releaseDate: String?
    public let firstAirDate: String? // For TV Shows
    public let mediaType: String?
    
    // Non-decodable mutable property to carry Kinorium metadata
    public var kinoriumID: String? = nil
    
    public var computedTitle: String {
        return title ?? name ?? "Unknown Title"
    }
    
    public var computedReleaseYear: String {
        let dateStr = releaseDate ?? firstAirDate ?? ""
        return String(dateStr.prefix(4))
    }
    
    public var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(path)")
    }
    
    public var backdropURL: URL? {
        guard let path = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(path)")
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case mediaType = "media_type"
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: TMDBMedia, rhs: TMDBMedia) -> Bool {
        return lhs.id == rhs.id
    }
}

public struct TMDBGenre: Codable, Identifiable {
    public let id: Int
    public let name: String
}

public struct TMDBMediaDetail: Codable {
    public let id: Int
    public let title: String?
    public let name: String?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let voteAverage: Double?
    public let releaseDate: String?
    public let firstAirDate: String?
    public let genres: [TMDBGenre]?
    public let runtime: Int? // In minutes (Movies)
    public let episodeRunTime: [Int]? // For TV Shows
    public let numberOfSeasons: Int? // For TV Shows
    public let numberOfEpisodes: Int? // For TV Shows
    public let credits: TMDBCredits?
    
    public var computedTitle: String {
        return title ?? name ?? "Unknown Title"
    }
    
    public var computedReleaseYear: String {
        let dateStr = releaseDate ?? firstAirDate ?? ""
        return String(dateStr.prefix(4))
    }
    
    public var runtimeString: String {
        if let r = runtime, r > 0 {
            return "\(r) мин."
        }
        if let list = episodeRunTime, let r = list.first, r > 0 {
            return "\(r) мин. серия"
        }
        return ""
    }
    
    public var genresString: String {
        guard let gList = genres else { return "" }
        return gList.map { $0.name }.joined(separator: ", ")
    }
    
    public var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(path)")
    }
    
    public var backdropURL: URL? {
        guard let path = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w300\(path)")
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, name, overview, genres, runtime
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case episodeRunTime = "episode_run_time"
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case credits
    }
}

public struct TMDBCredits: Codable {
    public let cast: [TMDBCast]
}

public struct TMDBCast: Codable, Identifiable {
    public let id: Int
    public let name: String
    public let character: String
    public let profilePath: String?
    
    public var profileURL: URL? {
        guard let path = profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(path)")
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, character
        case profilePath = "profile_path"
    }
}

public struct TMDBSeasonDetail: Codable {
    public let id: Int
    public let seasonNumber: Int
    public let name: String
    public let episodes: [TMDBEpisode]
    
    enum CodingKeys: String, CodingKey {
        case id, name, episodes
        case seasonNumber = "season_number"
    }
}

public struct TMDBEpisode: Codable, Identifiable {
    public let id: Int
    public let episodeNumber: Int
    public let name: String
    public let overview: String?
    public let stillPath: String?
    public let airDate: String?
    
    public var stillURL: URL? {
        guard let path = stillPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w300\(path)")
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, overview
        case episodeNumber = "episode_number"
        case stillPath = "still_path"
        case airDate = "air_date"
    }
}

public final class TMDBClient: Sendable {
    public static let shared = TMDBClient()
    
    private let apiKey = "4ef0d7355d9ffb5151e987764708ce96"
    private let baseURL = "https://api.themoviedb.org/3"
    private let language = "ru-RU"
    
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 30
        config.timeoutIntervalForRequest = 10.0
        config.httpShouldUsePipelining = true
        config.connectionProxyDictionary = [:]
        self.session = URLSession(configuration: config)
    }
    
    private func fetch<T: Codable>(endpoint: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let customKey = await MainActor.run { SettingsManager.shared.settings.tmdbApiKey }
        let resolvedKey = customKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? apiKey : customKey
        
        var urlComponents = URLComponents(string: "\(baseURL)\(endpoint)")
        var allQueryItems = [
            URLQueryItem(name: "api_key", value: resolvedKey),
            URLQueryItem(name: "language", value: language)
        ]
        allQueryItems.append(contentsOf: queryItems)
        urlComponents?.queryItems = allQueryItems
        
        guard let url = urlComponents?.url else {
            throw URLError(.badURL)
        }
        
        let eventName = "TMDB Fetch: \(endpoint)"
        AppPerfTracker.shared.start(eventName)
        defer { AppPerfTracker.shared.stop(eventName) }
        
        let (data, response) = try await self.session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
    
    public func fetchTrendingMovies() async throws -> [TMDBMedia] {
        let response: TMDBPageResponse<TMDBMedia> = try await fetch(endpoint: "/trending/movie/week")
        return response.results
    }
    
    public func fetchTrendingTVShows() async throws -> [TMDBMedia] {
        let response: TMDBPageResponse<TMDBMedia> = try await fetch(endpoint: "/trending/tv/week")
        return response.results
    }
    
    public func fetchPopularMovies() async throws -> [TMDBMedia] {
        let response: TMDBPageResponse<TMDBMedia> = try await fetch(endpoint: "/movie/popular")
        return response.results
    }
    
    public func fetchPopularTVShows() async throws -> [TMDBMedia] {
        let response: TMDBPageResponse<TMDBMedia> = try await fetch(endpoint: "/tv/popular")
        return response.results
    }
    
    public func fetchTrendingToday() async throws -> [TMDBMedia] {
        let response: TMDBPageResponse<TMDBMedia> = try await fetch(endpoint: "/trending/movie/day")
        return response.results
    }
    
    public func fetchTopRatedMovies() async throws -> [TMDBMedia] {
        let response: TMDBPageResponse<TMDBMedia> = try await fetch(endpoint: "/movie/top_rated")
        return response.results
    }
    
    public func fetchTopRatedTVShows() async throws -> [TMDBMedia] {
        let response: TMDBPageResponse<TMDBMedia> = try await fetch(endpoint: "/tv/top_rated")
        return response.results
    }
    
    public func fetchMoviesByGenre(id: Int) async throws -> [TMDBMedia] {
        let queryItems = [URLQueryItem(name: "with_genres", value: "\(id)")]
        let response: TMDBPageResponse<TMDBMedia> = try await fetch(endpoint: "/discover/movie", queryItems: queryItems)
        return response.results
    }
    
    public func fetchMovieDetails(id: Int) async throws -> TMDBMediaDetail {
        let query = [URLQueryItem(name: "append_to_response", value: "credits")]
        return try await fetch(endpoint: "/movie/\(id)", queryItems: query)
    }
    
    public func fetchTVShowDetails(id: Int) async throws -> TMDBMediaDetail {
        let query = [URLQueryItem(name: "append_to_response", value: "credits")]
        return try await fetch(endpoint: "/tv/\(id)", queryItems: query)
    }
    
    public func fetchTVSeasonDetails(tvShowId: Int, seasonNumber: Int) async throws -> TMDBSeasonDetail {
        return try await fetch(endpoint: "/tv/\(tvShowId)/season/\(seasonNumber)")
    }
    
    public func searchMulti(query: String) async throws -> [TMDBMedia] {
        let queryItems = [URLQueryItem(name: "query", value: query)]
        let response: TMDBPageResponse<TMDBMedia> = try await fetch(endpoint: "/search/multi", queryItems: queryItems)
        return response.results.filter { $0.mediaType == "movie" || $0.mediaType == "tv" }
    }
}
