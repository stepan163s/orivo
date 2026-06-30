import Foundation
import Network
import WebKit

@MainActor
public final class SolverWebViewManager: NSObject, WKNavigationDelegate {
    public static let shared = SolverWebViewManager()
    
    private var webView: WKWebView?
    private var pendingCompletion: ((String?, [HTTPCookie], String?) -> Void)?
    
    private override init() {
        super.init()
        let config = WKWebViewConfiguration()
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView?.navigationDelegate = self
    }
    
    public func solve(urlString: String, completion: @escaping (String?, [HTTPCookie], String?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil, [], nil)
            return
        }
        self.pendingCompletion = completion
        
        let request = URLRequest(url: url)
        webView?.load(request)
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let userAgent = webView.value(forKey: "userAgent") as? String ?? ""
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            webView.evaluateJavaScript("document.documentElement.outerHTML") { htmlResult, _ in
                let html = htmlResult as? String ?? ""
                self?.pendingCompletion?(html, cookies, userAgent)
                self?.pendingCompletion = nil
            }
        }
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pendingCompletion?(nil, [], nil)
        pendingCompletion = nil
    }
}

public final class SolverServer: @unchecked Sendable {
    public static let shared = SolverServer()
    
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.orivo.solverserver", qos: .userInitiated)
    
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
        LogManager.shared.log(serviceId: "system", text: "Native FlareSolverr bypass service stopped.")
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        LogManager.shared.log(serviceId: "system", text: "SolverServer: Received connection.")
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            if let error = error {
                LogManager.shared.log(serviceId: "system", text: "SolverServer connection receive error: \(error.localizedDescription)", isError: true)
                connection.cancel()
                return
            }
            guard let data = data, !data.isEmpty else {
                LogManager.shared.log(serviceId: "system", text: "SolverServer: Received empty data or EOF.")
                connection.cancel()
                return
            }
            LogManager.shared.log(serviceId: "system", text: "SolverServer: Received \(data.count) bytes.")
            self?.processRequest(data, connection: connection)
        }
    }
    
    private func processRequest(_ data: Data, connection: NWConnection) {
        let requestString = String(data: data, encoding: .utf8) ?? ""
        LogManager.shared.log(serviceId: "system", text: "SolverServer Request headers:\n\(requestString.components(separatedBy: "\r\n\r\n").first ?? "")")
        
        guard requestString.contains("POST /v1") else {
            LogManager.shared.log(serviceId: "system", text: "SolverServer: Request is not POST /v1. Ignoring.")
            sendResponse(body: "{}", connection: connection)
            return
        }
        
        let components = requestString.components(separatedBy: "\r\n\r\n")
        guard components.count >= 2 else {
            LogManager.shared.log(serviceId: "system", text: "SolverServer: No body payload found in HTTP request.", isError: true)
            sendResponse(body: "{\"status\": \"error\", \"message\": \"No body payload found\"}", connection: connection)
            return
        }
        
        let body = components[1]
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
