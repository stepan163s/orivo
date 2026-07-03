import Foundation

public struct TraktPairingResponse: Decodable, Sendable {
    public let device_code: String
    public let user_code: String
    public let verification_url: String
    public let expires_in: Int
    public let interval: Int
}

public struct TraktTokenResponse: Decodable, Sendable {
    public let access_token: String?
    public let token_type: String?
    public let expires_in: Int?
    public let refresh_token: String?
    public let scope: String?
    public let created_at: Int?
}

@MainActor
public final class TraktClient: Sendable {
    public static let shared = TraktClient()
    
    private init() {}
    
    private var clientID: String {
        return SettingsManager.shared.settings.traktClientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var clientSecret: String {
        return SettingsManager.shared.settings.traktClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var accessToken: String {
        return SettingsManager.shared.settings.traktToken
    }
    
    /// Requests a new device coupling PIN code from Trakt
    public func requestPairingCode() async throws -> TraktPairingResponse {
        guard !clientID.isEmpty else {
            throw NSError(domain: "TraktClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Пожалуйста, укажите Trakt Client ID в настройках выше."])
        }
        
        let url = URL(string: "https://api.trakt.tv/oauth/device/code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        
        let body: [String: String] = [
            "client_id": clientID
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpRes = response as? HTTPURLResponse
        let code = httpRes?.statusCode ?? 0
        let bodyStr = String(data: data, encoding: .utf8) ?? ""
        LogManager.shared.log(serviceId: "system", text: "TraktClient: requestPairingCode response code: \(code), body: \(bodyStr)")
        
        guard code == 200 else {
            throw NSError(domain: "TraktClient", code: code, userInfo: [NSLocalizedDescriptionKey: "Failed to request Trakt pairing code (Status \(code)): \(bodyStr)"])
        }
        return try JSONDecoder().decode(TraktPairingResponse.self, from: data)
    }
    
    /// Polls Trakt for authorization token completion
    public func pollPairingStatus(deviceCode: String) async throws -> TraktTokenResponse {
        let url = URL(string: "https://api.trakt.tv/oauth/device/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        
        let body: [String: String] = [
            "code": deviceCode,
            "client_id": clientID,
            "client_secret": clientSecret
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 200 {
            return try JSONDecoder().decode(TraktTokenResponse.self, from: data)
        } else {
            return TraktTokenResponse(access_token: nil, token_type: nil, expires_in: nil, refresh_token: nil, scope: nil, created_at: nil)
        }
    }
    
    /// Sends a scrobble progress update to Trakt.tv
    public func scrobbleProgress(mediaId: Int, progress: Double) async {
        guard !accessToken.isEmpty else {
            LogManager.shared.log(serviceId: "system", text: "TraktClient: Scrobbling progress for TMDB ID \(mediaId): \(String(format: "%.1f", progress))% (Trakt account not connected)")
            return
        }
        
        let url = URL(string: "https://api.trakt.tv/scrobble/start")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        
        let body: [String: Any] = [
            "movie": [
                "ids": [
                    "tmdb": mediaId
                ]
            ],
            "progress": progress
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            LogManager.shared.log(serviceId: "system", text: "TraktClient: Scrobble progress response code: \(code)")
        } catch {
            LogManager.shared.log(serviceId: "system", text: "TraktClient: Scrobbling failed: \(error.localizedDescription)", isError: true)
        }
    }
    
    /// Sends a scrobble stop (mark watched) request to Trakt.tv
    public func scrobbleStop(mediaId: Int, progress: Double) async {
        guard !accessToken.isEmpty else {
            LogManager.shared.log(serviceId: "system", text: "TraktClient: Scrobbling stop for TMDB ID \(mediaId): \(String(format: "%.1f", progress))% (Trakt account not connected)")
            return
        }
        
        let url = URL(string: "https://api.trakt.tv/scrobble/stop")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        
        let body: [String: Any] = [
            "movie": [
                "ids": [
                    "tmdb": mediaId
                ]
            ],
            "progress": progress
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {}
    }
}
