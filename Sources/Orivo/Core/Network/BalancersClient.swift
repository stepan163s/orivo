import Foundation

public struct StreamQuality: Identifiable, Hashable, Sendable {
    public var id: String { quality }
    public let quality: String // e.g. "1080p", "720p", "4K"
    public let url: String
}

public struct BalancerStream: Identifiable, Hashable, Sendable {
    public var id: String { translation + "-" + String(qualities.hashValue) }
    public let translation: String // e.g. "Дубляж", "HDRezka Studio"
    public let qualities: [StreamQuality]
}

public final class BalancersClient: Sendable {
    public static let shared = BalancersClient()
    
    private init() {}
    
    private var rezkaBaseURL: String {
        let customUrl = DispatchQueue.main.sync { SettingsManager.shared.settings.rezkaMirrorURL }
        let trimmed = customUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://rezka.ag" : trimmed
    }
    
    /// Decrypts HDRezka's base64 obfuscated stream URLs
    public func decryptRezkaURL(_ urlStr: String) -> String {
        if urlStr.hasPrefix("[") || urlStr.hasPrefix("http") {
            return urlStr
        }
        
        var url = urlStr
        if url.hasPrefix("#h") {
            url = String(url.dropFirst(2))
        }
        
        let trashList = [
            "//_//",
            "IyMjI14hISMjIUBA",
            "QEBAQEAhIyMhXl5e",
            "JCQhIUAkJEBeIUAjJCRA",
            "JCQjISFAIyFAIyM=",
            "Xl5eIUAjIyEhIyM="
        ]
        
        for _ in 1...2 {
            for trash in trashList {
                url = url.replacingOccurrences(of: trash, with: "")
            }
        }
        
        if let data = Data(base64Encoded: url), let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        return urlStr
    }
    
