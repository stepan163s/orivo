import SwiftUI
import WebKit
import AppKit

public struct LibraryWebView: NSViewRepresentable {
    public init() {}
    
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
        
        // 1b. Player interception bridge script with active check for bidirectional close
        let playerBridgeSource = """
        (function() {
            function intercept(src) {
                if (!src) return false;
                if (src.indexOf(':8090/stream/') !== -1) {
                    console.log('[Orivo Bridge] Intercepted stream URL: ' + src);
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerHandler) {
                        window.webkit.messageHandlers.playerHandler.postMessage(src);
                    }
                    return true;
                }
                return false;
            }

            var originalPlay = HTMLMediaElement.prototype.play;
            HTMLMediaElement.prototype.play = function() {
                var src = this.src || '';
                if (!src) {
                    var source = this.querySelector('source');
                    if (source) src = source.src || '';
                }
                if (intercept(src)) {
                    this.pause();
                    return Promise.resolve();
                }
                return originalPlay.apply(this, arguments);
            };

            var originalLoad = HTMLMediaElement.prototype.load;
            HTMLMediaElement.prototype.load = function() {
                var src = this.src || '';
                if (!src) {
                    var source = this.querySelector('source');
                    if (source) src = source.src || '';
                }
                if (intercept(src)) {
                    this.pause();
                    return;
                }
                return originalLoad.apply(this, arguments);
            };

            var originalSrcDescriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
            if (originalSrcDescriptor && originalSrcDescriptor.set) {
                var originalSet = originalSrcDescriptor.set;
                originalSrcDescriptor.set = function(val) {
                    if (intercept(val)) {
                        return;
                    }
                    originalSet.call(this, val);
                };
                Object.defineProperty(HTMLMediaElement.prototype, 'src', originalSrcDescriptor);
            }

            var activeVideoDetected = false;
            setInterval(function() {
                var videos = document.querySelectorAll('video');
                if (videos.length === 0 && activeVideoDetected) {
                    console.log('[Orivo Bridge] Video element removed from DOM, closing player');
                    activeVideoDetected = false;
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerHandler) {
                        window.webkit.messageHandlers.playerHandler.postMessage('close');
                    }
                } else if (videos.length > 0 && !activeVideoDetected) {
                    var src = videos[0].src || '';
                    if (src.indexOf(':8090/stream/') !== -1) {
                        activeVideoDetected = true;
                    }
                }
            }, 500);
        })();
        """
        let playerBridgeScript = WKUserScript(source: playerBridgeSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(playerBridgeScript)
        
        // 2. Safe and defensive Lampa localStorage configuration script
        let configSource = """
        (function () {
            function configure() {
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
        })();
        """
        let configScript = WKUserScript(source: configSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(configScript)
        
        // Register console bridge listener
        configuration.userContentController.add(context.coordinator, name: "logHandler")
        configuration.userContentController.add(context.coordinator, name: "playerHandler")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        AppStateManager.shared.onClosePlayerRequested = { [weak webView] in
            webView?.evaluateJavaScript("if (typeof Lampa !== 'undefined' && Lampa.Player) { Lampa.Player.close(); } else if (typeof Player !== 'undefined' && Player.close) { Player.close(); }", completionHandler: nil)
        }
        
        if let localHTML = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Lampa") {
            webView.loadFileURL(localHTML, allowingReadAccessTo: localHTML.deletingLastPathComponent())
        } else {
            LogManager.shared.log(serviceId: "system", text: "LibraryWebView error: Failed to find local Lampa index.html in resources bundle", isError: true)
        }
        
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
            } else if message.name == "playerHandler", let urlString = message.body as? String {
                if urlString == "close" {
                    LogManager.shared.log(serviceId: "system", text: "LibraryWebView playerHandler received close command from Lampa")
                    DispatchQueue.main.async {
                        AppStateManager.shared.closePlayer()
                    }
                    return
                }
                
                LogManager.shared.log(serviceId: "system", text: "LibraryWebView playerHandler received stream URL: \(urlString)")
                
                var title = "Orivo Media Player"
                if let url = URL(string: urlString) {
                    let filename = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                    if !filename.isEmpty && filename != "play" && filename != "stream" {
                        title = filename
                    }
                }
                
                DispatchQueue.main.async {
                    AppStateManager.shared.play(url: urlString, title: title)
                }
            }
        }
        
        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let scheme = url.scheme?.lowercased() ?? ""
                if scheme != "http" && scheme != "https" && scheme != "file" && scheme != "about" {
                    LogManager.shared.log(serviceId: "system", text: "LibraryWebView opening external player URL: \(url.absoluteString)")
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
        
        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            LogManager.shared.log(serviceId: "system", text: "LibraryWebView provisional navigation failed: \(error.localizedDescription)", isError: true)
        }
        
        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            LogManager.shared.log(serviceId: "system", text: "LibraryWebView navigation failed: \(error.localizedDescription)", isError: true)
        }
    }
}
