import Foundation

public struct CUBPairingResponse: Decodable, Sendable {
    public let code: String          // e.g. "123456"
    public let user_code: String     // e.g. "123-456"
    public let device_code: String   // Verification token used to poll
    public let verification_url: String
    public let expires_in: Int
    public let interval: Int
}

public struct CUBTokenResponse: Decodable, Sendable {
    public let token: String?
    public let status: String?       // "pending", "approved", etc.
    public let error: String?
}

public struct CUBBookmarkItem: Codable, Sendable {
    public let id: Int               // TMDB ID
    public let title: String?
    public let type: String?        // "movie" or "tv"
}

public struct CUBTimelineItem: Codable, Sendable {
    public let id: Int               // TMDB ID
    public let time: Double
    public let duration: Double
}

@MainActor
public final class CUBClient: Sendable {
    public static let shared = CUBClient()
    
    private init() {}
    
    private var baseURL: String {
        let settings = SettingsManager.shared.settings
        let mirror = settings.cubMirrorURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if mirror.isEmpty {
            return "https://cub.red/api"
        }
        return mirror.hasSuffix("/api") ? mirror : mirror + "/api"
    }
    
    private func getHeaders() -> [String: String] {
        let settings = SettingsManager.shared.settings
        var headers = [
            "Content-Type": "application/json",
            "token": settings.cubToken
        ]
        if !settings.cubProfileID.isEmpty {
            headers["profile"] = settings.cubProfileID
        }
        return headers
    }
    
    /// Requests a new 6-digit device link PIN code
    public func requestPairingCode() async throws -> CUBPairingResponse {
        let url = URL(string: "\(baseURL)/device/code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "client_id": "lampa",
            "device_id": UUID().uuidString
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "CUBClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to request CUB pairing code"])
        }
        return try JSONDecoder().decode(CUBPairingResponse.self, from: data)
    }
    
    /// Polls CUB token status for authorization progress
    public func pollPairingStatus(deviceCode: String) async throws -> CUBTokenResponse {
        let url = URL(string: "\(baseURL)/device/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "client_id": "lampa",
            "device_code": deviceCode
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "CUBClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to verify CUB pairing status"])
        }
        return try JSONDecoder().decode(CUBTokenResponse.self, from: data)
    }
    
    /// Fetch all bookmarks (favorites) from CUB profile
    public func fetchBookmarks() async throws -> [CUBBookmarkItem] {
        let settings = SettingsManager.shared.settings
        guard !settings.cubToken.isEmpty else { return [] }
        
        let url = URL(string: "\(baseURL)/bookmarks/all")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, val) in getHeaders() {
            request.setValue(val, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            return []
        }
        return (try? JSONDecoder().decode([CUBBookmarkItem].self, from: data)) ?? []
    }
    
    /// Fetch watch progression timeline history from CUB
    public func fetchTimeline() async throws -> [CUBTimelineItem] {
        let settings = SettingsManager.shared.settings
        guard !settings.cubToken.isEmpty else { return [] }
        
        let url = URL(string: "\(baseURL)/timeline/all")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, val) in getHeaders() {
            request.setValue(val, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            return []
        }
        return (try? JSONDecoder().decode([CUBTimelineItem].self, from: data)) ?? []
    }
    
    /// Update watch progression progress code on CUB servers
    public func updateTimeline(mediaId: Int, time: Double, duration: Double) async {
        let settings = SettingsManager.shared.settings
        guard !settings.cubToken.isEmpty else { return }
        
        let url = URL(string: "\(baseURL)/timeline/update")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, val) in getHeaders() {
            request.setValue(val, forHTTPHeaderField: key)
        }
        
        let body: [String: Any] = [
            "id": mediaId,
            "time": time,
            "duration": duration
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        _ = try? await URLSession.shared.data(for: request)
    }
}