    /// Searches HDRezka by title and returns streaming options
    public func fetchRezkaStreams(title: String, year: String?) async throws -> [BalancerStream] {
        LogManager.shared.log(serviceId: "system", text: "BalancersClient: Searching HDRezka for title: \(title) (\(year ?? ""))")
        
        // 1. Search Query
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let searchURL = URL(string: "\(rezkaBaseURL)/search/?do=search&subaction=search&story=\(encodedTitle)")!
        
        var request = URLRequest(url: searchURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        let (searchHTMLData, _) = try await URLSession.shared.data(for: request)
        guard let searchHTML = String(data: searchHTMLData, encoding: .utf8) else {
            return []
        }
        
        // 2. Parse search results using regex to find target page URL
        // Example match: <a href="https://rezka.ag/movies/drama/12345-movie.html">Movie Title (Year)</a>
        let itemPattern = #"href="([^"]+?-\w+?\.html)">(.*?)(?:\s*\((\d{4})\))?</a>"#
        let regex = try NSRegularExpression(pattern: itemPattern, options: [])
        let range = NSRange(searchHTML.startIndex..<searchHTML.endIndex, in: searchHTML)
        
        var targetPageURL: String? = nil
        
        for match in regex.matches(in: searchHTML, options: [], range: range) {
            if let urlRange = Range(match.range(at: 1), in: searchHTML),
               let titleRange = Range(match.range(at: 2), in: searchHTML) {
                let foundURL = String(searchHTML[urlRange])
                let foundTitle = String(searchHTML[titleRange]).lowercased()
                
                var foundYear: String? = nil
                if match.numberOfRanges > 3, let yearRange = Range(match.range(at: 3), in: searchHTML) {
                    foundYear = String(searchHTML[yearRange])
                }
                
                // Match criteria: title and optional year check
                if foundTitle.contains(title.lowercased()) {
                    if let targetYear = year, let currentYear = foundYear, targetYear == currentYear {
                        targetPageURL = foundURL
                        break
                    } else if targetPageURL == nil {
                        // Fallback: match first found URL with matching title
                        targetPageURL = foundURL
                    }
                }
            }
        }
        
        guard let pageURLString = targetPageURL, let pageURL = URL(string: pageURLString) else {
            LogManager.shared.log(serviceId: "system", text: "BalancersClient: No matching HDRezka page found.")
            return []
        }
        
        LogManager.shared.log(serviceId: "system", text: "BalancersClient: Found HDRezka page: \(pageURLString)")
        
        // 3. Fetch target page and extract movie ID / translator IDs
        var pageRequest = URLRequest(url: pageURL)
        pageRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        let (pageData, _) = try await URLSession.shared.data(for: pageRequest)
        guard let pageHTML = String(data: pageData, encoding: .utf8) else {
            return []
        }
        
        // Extract movie ID
        // Often defined as data-id="12345" or inside initCDNMoviesEvents(12345, ...
        var movieId: String? = nil
        if let idMatch = pageHTML.range(of: #"data-id="(\d+)""#, options: .regularExpression) {
            let sub = pageHTML[idMatch]
            movieId = String(sub.split(separator: "\"")[1])
        }
        
        // Extract translators (audio tracks)
        // Typically `<li class="b-translator__item" data-translator_id="123" title="Translator Name">`
        let translatorPattern = #"data-translator_id="(\d+)"\s*(?:title="([^"]+)")?"#
        let transRegex = try NSRegularExpression(pattern: translatorPattern, options: [])
        let pageRange = NSRange(pageHTML.startIndex..<pageHTML.endIndex, in: pageHTML)
        
        var translators: [(id: String, name: String)] = []
        for match in transRegex.matches(in: pageHTML, options: [], range: pageRange) {
            if let idRange = Range(match.range(at: 1), in: pageHTML) {
                let transId = String(pageHTML[idRange])
                var transName = "Default"
                if match.numberOfRanges > 2, let nameRange = Range(match.range(at: 2), in: pageHTML) {
                    transName = String(pageHTML[nameRange])
                }
                translators.append((id: transId, name: transName))
            }
        }
        
        guard let resolvedMovieId = movieId else {
            LogManager.shared.log(serviceId: "system", text: "BalancersClient: Failed to resolve HDRezka Movie ID.", isError: true)
            return []
        }
        
        // If no translators parsed, add default/empty translator ID
        if translators.isEmpty {
            translators.append((id: "1", name: "Оригинал / Стандартный"))
        }
        
        LogManager.shared.log(serviceId: "system", text: "BalancersClient: Resolved MovieID: \(resolvedMovieId), translators count: \(translators.count)")
        
        var resultStreams: [BalancerStream] = []
        
        // 4. Fetch streams for each translator from the AJAX endpoint
        for trans in translators {
            do {
                let ajaxURL = URL(string: "\(rezkaBaseURL)/ajax/get_cdn_series/")!
                var ajaxRequest = URLRequest(url: ajaxURL)
                ajaxRequest.httpMethod = "POST"
                ajaxRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                ajaxRequest.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                ajaxRequest.setValue("\(rezkaBaseURL)/", forHTTPHeaderField: "Referer")
                
                let bodyParams = "id=\(resolvedMovieId)&translator_id=\(trans.id)&action=get_movie"
                ajaxRequest.httpBody = bodyParams.data(using: .utf8)
                
                let (ajaxData, _) = try await URLSession.shared.data(for: ajaxRequest)
                if let json = try? JSONSerialization.jsonObject(with: ajaxData) as? [String: Any],
                   let success = json["success"] as? Bool, success,
                   let cipheredUrl = json["url"] as? String {
                    
                    let decodedUrl = decryptRezkaURL(cipheredUrl)
                    let streamQualities = parseQualities(decodedUrl)
                    if !streamQualities.isEmpty {
                        resultStreams.append(BalancerStream(translation: trans.name, qualities: streamQualities))
                    }
                }
            } catch {
                LogManager.shared.log(serviceId: "system", text: "BalancersClient: Failed to fetch translator streams: \(error.localizedDescription)", isError: true)
            }
        }
        
        return resultStreams
    }
    
    /// Parses quality URL links from the decoded string format
    /// Format example: [360p]https://... or [720p]https://...
    private func parseQualities(_ rawDecoded: String) -> [StreamQuality] {
        var qualities: [StreamQuality] = []
        
        let streams = rawDecoded.components(separatedBy: " or ")
        let pattern = #"\[(.*?)\](https?://[^\s,]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        
        for stream in streams {
            let range = NSRange(stream.startIndex..<stream.endIndex, in: stream)
            if let match = regex.firstMatch(in: stream, options: [], range: range),
               let qRange = Range(match.range(at: 1), in: stream),
               let urlRange = Range(match.range(at: 2), in: stream) {
                let qLabel = String(stream[qRange])
                let streamURL = String(stream[urlRange])
                qualities.append(StreamQuality(quality: qLabel, url: streamURL))
            }
        }
        
        return qualities
    }
}
