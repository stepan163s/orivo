import Foundation
import WebKit
import Network
import AppKit

@MainActor
private final class SolveSession: NSObject, WKNavigationDelegate {
    let id: UUID
    let urlString: String
    let proxyHost: String?
    let proxyPort: Int?
    let completion: (String?, [HTTPCookie], String?) -> Void
    
    private var webView: WKWebView?
    private var window: NSWindow?
    private var solveTimer: Timer?
    private var solveTimeoutWorkItem: DispatchWorkItem?
    private var onFinished: (() -> Void)?
    private var startTime: Date = Date()
    private var isWindowShown = false
    
    init(id: UUID, urlString: String, proxyHost: String?, proxyPort: Int?, completion: @escaping (String?, [HTTPCookie], String?) -> Void, onFinished: @escaping () -> Void) {
        self.id = id
        self.urlString = urlString
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.completion = completion
        self.onFinished = onFinished
        super.init()
    }
    
    func start() {
        self.startTime = Date()
        guard let url = URL(string: urlString) else {
            finish(html: nil, cookies: [], userAgent: nil)
            return
        }
        
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = ""
        config.websiteDataStore = .default()
        
        let userContentController = WKUserContentController()
        let jsSource = """
        setInterval(function() {
            var cb = document.querySelector('input[type="checkbox"]');
            if (cb && !cb.checked) {
                cb.click();
                cb.dispatchEvent(new Event('change'));
            }
            var stage = document.querySelector('#challenge-stage') || document.querySelector('.ct-checkbox-label') || document.querySelector('.mark') || document.querySelector('#cf-stage');
            if (stage) {
                stage.click();
            }
        }, 500);
        """
        let userScript = WKUserScript(source: jsSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        userContentController.addUserScript(userScript)
        config.userContentController = userContentController
        
        let settings = SettingsManager.shared.settings
        let finalHost: String?
        let finalPort: Int?
        
        if settings.useSolverProxy {
            finalHost = settings.solverProxyHost
            finalPort = settings.solverProxyPort
        } else if let pHost = proxyHost, let pPort = proxyPort {
            finalHost = pHost
            finalPort = pPort
        } else {
            finalHost = nil
            finalPort = nil
        }
        
        if #available(macOS 14.0, *), let pHost = finalHost, let pPort = finalPort {
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(pHost), port: NWEndpoint.Port(rawValue: UInt16(pPort)) ?? 12334)
            let proxyConfig = ProxyConfiguration(httpCONNECTProxy: endpoint)
            config.websiteDataStore.proxyConfigurations = [proxyConfig]
            LogManager.shared.log(serviceId: "system", text: "SolverServer: WKWebView configured with proxy \(pHost):\(pPort)")
        }
        
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        
        // Host the WebView in a window positioned partially on-screen (only 1 pixel visible at bottom-left: 0,0)
        // This forces macOS WindowServer to keep GPU acceleration and JS execution active on 100% speed.
        let window = NSWindow(
            contentRect: CGRect(x: -1023, y: -767, width: 1024, height: 768),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.alphaValue = 1.0
        window.orderFrontRegardless()
        self.window = window
        
        let store = config.websiteDataStore
        let targetHost = url.host?.lowercased() ?? ""
        
        store.httpCookieStore.getAllCookies { [weak self, weak webView] cookies in
            guard let self = self, let webView = webView else { return }
            let dispatchGroup = DispatchGroup()
            
            for cookie in cookies {
                let domain = cookie.domain.lowercased()
                if targetHost.contains(domain) || domain.contains(targetHost) {
                    dispatchGroup.enter()
                    store.httpCookieStore.delete(cookie) {
                        dispatchGroup.leave()
                    }
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                let request = URLRequest(url: url)
                webView.load(request)
                self.startPolling(for: url)
            }
        }
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
            self?.finish(html: nil, cookies: [], userAgent: nil)
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
    
    private func checkStatus(for url: URL) {
        guard let webView = webView else { return }
        
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            
            // Filter cookies to belong only to the target host to prevent leaking other session cookies
            let targetHost = url.host?.lowercased() ?? ""
            let hostParts = targetHost.split(separator: ".")
            let mainHostPart = String(hostParts.first(where: { $0 != "www" }) ?? "")
            
            let filteredCookies = cookies.filter { cookie in
                let domain = cookie.domain.lowercased()
                return (!mainHostPart.isEmpty && domain.contains(mainHostPart)) || targetHost.contains(domain) || domain.contains(targetHost)
            }
            
            let hasClearance = filteredCookies.contains { $0.name == "cf_clearance" }
            let isDoneLoading = !webView.isLoading
            
            // Check if Cloudflare challenge is still active by examining the webview title
            let title = webView.title ?? ""
            let isChallengeActive = title.contains("Just a moment...") || title.contains("Checking your browser")
            
            let solveSuccessful = hasClearance && !isChallengeActive
            let normalLoadComplete = isDoneLoading && !isChallengeActive
            
            let timeSinceStart = Date().timeIntervalSince(self.startTime)
            LogManager.shared.log(serviceId: "system", text: "SolverServer Status: title='\(title)', hasClearance=\(hasClearance), isDoneLoading=\(isDoneLoading), isChallengeActive=\(isChallengeActive), elapsed=\(timeSinceStart)")
            
            if isChallengeActive && !hasClearance {
                let jsFindIframe = """
                (function() {
                    var iframe = document.querySelector('iframe[src*="challenges.cloudflare.com"]') || 
                                 document.querySelector('iframe[src*="turnstile"]') ||
                                 document.querySelector('.cf-turnstile iframe') ||
                                 document.querySelector('iframe');
                    if (iframe) {
                        var rect = iframe.getBoundingClientRect();
                        if (rect.width > 0 && rect.height > 0) {
                            return {
                                x: rect.left + rect.width / 2,
                                y: rect.top + rect.height / 2,
                                found: true
                            };
                        }
                    }
                    return { found: false };
                })()
                """
                webView.evaluateJavaScript(jsFindIframe) { [weak self, weak webView] result, _ in
                    guard let self = self, let webView = webView, let dict = result as? [String: Any], let found = dict["found"] as? Bool, found else { return }
                    guard let x = dict["x"] as? Double, let y = dict["y"] as? Double else { return }
                    
                    let clickX = CGFloat(x)
                    let clickY = webView.bounds.height - CGFloat(y)
                    let windowPoint = CGPoint(x: clickX, y: clickY)
                    
                    LogManager.shared.log(serviceId: "system", text: "SolverServer: Auto-clicking Turnstile iframe at (\(clickX), \(clickY))")
                    
                    let eventDown = NSEvent.mouseEvent(
                        with: .leftMouseDown,
                        location: windowPoint,
                        modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: self.window?.windowNumber ?? 0,
                        context: nil,
                        eventNumber: 0,
                        clickCount: 1,
                        pressure: 1.0
                    )
                    let eventUp = NSEvent.mouseEvent(
                        with: .leftMouseUp,
                        location: windowPoint,
                        modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: self.window?.windowNumber ?? 0,
                        context: nil,
                        eventNumber: 0,
                        clickCount: 1,
                        pressure: 0.0
                    )
                    
                    if let eventDown = eventDown, let eventUp = eventUp {
                        webView.mouseDown(with: eventDown)
                        webView.mouseUp(with: eventUp)
                    }
                }
            }
            
            if isChallengeActive && !hasClearance && timeSinceStart >= 10.0 {
                self.showWindowInteractive()
            }
            
            if solveSuccessful || normalLoadComplete {
                // Stop the check timer immediately
                self.cancelPendingSolve()
                
                // Fetch the HTML content once and finish
                webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] htmlResult, _ in
                    guard let self = self else { return }
                    let html = htmlResult as? String ?? ""
                    let userAgent = webView.value(forKey: "userAgent") as? String ?? webView.customUserAgent ?? ""
                    self.finish(html: html, cookies: filteredCookies, userAgent: userAgent)
                }
            }
        }
    }
    
    private func showWindowInteractive() {
        guard !isWindowShown, let window = window else { return }
        isWindowShown = true
        
        LogManager.shared.log(serviceId: "system", text: "SolverServer: CF challenge active for >2s, showing interactive verification window.")
        
        DispatchQueue.main.async { [weak window] in
            guard let window = window else { return }
            window.styleMask = [.titled, .closable]
            window.title = "Orivo - Проверка Cloudflare (1337x)"
            
            if let screen = NSScreen.main {
                let screenRect = screen.visibleFrame
                let width: CGFloat = 460
                let height: CGFloat = 360
                let x = (screenRect.width - width) / 2 + screenRect.minX
                let y = (screenRect.height - height) / 2 + screenRect.minY
                
                window.setFrame(CGRect(x: x, y: y, width: width, height: height), display: true)
                window.ignoresMouseEvents = false
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    private func finish(html: String?, cookies: [HTTPCookie], userAgent: String?) {
        cancelPendingSolve()
        
        DispatchQueue.main.async { [weak window] in
            window?.close()
        }
        
        completion(html, cookies, userAgent)
        
        // Clean up references and window context
        self.webView?.navigationDelegate = nil
        self.webView = nil
        self.window?.contentView = nil
        self.window = nil
        
        onFinished?()
        onFinished = nil
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        LogManager.shared.log(serviceId: "system", text: "SolverServer WebView didFailProvisionalNavigation: \(error.localizedDescription) (code: \((error as NSError).code))", isError: true)
        finish(html: nil, cookies: [], userAgent: nil)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        LogManager.shared.log(serviceId: "system", text: "SolverServer WebView didFail: \(error.localizedDescription) (code: \((error as NSError).code))", isError: true)
        finish(html: nil, cookies: [], userAgent: nil)
    }
}

@MainActor
public final class SolverWebViewManager: NSObject {
    public static let shared = SolverWebViewManager()
    
    private var activeSessions: [UUID: SolveSession] = [:]
    
    private override init() {
        super.init()
    }
    
    public func solve(urlString: String, proxyHost: String?, proxyPort: Int?, completion: @escaping (String?, [HTTPCookie], String?) -> Void) {
        let sessionId = UUID()
        let session = SolveSession(id: sessionId, urlString: urlString, proxyHost: proxyHost, proxyPort: proxyPort, completion: completion) { [weak self] in
            guard let self = self else { return }
            self.activeSessions[sessionId] = nil
        }
        activeSessions[sessionId] = session
        session.start()
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
        
        Task { @MainActor in
            let port = ServiceManager.shared.resolvedFlareSolverrPort
            do {
                let resolvedPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? 8191
                let listener = try NWListener(using: .tcp, on: resolvedPort)
                self.listener = listener
                
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        LogManager.shared.log(serviceId: "system", text: "Native FlareSolverr bypass service started on port \(port).")
                    case .failed(let error):
                        LogManager.shared.log(serviceId: "system", text: "Native FlareSolverr service failed to start on port \(port): \(error.localizedDescription)", isError: true)
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handleConnection(connection)
                }
                listener.start(queue: self.queue)
            } catch {
                LogManager.shared.log(serviceId: "system", text: "Native FlareSolverr service init error on port \(port): \(error.localizedDescription)", isError: true)
            }
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
        
        let proxyDict = json["proxy"] as? [String: Any]
        let proxyUrlString = proxyDict?["url"] as? String ?? ""
        var proxyHost: String? = nil
        var proxyPort: Int? = nil
        if let proxyURL = URL(string: proxyUrlString) {
            proxyHost = proxyURL.host
            proxyPort = proxyURL.port
        }
        
        LogManager.shared.log(serviceId: "system", text: "SolverServer: Solving challenge for URL: \(urlString)")
        
        // Execute solver on the @MainActor
        DispatchQueue.main.async {
            SolverWebViewManager.shared.solve(urlString: urlString, proxyHost: proxyHost, proxyPort: proxyPort) { html, cookies, userAgent in
                self.queue.async {
                    LogManager.shared.log(serviceId: "system", text: "SolverServer: Solve completed. Cookies: \(cookies.count), UserAgent: \(userAgent ?? "")")
                    let responseJson = self.formatResponse(url: urlString, html: html ?? "", cookies: cookies, userAgent: userAgent ?? "")
                    self.sendResponse(body: responseJson, connection: connection)
                }
            }
        }
    }
    
    private func formatResponse(url: String, html: String, cookies: [HTTPCookie], userAgent: String) -> String {
        let cleanUA = userAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty 
            ? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15" 
            : userAgent
            
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
                "userAgent": cleanUA,
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
