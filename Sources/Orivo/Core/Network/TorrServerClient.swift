import Foundation

public struct TorrServerRequest: Codable {
    public let action: String
    public let link: String?
    public let hash: String?
    public let title: String?
    public let save_to_db: Bool?
    
    public init(action: String, link: String? = nil, hash: String? = nil, title: String? = nil, saveToDB: Bool? = nil) {
        self.action = action
        self.link = link
        self.hash = hash
        self.title = title
        self.save_to_db = saveToDB
    }
}

public struct TorrServerAddResponse: Codable {
    public let hash: String
    public let title: String?
    public let files: [TorrServerFile]?
}

public struct TorrServerFile: Codable, Identifiable, Hashable {
    public var id: Int { index }
    public let index: Int
    public let path: String
    public let size: Int64
    
    public var formattedSize: String {
        let gb = Double(size) / (1024 * 1024 * 1024)
        if gb >= 1.0 {
            return String(format: "%.2f ГБ", gb)
        } else {
            let mb = Double(size) / (1024 * 1024)
            return String(format: "%.1f МБ", mb)
        }
    }
    
    public var filename: String {
        return (path as NSString).lastPathComponent
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(index)
        hasher.combine(path)
    }
}

public struct TorrServerStatusResponse: Codable {
    public let hash: String
    public let title: String?
    public let status: Int? // 0: Idle, 1: Getting Info, 2: Preloading, 3: Downloading/Working
    public let stat_string: String?
    public let preload_size: Int64?
    public let loaded_size: Int64?
    public let download_speed: Double?
    public let active_peers: Int?
    public let total_peers: Int?
    
    public var bufferingProgress: Double {
        guard let loaded = loaded_size, let preload = preload_size, preload > 0 else { return 0 }
        return min(Double(loaded) / Double(preload), 1.0)
    }
    
    public var formattedSpeed: String {
        guard let speed = download_speed else { return "0 КБ/с" }
        let mb = speed / (1024 * 1024)
        if mb >= 1.0 {
            return String(format: "%.1f МБ/с", mb)
        } else {
            let kb = speed / 1024
            return String(format: "%.0f КБ/с", kb)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case hash, title, status
        case stat_string = "stat_string"
        case preload_size = "preload_size"
        case loaded_size = "loaded_size"
        case download_speed = "download_speed"
        case active_peers = "active_peers"
        case total_peers = "total_peers"
    }
}

public final class TorrServerClient: Sendable {
    public static let shared = TorrServerClient()
    
    private let baseURL = "http://127.0.0.1:8090"
    
    private init() {}
    
    private func post<T: Codable>(endpoint: String, request: TorrServerRequest) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw URLError(.badURL)
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
    
    public func addTorrent(link: String, title: String) async throws -> TorrServerAddResponse {
        let req = TorrServerRequest(action: "add", link: link, title: title, saveToDB: true)
        return try await post(endpoint: "/torrent/action", request: req)
    }
    
    public func getTorrentStatus(hash: String) async throws -> TorrServerStatusResponse {
        let req = TorrServerRequest(action: "get", hash: hash)
        return try await post(endpoint: "/torrent/action", request: req)
    }
    
    public func getPlayURL(hash: String, fileIndex: Int, filename: String) -> String {
        guard let escapedFilename = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return "\(baseURL)/stream/?link=\(hash)&index=\(fileIndex)&play"
        }
        return "\(baseURL)/stream/\(escapedFilename)?link=\(hash)&index=\(fileIndex)&play"
    }
}
