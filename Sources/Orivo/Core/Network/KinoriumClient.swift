import CryptoKit
import Foundation

public struct KinoriumWatchItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let originalTitle: String?
    public let year: String?
    public let posterURL: URL?
    public let kinoriumID: String?
    public let objectType: String?
}

@MainActor
public final class KinoriumClient: Sendable {
    public static let shared = KinoriumClient()
    
    private init() {}
    
    private let baseURL = URL(string: "https://api.kinorium.com/1.0.3/")!
    private let apiSalt = "Sole8dya$ovbDi9I$adta"
    private let userAgent = "Kinorium/1.56.0 (Android 16)"
    
    /// Authenticates with Kinorium using the same request signing scheme as the Android client.
    public func authenticate(email: String, password: String) async throws {
        guard !email.isEmpty, !password.isEmpty else {
            throw NSError(domain: "KinoriumClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Email и пароль не могут быть пустыми"])
        }
        
        let url = try signedURL(method: "userAuth")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "email", value: email),
            URLQueryItem(name: "password", value: password)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let responseString = String(data: data, encoding: .utf8) ?? ""
        
        LogManager.shared.log(serviceId: "system", text: "KinoriumClient: Authentication response status \(statusCode)")
        
        guard statusCode == 200 else {
            throw NSError(domain: "KinoriumClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Ошибка соединения с сервером Кинориум (Status \(statusCode))"])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "KinoriumClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать ответ сервера Кинориум"])
        }
        
        if let resultCode = json["resultCode"] as? Int, resultCode != 0 {
            let msg = json["resultMessage"] as? String ?? "Неизвестная ошибка авторизации"
            throw NSError(domain: "KinoriumClient", code: resultCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        
        let authPayload = extractAuthPayload(from: json, fallbackResponse: responseString)
        SettingsManager.shared.settings.kinoriumToken = authPayload.token
        SettingsManager.shared.settings.kinoriumEmail = authPayload.email ?? email
        SettingsManager.shared.saveSettings()
    }
    
    public func authenticateWithApple(accessTokenID: String, email: String, secret: String) async throws {
        guard !accessTokenID.isEmpty, !secret.isEmpty else {
            throw NSError(domain: "KinoriumClient", code: -5, userInfo: [NSLocalizedDescriptionKey: "Apple ID не вернул токен авторизации"])
        }
        
        let url = try signedURL(method: "userConnectExternal")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "type", value: "apple"),
            URLQueryItem(name: "access_token", value: accessTokenID),
            URLQueryItem(name: "access_token[id]", value: accessTokenID),
            URLQueryItem(name: "access_token[email]", value: email),
            URLQueryItem(name: "secret", value: secret)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let responseString = String(data: data, encoding: .utf8) ?? ""
        
        LogManager.shared.log(serviceId: "system", text: "KinoriumClient: Apple authentication response status \(statusCode)")
        
        guard statusCode == 200 else {
            throw NSError(domain: "KinoriumClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Ошибка соединения с сервером Кинориум (Status \(statusCode))"])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "KinoriumClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать ответ сервера Кинориум"])
        }
        
        if let resultCode = json["resultCode"] as? Int, resultCode != 0 {
            let msg = json["resultMessage"] as? String ?? "Неизвестная ошибка авторизации"
            throw NSError(domain: "KinoriumClient", code: resultCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "KinoriumClient", code: -6, userInfo: [NSLocalizedDescriptionKey: "Сервер Кинориум не вернул HTTP-ответ"])
        }
        
        let cookieHeader = sessionCookieHeader(from: httpResponse)
        guard !cookieHeader.isEmpty else {
            throw NSError(domain: "KinoriumClient", code: -7, userInfo: [NSLocalizedDescriptionKey: "Кинориум не вернул cookie авторизации"])
        }
        
        let authDict = (json["data"] as? [String: Any]) ?? json
        SettingsManager.shared.settings.kinoriumToken = cookieHeader
        SettingsManager.shared.settings.kinoriumEmail = firstString(in: authDict, keys: ["email"]) ?? email
        SettingsManager.shared.saveSettings()
        
        if responseString.contains("\"key\":false") {
            throw NSError(domain: "KinoriumClient", code: -8, userInfo: [NSLocalizedDescriptionKey: "Кинориум отклонил подпись запроса"])
        }
    }
    
    public func signedURL(method: String, queryItems: [URLQueryItem] = []) throws -> URL {
        var allItems = [URLQueryItem(name: "method", value: method)]
        allItems.append(contentsOf: queryItems)
        
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = allItems
        
        guard let encodedQuery = components.percentEncodedQuery else {
            throw NSError(domain: "KinoriumClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "Не удалось собрать параметры запроса Кинориум"])
        }
        
        let canonicalQuery = canonicalize(encodedQuery: encodedQuery)
        let key = sign(canonicalQuery: canonicalQuery)
        components.percentEncodedQuery = "\(canonicalQuery)&key=\(key)"
        
        guard let url = components.url else {
            throw NSError(domain: "KinoriumClient", code: -4, userInfo: [NSLocalizedDescriptionKey: "Не удалось собрать URL запроса Кинориум"])
        }
        return url
    }
    
    public func fetchFutureWatchlist(page: Int = 1, perPage: Int = 50) async throws -> [KinoriumWatchItem] {
        let cookieHeader = try await validSessionCookieHeader()
        let listsJSON = try await getJSON(
            method: "getUList",
            queryItems: [
                URLQueryItem(name: "user_id", value: "0"),
                URLQueryItem(name: "obj_ids", value: ""),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "perpage", value: "1000")
            ],
            cookieHeader: cookieHeader
        )
        
        let listsData = try requireSuccess(listsJSON)
        guard let lists = (listsData["ulist"] as? [[String: Any]]) else {
            return []
        }
        
        guard let futureList = lists.first(where: { ($0["special"] as? String) == "future" || ($0["title"] as? String) == "Буду смотреть" }),
              let listID = firstString(in: futureList, keys: ["ulist_id"]) else {
            return []
        }
        
        let listObjectJSON = try await getJSON(
            method: "getUListObj",
            queryItems: [
                URLQueryItem(name: "ulist_id", value: listID),
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "perpage", value: "\(perPage)")
            ],
            cookieHeader: cookieHeader
        )
        
        let listObjectData = try requireSuccess(listObjectJSON)
        return extractWatchItems(from: listObjectData)
    }
    
    private func canonicalize(encodedQuery: String) -> String {
        encodedQuery
            .replacingOccurrences(of: "+", with: "%20")
            .replacingOccurrences(of: "%2F", with: "/")
            .replacingOccurrences(of: "%3F", with: "?")
    }
    
    private func sign(canonicalQuery: String) -> String {
        let input = "?\(canonicalQuery)\(apiSalt)"
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private func getJSON(method: String, queryItems: [URLQueryItem], cookieHeader: String) async throws -> [String: Any] {
        let url = try signedURL(method: method, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            throw NSError(domain: "KinoriumClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Ошибка соединения с сервером Кинориум (Status \(statusCode))"])
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "KinoriumClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать ответ сервера Кинориум"])
        }
        return json
    }
    
    private func requireSuccess(_ json: [String: Any]) throws -> [String: Any] {
        if let keyOK = json["key"] as? Bool, !keyOK {
            throw NSError(domain: "KinoriumClient", code: -8, userInfo: [NSLocalizedDescriptionKey: "Кинориум отклонил подпись запроса"])
        }
        if let resultCode = json["resultCode"] as? Int, resultCode != 0 {
            let msg = json["resultMessage"] as? String ?? "Ошибка API Кинориум"
            throw NSError(domain: "KinoriumClient", code: resultCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return (json["data"] as? [String: Any]) ?? [:]
    }
    
    private func validSessionCookieHeader() async throws -> String {
        let storedToken = SettingsManager.shared.settings.kinoriumToken
        if storedToken.contains("auth="), storedToken.contains("PHPSESSID=") {
            return storedToken
        }
        
        let parsed = parseTokenPayload(storedToken)
        if let token = parsed["token"], let secret = parsed["secret"] {
            let email = SettingsManager.shared.settings.kinoriumEmail
            try await authenticateWithApple(accessTokenID: token, email: email, secret: secret)
            let exchangedToken = SettingsManager.shared.settings.kinoriumToken
            if exchangedToken.contains("auth="), exchangedToken.contains("PHPSESSID=") {
                return exchangedToken
            }
        }
        
        throw NSError(domain: "KinoriumClient", code: -9, userInfo: [NSLocalizedDescriptionKey: "Войдите в Кинориум в настройках, чтобы загрузить списки"])
    }
    
    private func parseTokenPayload(_ payload: String) -> [String: String] {
        payload.split(separator: ";").reduce(into: [String: String]()) { result, part in
            let pieces = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if pieces.count == 2 {
                result[pieces[0]] = pieces[1]
            }
        }
    }
    
    private func extractWatchItems(from data: [String: Any]) -> [KinoriumWatchItem] {
        let candidateKeys = ["movie", "movies", "items", "objects", "obj", "list", "results", "ulist_obj", "ulistObj"]
        for key in candidateKeys {
            if let items = data[key] as? [[String: Any]] {
                let parsed = items.compactMap(parseWatchItem)
                if !parsed.isEmpty {
                    return parsed
                }
            }
        }
        
        for value in data.values {
            if let items = value as? [[String: Any]] {
                let parsed = items.compactMap(parseWatchItem)
                if !parsed.isEmpty {
                    return parsed
                }
            }
        }
        
        return []
    }
    
    private func parseWatchItem(_ rawItem: [String: Any]) -> KinoriumWatchItem? {
        let item = (rawItem["movie"] as? [String: Any]) ?? (rawItem["obj"] as? [String: Any]) ?? rawItem
        let title = firstString(in: item, keys: ["title", "name", "name_ru", "name_original", "original_title", "movie_title"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty, title != "Буду смотреть", title != "Избранное" else {
            return nil
        }
        
        let id = firstString(in: item, keys: ["movie_id", "id", "obj_id", "kinorium_id"])
            ?? firstString(in: rawItem, keys: ["movie_id", "id", "obj_id", "kinorium_id"])
            ?? title
        let poster = firstString(in: item, keys: ["poster", "poster_url", "image", "image_url", "picture"])
            ?? firstString(in: rawItem, keys: ["poster", "poster_url", "image", "image_url", "picture"])
        
        return KinoriumWatchItem(
            id: "\(id)-\(title)",
            title: title,
            originalTitle: firstString(in: item, keys: ["name_original", "original_title", "title_en"]),
            year: firstString(in: item, keys: ["year", "production_year", "date"]),
            posterURL: poster.flatMap(URL.init(string:)),
            kinoriumID: firstString(in: item, keys: ["movie_id", "kinorium_id", "id"]),
            objectType: firstString(in: item, keys: ["obj_type", "type"])
        )
    }
    
    private func extractAuthPayload(from json: [String: Any], fallbackResponse: String) -> (token: String, email: String?) {
        let authDict = (json["data"] as? [String: Any]) ?? json
        let email = firstString(in: authDict, keys: ["email", "mail", "login"])
        let tokenKeys = ["token", "access_token", "auth", "ukey", "signature", "user_id"]
        let compactToken = tokenKeys
            .compactMap { key -> String? in
                guard let value = firstString(in: authDict, keys: [key]), !value.isEmpty else { return nil }
                return "\(key)=\(value)"
            }
            .joined(separator: "; ")
        
        return (compactToken.isEmpty ? fallbackResponse : compactToken, email)
    }
    
    private func sessionCookieHeader(from response: HTTPURLResponse) -> String {
        let responseCookies = HTTPCookie.cookies(withResponseHeaderFields: response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            if let key = item.key as? String, let value = item.value as? String {
                result[key] = value
            }
        }, for: baseURL)
        let storedCookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
        let sessionCookies = (responseCookies + storedCookies).filter { $0.name == "auth" || $0.name == "PHPSESSID" }
        let uniqueCookies = Dictionary(sessionCookies.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
        
        return uniqueCookies
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        .joined(separator: "; ")
    }
    
    private func firstString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String {
                return value
            }
            if let value = dict[key] as? CustomStringConvertible {
                return value.description
            }
        }
        return nil
    }
}
