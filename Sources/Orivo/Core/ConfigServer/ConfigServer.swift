import Foundation
import Network

private struct SendableConnection: @unchecked Sendable {
    let connection: NWConnection
}

private final class ConfigConnectionHandler: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()
    private let onComplete: @Sendable (Data) -> Void
    private let onError: @Sendable (Error) -> Void
    
    init(connection: NWConnection, queue: DispatchQueue, onComplete: @escaping @Sendable (Data) -> Void, onError: @escaping @Sendable (Error) -> Void) {
        self.connection = connection
        self.queue = queue
        self.onComplete = onComplete
        self.onError = onError
    }
    
    func start() {
        connection.start(queue: queue)
        readNext()
    }
    
    func cancel() {
        connection.cancel()
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
                self.onError(NSError(domain: "ConfigConnectionHandler", code: -2, userInfo: [NSLocalizedDescriptionKey: "Connection closed unexpectedly"]))
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
            self.onError(NSError(domain: "ConfigConnectionHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP headers encoding"]))
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

public final class ConfigServer: @unchecked Sendable {
    public static let shared = ConfigServer()
    
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.orivo.configserver", qos: .background)
    private var activeHandlers: [UUID: ConfigConnectionHandler] = [:]
    private let handlerLock = NSLock()
    
    private init() {}
    
