import SwiftUI
import WebKit

public struct LibraryWebView: NSViewRepresentable {
    let url: URL
    
    public init(url: URL) {
        self.url = url
    }
    
    private func getJackettAPIKey() -> String {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        
        let paths = [
            home.appendingPathComponent(".config/Jackett/ServerConfig.json"),
            home.appendingPathComponent("Library/Application Support/Jackett/ServerConfig.json"),
            home.appendingPathComponent("Library/Application Support/Orivo/services/jackett/ServerConfig.json")
        ]
        
        for path in paths {
            if fileManager.fileExists(atPath: path.path) {
                if let data = try? Data(contentsOf: path),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let apiKey = json["APIKey"] as? String {
                    return apiKey
                }
            }
        }
        return ""
    }
    
    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let jackettAPIKey = getJackettAPIKey()
        
        // 1. Console Log redirection bridge script
        let logBridgeSource = """
        (function() {
            var oldLog = console.log;
            console.log = function() {
                var msg = Array.prototype.slice.call(arguments).join(' ');
                oldLog.apply(console, arguments);
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.logHandler) {
                    window.webkit.messageHandlers.logHandler.postMessage('[Console] ' + msg);
                }
            };
            var oldErr = console.error;
            console.error = function() {
                var msg = Array.prototype.slice.call(arguments).join(' ');
                oldErr.apply(console, arguments);
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.logHandler) {
                    window.webkit.messageHandlers.logHandler.postMessage('[Console Error] ' + msg);
                }
            };
        })();
        """
        let logBridgeScript = WKUserScript(source: logBridgeSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(logBridgeScript)
        
        // 2. Safe and defensive Lampa localStorage configuration script
        let configSource = """
        (function () {
            function configure() {
                if (!window.location || !window.location.hostname || window.location.hostname.indexOf('lampa') === -1) {
                    return;
                }
                
                try {
                    var keys = ['settings', 'lampa_settings'];
                    for (var i = 0; i < keys.length; i++) {
                        var key = keys[i];
                        var data = {};
                        
                        var raw = localStorage.getItem(key);
                        if (raw) {
                            try {
                                data = JSON.parse(raw);
                            } catch(e) {}
                        }
                        
                        var jackettKey = '\(jackettAPIKey)';
                        // Route through our CORS proxy (port 8098) so WebKit allows the cross-origin requests
                        var jackettProxyBase = 'http://127.0.0.1:8098/jackett';
                        var parserUrl = jackettProxyBase + '/api/v2.0/indexers/all/results/torznab/api?apikey=' + jackettKey + '&';
                        
                        data.torrserver_url = 'http://127.0.0.1:8090';
                        data.torrserver_use = true;
                        data.parser_use = true;
                        data.parser_url = parserUrl;
                        data.parser_jackett = true;
                        data.parser_torrent_type = 'jackett';
                        data.jackett_url = jackettProxyBase;
                        data.jackett_key = jackettKey;
                        
                        localStorage.setItem(key, JSON.stringify(data));
                    }
                    
                    // Backup flat values
                    var jackettKey = '\(jackettAPIKey)';
                    var jackettProxyBase = 'http://127.0.0.1:8098/jackett';
                    var parserUrl = jackettProxyBase + '/api/v2.0/indexers/all/results/torznab/api?apikey=' + jackettKey + '&';
                    localStorage.setItem('torrserver_url', 'http://127.0.0.1:8090');
                    localStorage.setItem('torrserver_use', 'true');
                    localStorage.setItem('parser_use', 'true');
                    localStorage.setItem('parser_url', parserUrl);
                    localStorage.setItem('parser_jackett', 'true');
                    localStorage.setItem('parser_torrent_type', 'jackett');
                    localStorage.setItem('jackett_url', jackettProxyBase);
                    localStorage.setItem('jackett_key', jackettKey);
                } catch (e) {
                    console.error('[Orivo] LocalStorage config failed: ' + e.message);
                }
            }
            
            configure();
            
            var attempts = 0;
            var interval = setInterval(function() {
                configure();
                attempts++;
                if (attempts >= 15) clearInterval(interval);
            }, 300);
        })();
        """
        let configScript = WKUserScript(source: configSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(configScript)
        
        // Register console bridge listener
        configuration.userContentController.add(context.coordinator, name: "logHandler")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underlyingNSView.setValue(false, forKey: "drawsBackground") // Enable transparent background
        webView.load(URLRequest(url: url))
        return webView
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "logHandler", let log = message.body as? String {
                LogManager.shared.log(serviceId: "system", text: "[WebView] \(log)")
            }
        }
        
        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            LogManager.shared.log(serviceId: "system", text: "LibraryWebView provisional navigation failed: \(error.localizedDescription)", isError: true)
        }
        
        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            LogManager.shared.log(serviceId: "system", text: "LibraryWebView navigation failed: \(error.localizedDescription)", isError: true)
        }
    }
}

extension WKWebView {
    var underlyingNSView: NSView {
        return self as NSView
    }
}
