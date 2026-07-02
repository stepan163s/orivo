import Foundation

public struct JackettResponse: Codable {
    public let results: [JackettResult]
    
    enum CodingKeys: String, CodingKey {
        case results = "Results"
    }
}

public struct JackettResult: Codable, Identifiable, Hashable {
    public var id: String { guid ?? link ?? UUID().uuidString }
    public let title: String?
    public let guid: String?
    public let link: String?
    public let size: Int64?
    public let seeders: Int?
    public let peers: Int?
    public let tracker: String?
    public let publishDate: String?
    
    public var formattedSize: String {
        guard let sizeBytes = size else { return "0 ГБ" }
        let gb = Double(sizeBytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 {
            return String(format: "%.2f ГБ", gb)
        } else {
            let mb = Double(sizeBytes) / (1024 * 1024)
            return String(format: "%.1f МБ", mb)
        }
    }
    
    public var computedTitle: String {
        return title ?? "Unknown Torrent"
    }
    
    public var seedersCount: Int {
        return seeders ?? 0
    }
    
    public var peersCount: Int {
        return peers ?? 0
    }
    
    enum CodingKeys: String, CodingKey {
        case title = "Title"
        case guid = "Guid"
        case link = "Link"
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
    
    private let baseURL = "http://127.0.0.1:9117"
    
    private init() {}
    
    private func getJackettAPIKey() -> String {
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
        let apiKey = getJackettAPIKey()
        guard !apiKey.isEmpty else {
            throw NSError(domain: "JackettClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Jackett API Key not found. Please verify Jackett is installed."])
        }
        
        var urlComponents = URLComponents(string: "\(baseURL)/api/v2.0/indexers/all/results")
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
}
