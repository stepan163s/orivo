import Foundation
import Network
import WebKit
import AppKit

@MainActor
public final class SolverWebViewManager: NSObject, WKNavigationDelegate {
    public static let shared = SolverWebViewManager()
    
    private var webView: WKWebView?
    private var window: NSWindow?
    private var pendingCompletion: ((String?, [HTTPCookie], String?) -> Void)?
    
    private var solveTimer: Timer?
    private var solveTimeoutWorkItem: DispatchWorkItem?
    
    private override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        webView.navigationDelegate = self
        // Set standard Mac Safari user agent to ensure Cloudflare doesn't flag us as a bot
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        self.webView = webView
        
        // Host the WebView in an off-screen borderless window so Turnstile JS execution and layout runs at 100% speed
        let window = NSWindow(
            contentRect: CGRect(x: -2000, y: -2000, width: 1024, height: 768),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        self.window = window
    }
    
    public func solve(urlString: String, completion: @escaping (String?, [HTTPCookie], String?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil, [], nil)
            return
        }
        
        cancelPendingSolve()
        self.pendingCompletion = completion
        
        let request = URLRequest(url: url)
        webView?.load(request)
        
        startPolling(for: url)
    }
    
    private func cancelPendingSolve() {
        solveTimer?.invalidate()
        solveTimer = nil
        solveTimeoutWorkItem?.cancel()
        solveTimeoutWorkItem = nil
    }
    
    private func startPolling(for url: URL) {
        // Set a hard timeout of 15 seconds
        let timeoutItem = DispatchWorkItem { [weak self] in
            self?.finishSolve(status: .timeout)
        }
        self.solveTimeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeoutItem)
        
        // Poll for clearance cookies and page state every 500ms
        solveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkStatus(for: url)
            }
        }
    }
    
    private enum SolveStatus {
        case solved
        case timeout
    }
    
    private func checkStatus(for url: URL) {
        guard let webView = webView else { return }
        
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            
            // Check if Cloudflare's clearance cookie is set
            let hasClearance = cookies.contains { $0.name == "cf_clearance" }
            
            webView.evaluateJavaScript("document.title") { titleResult, _ in
                let title = titleResult as? String ?? ""
                
                webView.evaluateJavaScript("document.documentElement.outerHTML") { htmlResult, _ in
                    let html = htmlResult as? String ?? ""
                    
                    // Verify if Cloudflare challenge elements or title are active
                    let isChallengeActive = title.contains("Just a moment...") || 
                                           html.contains("cf-challenge") || 
                                           html.contains("challenge-platform") || 
                                           html.contains("Checking your browser")
                    
                    if hasClearance || (!isChallengeActive && !html.isEmpty) {
                        self.finishSolve(status: .solved, html: html, cookies: cookies)
                    }
                }
            }
        }
    }
    
    private func finishSolve(status: SolveStatus, html: String? = nil, cookies: [HTTPCookie] = []) {
        cancelPendingSolve()
        
        let finalHtml = html
        let finalCookies = cookies
        let userAgent = webView?.value(forKey: "userAgent") as? String ?? webView?.customUserAgent ?? ""
        
        if let completion = pendingCompletion {
            completion(finalHtml, finalCookies, userAgent)
            self.pendingCompletion = nil
        }
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishSolve(status: .timeout)
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishSolve(status: .timeout)
    }
}

/// A connection handler that correctly resolves TCP packet fragmentation for HTTP request parsing.
private final class SolverConnectionHandler {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()
    private let onComplete: (Data) -> Void
    private let onError: (Error) -> Void
    
    init(connection: NWConnection, queue: DispatchQueue, onComplete: @escaping (Data) -> Void, onError: @escaping (Error) -> Void) {
        self.connection = connection
        self.queue = queue
        self.onComplete = onComplete
        self.onError = onError
    }
    
    func start() {
        connection.start(queue: queue)
        readNext()
    }
    
    private func readNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                self.onError(error)
                return
            }
            
            if let data = data, !data.isEmpty {
                self.buffer.append(data)
                self.checkBuffer()
            } else if isComplete {
                self.onComplete(self.buffer)
            } else {
                self.connection.cancel()
            }
        }
    }
    
    private func checkBuffer() {
        // HTTP double line ending separator
        guard let separatorRange = buffer.range(of: Data([13, 10, 13, 10])) else {
            readNext()
            return
        }
        
        // Parse Content-Length header to determine full payload bounds
        let headersData = buffer.subdata(in: 0..<separatorRange.lowerBound)
        guard let headersString = String(data: headersData, encoding: .utf8) else {
            self.onError(NSError(domain: "SolverConnectionHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP headers encoding"]))
            return
        }
        
        var contentLength = 0
        let lines = headersString.components(separatedBy: "\r\n")
        for line in lines {
            let parts = line.components(separatedBy: ":")
            if parts.count >= 2 && parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                if let parsedLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                    contentLength = parsedLength
                    break
                }
            }
        }
        
        let totalRequiredBytes = separatorRange.upperBound + contentLength
        if buffer.count >= totalRequiredBytes {
            let fullRequest = buffer.subdata(in: 0..<totalRequiredBytes)
            onComplete(fullRequest)
        } else {
            readNext()
        }
    }
}

public final class SolverServer: @unchecked Sendable {
    public static let shared = SolverServer()
    
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.orivo.solverserver", qos: .userInitiated)
    private var activeHandlers: [UUID: SolverConnectionHandler] = [:]
    private let handlerLock = NSLock()
    
