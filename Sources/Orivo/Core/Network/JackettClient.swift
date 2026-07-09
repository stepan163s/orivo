import Foundation

public struct JackettResponse: Codable, Sendable {
    public let results: [JackettResult]
    
    enum CodingKeys: String, CodingKey {
        case results = "Results"
    }
}

public struct JackettResult: Codable, Identifiable, Hashable, Sendable {
    public var id: String { guid ?? link ?? UUID().uuidString }
    public let guid: String?
    public let title: String?
    public let link: String?
    public let magnetUri: String?
    public let size: Int64?
    public let seeders: Int?
    public let peers: Int?
    public let tracker: String?
    public let publishDate: String?
    
    public var computedTitle: String {
        return title ?? "Без названия"
    }
    
    public var formattedSize: String {
        guard let size = size else { return "Размер неизвестен" }
        let kb = Double(size) / 1024.0
        let mb = kb / 1024.0
        let gb = mb / 1024.0
        if gb >= 1.0 {
            return String(format: "%.2f ГБ", gb)
        } else if mb >= 1.0 {
            return String(format: "%.1f МБ", mb)
        } else {
            return String(format: "%.0f КБ", kb)
        }
    }
    
    public var seedersCount: Int {
        return seeders ?? 0
    }
    
    public var peersCount: Int {
        return peers ?? 0
    }
    
    enum CodingKeys: String, CodingKey {
        case guid = "Guid"
        case title = "Title"
        case link = "Link"
        case magnetUri = "MagnetUri"
        case size = "Size"
        case seeders = "Seeders"
        case peers = "Peers"
        case tracker = "Tracker"
        case publishDate = "PublishDate"
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: JackettResult, rhs: JackettResult) -> Bool {
        return lhs.id == rhs.id
    }
}

public final class JackettClient: Sendable {
    public static let shared = JackettClient()
    
    private func getBaseURL() async -> String {
        return await MainActor.run {
            let settings = SettingsManager.shared.settings
            if settings.useExternalServers && !settings.externalJackettHost.isEmpty {
                return settings.externalJackettHost
            } else {
                let port = ServiceManager.shared.resolvedJackettPort
                return "http://127.0.0.1:\(port)"
            }
        }
    }
    
    private init() {}
    
    public func getJackettAPIKey() async -> String {
        return await MainActor.run {
            let settings = SettingsManager.shared.settings
            if settings.useExternalServers {
                return settings.externalJackettApiKey
            } else {
                return getLocalJackettAPIKey()
            }
        }
    }
    
    private func getLocalJackettAPIKey() -> String {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        
        let paths = [
            home.appendingPathComponent(".config/Jackett/ServerConfig.json"),
            home.appendingPathComponent("Library/Application Support/Jackett/ServerConfig.json"),
            home.appendingPathComponent("Library/Application Support/Orivo/services/jackett/ServerConfig.json")
        ]
        
        for path in paths {
            if fileManager.fileExists(atPath: path.path) {
                if let data = try? Data(contentsOf: path),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let apiKey = json["APIKey"] as? String {
                    return apiKey
                }
            }
        }
        return ""
    }
    
    public func search(query: String) async throws -> [JackettResult] {
        let apiKey = await getJackettAPIKey()
        guard !apiKey.isEmpty else {
            throw NSError(domain: "JackettClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Jackett API Key not found. Please verify Jackett is installed or configure an external server API key."])
        }
        
        let base = await getBaseURL()
        var urlComponents = URLComponents(string: "\(base)/api/v2.0/indexers/all/results")
        urlComponents?.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "Query", value: query)
        ]
        
        guard let url = urlComponents?.url else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(JackettResponse.self, from: data)
        return result.results
    }
    
    public func fetchIndexers() async throws -> [JackettIndexer] {
        let apiKey = await getJackettAPIKey()
        guard !apiKey.isEmpty else { return [] }
        let base = await getBaseURL()
        guard let url = URL(string: "\(base)/api/v2.0/indexers") else { return [] }
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [URLQueryItem(name: "apikey", value: apiKey)]
        guard let targetURL = urlComponents?.url else { return [] }
        
        let (data, response) = try await URLSession.shared.data(from: targetURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }
        
        let decoder = JSONDecoder()
        return (try? decoder.decode([JackettIndexer].self, from: data)) ?? []
    }
}

public struct JackettIndexer: Codable, Identifiable, Hashable, Sendable {
    public var id: String { idString ?? UUID().uuidString }
    public let idString: String?
    public let name: String?
    public let configured: Bool?
    public let description: String?
    
    enum CodingKeys: String, CodingKey {
        case idString = "id"
        case name
        case configured
        case description
    }
}
