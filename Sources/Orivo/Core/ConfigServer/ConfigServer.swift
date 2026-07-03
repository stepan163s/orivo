import Foundation
import Network

public final class ConfigServer: @unchecked Sendable {
    public static let shared = ConfigServer()
    
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.orivo.configserver", qos: .background)
    
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
        LogManager.shared.log(serviceId: "system", text: "Auto-config server stopped.")
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        // Larger buffer for proxied Jackett responses
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }
            Task {
                await self?.processRequest(data, connection: connection)
            }
        }
    }
    
    private func processRequest(_ data: Data, connection: NWConnection) async {
        let request = String(data: data, encoding: .utf8) ?? ""
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { connection.cancel(); return }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { connection.cancel(); return }
        
        let method = parts[0]
        let path = parts[1]
        
        LogManager.shared.log(serviceId: "system", text: "ConfigServer: Received \(method) request for \(path)")
        
        // Handle CORS preflight so WebKit doesn't block the request
        if method == "OPTIONS" {
            sendPreflightResponse(connection: connection)
            return
        }
        
        let (settings, torrPort, jackettPort) = await MainActor.run {
            (SettingsManager.shared.settings, ServiceManager.shared.resolvedTorrServerPort, ServiceManager.shared.resolvedJackettPort)
        }
        
        // CORS proxy: forward /jackett/* → http://127.0.0.1:resolvedJackettPort/* (or external host)
        if path.hasPrefix("/jackett") {
            let jackettPath = String(path.dropFirst("/jackett".count))
            let upstreamBase = (settings.useExternalServers && !settings.externalJackettHost.isEmpty)
                ? settings.externalJackettHost
                : "http://127.0.0.1:\(jackettPort)"
            let jackettURL = upstreamBase + (jackettPath.isEmpty ? "/" : jackettPath)
            proxyToJackett(urlString: jackettURL, connection: connection)
            return
        }
        
        // CORS proxy: forward /torrserver/* → http://127.0.0.1:resolvedTorrServerPort/* (or external host)
        if path.hasPrefix("/torrserver") {
            let torrPath = String(path.dropFirst("/torrserver".count))
            let upstreamBase = (settings.useExternalServers && !settings.externalTorrServerHost.isEmpty)
                ? settings.externalTorrServerHost
                : "http://127.0.0.1:\(torrPort)"
            let torrURL = upstreamBase + (torrPath.isEmpty ? "/" : torrPath)
            proxyRequest(urlString: torrURL, connection: connection)
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
    
    // MARK: - CORS proxy for Jackett
    
    private func proxyToJackett(urlString: String, connection: NWConnection) {
        proxyRequest(urlString: urlString, connection: connection)
    }
    private func proxyRequest(urlString: String, connection: NWConnection) {
        // Pre-encode raw square brackets to prevent Swift's URL(string:) from triggering double-encoding
        let cleanURLString = urlString
            .replacingOccurrences(of: "[", with: "%5B")
            .replacingOccurrences(of: "]", with: "%5D")
            
        guard let url = URL(string: cleanURLString) else {
            sendTextResponse(body: "{\"error\": \"Invalid proxy URL\"}", contentType: "application/json", connection: connection)
            return
        }
        
        LogManager.shared.log(serviceId: "system", text: "ConfigServer: Proxying to upstream URL: \(urlString)")
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                LogManager.shared.log(serviceId: "system", text: "ConfigServer: Proxy error: \(error.localizedDescription) for \(urlString)", isError: true)
                let body = "{\"error\": \"\(error.localizedDescription)\"}"
                self.sendTextResponse(body: body, contentType: "application/json", connection: connection)
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
        return """
        (function () {
            function configure() {
                var keys = ['settings', 'lampa_settings'];
                for (var i = 0; i < keys.length; i++) {
                    var key = keys[i];
                    var data = {};
                    try { var raw = localStorage.getItem(key); if (raw) data = JSON.parse(raw); } catch(e) {}
                    data.torrserver_url = 'http://127.0.0.1:8090';
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