    private init() {}
    
    public func start() {
        guard listener == nil else { return }
        
        do {
            listener = try NWListener(using: .tcp, on: 8191) // Port 8191 is FlareSolverr's default port
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    LogManager.shared.log(serviceId: "system", text: "Native FlareSolverr bypass service started on port 8191.")
                case .failed(let error):
                    LogManager.shared.log(serviceId: "system", text: "Native FlareSolverr service failed to start: \(error.localizedDescription)", isError: true)
                default:
                    break
                }
            }
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.start(queue: queue)
        } catch {
            LogManager.shared.log(serviceId: "system", text: "Native FlareSolverr service init error: \(error.localizedDescription)", isError: true)
        }
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        handlerLock.lock()
        activeHandlers.removeAll()
        handlerLock.unlock()
        LogManager.shared.log(serviceId: "system", text: "Native FlareSolverr bypass service stopped.")
    }
    
    private func handleConnection(_ connection: NWConnection) {
        let handlerId = UUID()
        let handler = SolverConnectionHandler(
            connection: connection,
            queue: queue,
            onComplete: { [weak self] fullData in
                self?.processRequest(fullData, connection: connection)
                self?.removeHandler(id: handlerId)
            },
            onError: { [weak self] error in
                LogManager.shared.log(serviceId: "system", text: "SolverServer stream error: \(error.localizedDescription)", isError: true)
                connection.cancel()
                self?.removeHandler(id: handlerId)
            }
        )
        
        handlerLock.lock()
        activeHandlers[handlerId] = handler
        handlerLock.unlock()
        
        handler.start()
    }
    
    private func removeHandler(id: UUID) {
        handlerLock.lock()
        activeHandlers[id] = nil
        handlerLock.unlock()
    }
    
    private func processRequest(_ data: Data, connection: NWConnection) {
        let requestString = String(data: data, encoding: .utf8) ?? ""
        LogManager.shared.log(serviceId: "system", text: "SolverServer Request headers:\n\(requestString.components(separatedBy: "\r\n\r\n").first ?? "")")
        
        guard requestString.contains("POST /v1") else {
            LogManager.shared.log(serviceId: "system", text: "SolverServer: Request is not POST /v1. Ignoring.")
            sendResponse(body: "{}", connection: connection)
            return
        }
        
        guard let bodySeparatorRange = requestString.range(of: "\r\n\r\n") else {
            LogManager.shared.log(serviceId: "system", text: "SolverServer: No body payload separator found in HTTP request.", isError: true)
            sendResponse(body: "{\"status\": \"error\", \"message\": \"No body payload found\"}", connection: connection)
            return
        }
        
        let body = String(requestString[bodySeparatorRange.upperBound...])
        LogManager.shared.log(serviceId: "system", text: "SolverServer Request body: \(body)")
        guard let bodyData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let urlString = json["url"] as? String else {
            LogManager.shared.log(serviceId: "system", text: "SolverServer: Failed to parse body JSON or missing url key.", isError: true)
            sendResponse(body: "{\"status\": \"error\", \"message\": \"Invalid JSON or missing url parameter\"}", connection: connection)
            return
        }
        
        LogManager.shared.log(serviceId: "system", text: "SolverServer: Solving challenge for URL: \(urlString)")
        
        // Execute solver on the @MainActor
        DispatchQueue.main.async {
            SolverWebViewManager.shared.solve(urlString: urlString) { html, cookies, userAgent in
                self.queue.async {
                    LogManager.shared.log(serviceId: "system", text: "SolverServer: Solve completed. Cookies: \(cookies.count), UserAgent: \(userAgent ?? "")")
                    let responseJson = self.formatResponse(url: urlString, html: html ?? "", cookies: cookies, userAgent: userAgent ?? "")
                    self.sendResponse(body: responseJson, connection: connection)
                }
            }
        }
    }
    
    private func formatResponse(url: String, html: String, cookies: [HTTPCookie], userAgent: String) -> String {
        var cookieDicts: [[String: Any]] = []
        for cookie in cookies {
            cookieDicts.append([
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path,
                "expiry": Int(cookie.expiresDate?.timeIntervalSince1970 ?? 0)
            ])
        }
        
        let responseObj: [String: Any] = [
            "status": "ok",
            "message": "Challenge solved!",
            "solution": [
                "url": url,
                "status": 200,
                "cookies": cookieDicts,
                "userAgent": userAgent,
                "response": html
            ]
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: responseObj, options: []),
           let jsonStr = String(data: data, encoding: .utf8) {
            return jsonStr
        }
        return "{\"status\": \"error\"}"
    }
    
    private func sendResponse(body: String, connection: NWConnection) {
        let responseBodyData = body.data(using: .utf8) ?? Data()
        
        // Construct HTTP response headers explicitly with standard CRLF line endings
        let httpHeaders = [
            "HTTP/1.1 200 OK",
            "Content-Type: application/json; charset=utf-8",
            "Content-Length: \(responseBodyData.count)",
            "Access-Control-Allow-Origin: *",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        
        var payload = httpHeaders.data(using: .utf8) ?? Data()
        payload.append(responseBodyData)
        
        connection.send(
            content: payload,
            isComplete: true,
            completion: .contentProcessed({ _ in
                // Delay connection cancellation to allow client network buffers to consume response fully
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    connection.cancel()
                }
            })
        )
    }
}