    public func start() {
        guard listener == nil else { return }
        
        Task { @MainActor in
            let port = ServiceManager.shared.resolvedConfigServerPort
            do {
                let resolvedPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? 8098
                let listener = try NWListener(using: .tcp, on: resolvedPort)
                self.listener = listener
                
                listener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        LogManager.shared.log(serviceId: "system", text: "Auto-config server started on port \(port).")
                    case .failed(let error):
                        LogManager.shared.log(serviceId: "system", text: "Auto-config server failed to start on port \(port): \(error.localizedDescription)", isError: true)
                        self?.listener = nil
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handleConnection(connection)
                }
                listener.start(queue: self.queue)
            } catch {
                LogManager.shared.log(serviceId: "system", text: "Auto-config server init error on port \(port): \(error.localizedDescription)", isError: true)
            }
        }
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        handlerLock.lock()
        activeHandlers.removeAll()
        handlerLock.unlock()
        LogManager.shared.log(serviceId: "system", text: "Auto-config server stopped.")
    }
    
    private func handleConnection(_ connection: NWConnection) {
        let handlerId = UUID()
        let wrappedConnection = SendableConnection(connection: connection)
        let handler = ConfigConnectionHandler(
            connection: connection,
            queue: queue,
            onComplete: { [weak self, wrappedConnection, handlerId] fullData in
                Task { [weak self, wrappedConnection] in
                    await self?.processRequest(fullData, connection: wrappedConnection)
                }
                self?.removeHandler(id: handlerId)
            },
            onError: { [weak self, wrappedConnection, handlerId] error in
                LogManager.shared.log(serviceId: "system", text: "ConfigServer stream error: \(error.localizedDescription)", isError: true)
                wrappedConnection.connection.cancel()
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
    
    private func processRequest(_ data: Data, connection wrapped: SendableConnection) async {
        let connection = wrapped.connection
        
        guard let separatorRange = data.range(of: Data([13, 10, 13, 10])) else {
            connection.cancel()
            return
        }
        
        let headersData = data.subdata(in: 0..<separatorRange.lowerBound)
        guard let headersString = String(data: headersData, encoding: .utf8) else {
            connection.cancel()
            return
        }
        
        let headerLines = headersString.components(separatedBy: "\r\n")
        guard let firstLine = headerLines.first else { connection.cancel(); return }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { connection.cancel(); return }
        
        let method = parts[0]
        let path = parts[1]
        
        LogManager.shared.log(serviceId: "system", text: "ConfigServer: Received \(method) request for \(path)")
        
        // Handle CORS preflight
        if method == "OPTIONS" {
            sendPreflightResponse(connection: connection)
            return
        }
        
        // Parse Content-Length to slice the body exactly
        var contentLength = 0
        for line in headerLines.dropFirst() {
            let components = line.components(separatedBy: ":")
            if components.count >= 2 && components[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                if let parsedLength = Int(components[1].trimmingCharacters(in: .whitespaces)) {
                    contentLength = parsedLength
                    break
                }
            }
        }
        
        // Extract the exact body data
        let bodyData: Data?
        if contentLength > 0 {
            let bodyStart = separatorRange.upperBound
            let bodyEnd = min(bodyStart + contentLength, data.count)
            bodyData = data.subdata(in: bodyStart..<bodyEnd)
        } else {
            bodyData = nil
        }
        
        let (settings, torrPort, jackettPort) = await MainActor.run {
            (SettingsManager.shared.settings, ServiceManager.shared.resolvedTorrServerPort, ServiceManager.shared.resolvedJackettPort)
        }
        
        var headersToForward: [String: String] = [:]
        for line in headerLines.dropFirst() {
            let components = line.components(separatedBy: ":")
            if components.count >= 2 {
                let key = components[0].trimmingCharacters(in: .whitespaces)
                let val = components.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                let lowerKey = key.lowercased()
                if lowerKey != "host" && lowerKey != "connection" && lowerKey != "accept-encoding" {
                    headersToForward[key] = val
                }
            }
        }
        
        // CORS proxy: forward /jackett/* → http://127.0.0.1:resolvedJackettPort/* (or external host)
        if path.hasPrefix("/jackett") {
            let jackettPath = String(path.dropFirst("/jackett".count))
            let upstreamBase = (settings.useExternalServers && !settings.externalJackettHost.isEmpty)
                ? settings.externalJackettHost
                : "http://127.0.0.1:\(jackettPort)"
            var jackettURL = upstreamBase + (jackettPath.isEmpty ? "/" : jackettPath)
            
            // Resolve the real key on the async path and replace/inject it
            let realKey = await JackettClient.shared.getJackettAPIKey()
            if !realKey.isEmpty {
                if jackettURL.contains("apikey=") {
                    let pattern = "apikey=[^&]+"
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                        let range = NSRange(jackettURL.startIndex..<jackettURL.endIndex, in: jackettURL)
                        jackettURL = regex.stringByReplacingMatches(in: jackettURL, options: [], range: range, withTemplate: "apikey=\(realKey)")
                    }
                } else if jackettURL.contains("/results") || jackettURL.contains("/api/v2.0") {
                    let separator = jackettURL.contains("?") ? "&" : "?"
                    jackettURL += "\(separator)apikey=\(realKey)"
                }
            }
            
            proxyRequest(urlString: jackettURL, method: method, headers: headersToForward, body: bodyData, connection: connection)
            return
        }
        
        // CORS proxy: forward /torrserver/* → http://127.0.0.1:resolvedTorrServerPort/* (or external host)
        if path.hasPrefix("/torrserver") {
            let torrPath = String(path.dropFirst("/torrserver".count))
            let upstreamBase = (settings.useExternalServers && !settings.externalTorrServerHost.isEmpty)
                ? settings.externalTorrServerHost
                : "http://127.0.0.1:\(torrPort)"
            let torrURL = upstreamBase + (torrPath.isEmpty ? "/" : torrPath)
            proxyRequest(urlString: torrURL, method: method, headers: headersToForward, body: bodyData, connection: connection)
            return
        }
        
        // Static route: orivo.js configuration helper (legacy)
        if path.contains("orivo.js") {
            sendTextResponse(body: buildOrivoJS(), contentType: "application/javascript", connection: connection)
            return
        }
        
        // Default: status ping
        sendTextResponse(body: "{\"status\": \"online\", \"version\": \"1.0\"}", contentType: "application/json", connection: connection)
    }
    
    // MARK: - CORS proxy forwarding
    
    private func proxyRequest(urlString: String, method: String, headers: [String: String], body: Data?, connection: NWConnection) {
        // Pre-encode raw square brackets to prevent Swift's URL(string:) from triggering double-encoding
        let cleanURLString = urlString
            .replacingOccurrences(of: "[", with: "%5B")
            .replacingOccurrences(of: "]", with: "%5D")
            
        guard let url = URL(string: cleanURLString) else {
            sendTextResponse(body: "{\"error\": \"Invalid proxy URL\"}", contentType: "application/json", connection: connection)
            return
        }
        
        LogManager.shared.log(serviceId: "system", text: "ConfigServer: Proxying \(method) to upstream URL: \(urlString)")
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        for (key, val) in headers {
            urlRequest.setValue(val, forHTTPHeaderField: key)
        }
        if let body = body, !body.isEmpty && method != "GET" && method != "HEAD" {
            urlRequest.httpBody = body
        }
        
        let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let error = error {
                LogManager.shared.log(serviceId: "system", text: "ConfigServer: Proxy error: \(error.localizedDescription) for \(urlString)", isError: true)
                let bodyStr = "{\"error\": \"\(error.localizedDescription)\"}"
                self.sendTextResponse(body: bodyStr, contentType: "application/json", connection: connection)
                return
            }
            
            guard let data = data else {
                self.sendTextResponse(body: "{\"error\": \"No data from upstream\"}", contentType: "application/json", connection: connection)
                return
            }
            
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 200
            let upstreamContentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "application/json; charset=utf-8"
            
            LogManager.shared.log(serviceId: "system", text: "ConfigServer: Upstream response status \(httpStatus), content-type \(upstreamContentType) for \(urlString)")
            
            // Inject CORS headers into the proxied response
            let headers = [
                "HTTP/1.1 \(httpStatus) OK",
                "Content-Type: \(upstreamContentType)",
                "Content-Length: \(data.count)",
                "Access-Control-Allow-Origin: *",
                "Access-Control-Allow-Methods: GET, POST, OPTIONS",
                "Access-Control-Allow-Headers: Content-Type, Authorization",
                "Connection: close",
                "",
                ""
            ].joined(separator: "\r\n")
            
            var payload = headers.data(using: .utf8) ?? Data()
            payload.append(data)
            
            connection.send(
                content: payload,
                isComplete: true,
                completion: .contentProcessed({ _ in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                        connection.cancel()
                    }
                })
            )
        }
        task.resume()
    }
    
    // MARK: - Response helpers
    
    private func sendPreflightResponse(connection: NWConnection) {
        let headers = [
            "HTTP/1.1 204 No Content",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type, Authorization",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        let payload = headers.data(using: .utf8) ?? Data()
        connection.send(content: payload, isComplete: true, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    private func sendTextResponse(body: String, contentType: String, connection: NWConnection) {
        let responseData = body.data(using: .utf8) ?? Data()
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: \(contentType); charset=utf-8",
            "Content-Length: \(responseData.count)",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, OPTIONS",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var payload = headers.data(using: .utf8) ?? Data()
        payload.append(responseData)
        connection.send(content: payload, isComplete: true, completion: .contentProcessed({ _ in
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                connection.cancel()
            }
        }))
    }
    
    // MARK: - Legacy JS helper
    
    private func buildOrivoJS() -> String {
        let (configPort, _) = MainActor.assumeIsolated {
            (ServiceManager.shared.resolvedConfigServerPort, ServiceManager.shared.resolvedTorrServerPort)
        }
        let torrserverURL = "http://127.0.0.1:\(configPort)/torrserver"
        
        return """
        (function () {
            function configure() {
                var keys = ['settings', 'lampa_settings'];
                for (var i = 0; i < keys.length; i++) {
                    var key = keys[i];
                    var data = {};
                    try { var raw = localStorage.getItem(key); if (raw) data = JSON.parse(raw); } catch(e) {}
                    data.torrserver_url = '\(torrserverURL)';
                    data.torrserver_use = true;
                    data.parser_use = true;
                    data.parser_jackett = true;
                    localStorage.setItem(key, JSON.stringify(data));
                }
            }
            configure();
            var attempts = 0;
            var interval = setInterval(function() {
                configure(); attempts++;
                if (attempts >= 8) clearInterval(interval);
            }, 500);
            console.log('[Orivo] Auto-configured local services.');
        })();
        """
    }
}
