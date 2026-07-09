import SwiftUI
import WebKit
import AppKit

public struct LibraryWebView: NSViewRepresentable {
    public init() {}
    
    private func getLocalJackettAPIKey() -> String {
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
        let settings = SettingsManager.shared.settings
        
        let configPort = ServiceManager.shared.resolvedConfigServerPort
        let torrPort = ServiceManager.shared.resolvedTorrServerPort
        
        let rawKey = settings.useExternalServers ? settings.externalJackettApiKey : getLocalJackettAPIKey()
        let isExternalLampa = settings.useExternalServers && !settings.externalLampaURL.isEmpty
        
        let jackettProxyBase = isExternalLampa 
            ? (settings.externalJackettHost.isEmpty ? "http://127.0.0.1:\(configPort)/jackett" : settings.externalJackettHost) 
            : "http://127.0.0.1:\(configPort)/jackett"
            
        let isProxied = jackettProxyBase.contains("127.0.0.1") || jackettProxyBase.contains("localhost")
        let jackettKey = isProxied ? "orivo_secured_key" : rawKey
            
        let torrserverURL = isExternalLampa 
            ? (settings.externalTorrServerHost.isEmpty ? "http://127.0.0.1:\(torrPort)" : settings.externalTorrServerHost) 
            : "http://127.0.0.1:\(configPort)/torrserver"
        
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
                var baseHost = '\(torrserverURL)';
                if (src.indexOf(baseHost + '/stream/') !== -1 || src.indexOf(':8090/stream/') !== -1 || src.indexOf('/stream/') !== -1) {
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
                    if (src.indexOf(':8090/stream/') !== -1 || src.indexOf('/stream/') !== -1) {
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
                        
                        var jackettKey = '\(jackettKey)';
                        var jackettProxyBase = '\(jackettProxyBase)';
                        var parserUrl = jackettProxyBase + '/api/v2.0/indexers/all/results/torznab/api?apikey=' + jackettKey + '&';
                        
                        data.torrserver_url = '\(torrserverURL)';
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
                    var jackettKey = '\(jackettKey)';
                    var jackettProxyBase = '\(jackettProxyBase)';
                    var parserUrl = jackettProxyBase + '/api/v2.0/indexers/all/results/torznab/api?apikey=' + jackettKey + '&';
                    localStorage.setItem('torrserver_url', '\(torrserverURL)');
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
        
        // Register console bridge listener with weak wrappers to prevent memory leaks
        configuration.userContentController.add(WeakScriptMessageHandler(delegate: context.coordinator), name: "logHandler")
        configuration.userContentController.add(WeakScriptMessageHandler(delegate: context.coordinator), name: "playerHandler")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        AppStateManager.shared.onClosePlayerRequested = { [weak webView] in
            webView?.evaluateJavaScript("if (typeof Lampa !== 'undefined' && Lampa.Player) { Lampa.Player.close(); } else if (typeof Player !== 'undefined' && Player.close) { Player.close(); }", completionHandler: nil)
        }
        
        // Load local bundle Lampa or external URL
        if settings.useExternalServers, !settings.externalLampaURL.isEmpty, let extURL = URL(string: settings.externalLampaURL) {
            LogManager.shared.log(serviceId: "system", text: "LibraryWebView: Loading external Lampa URL: \(extURL)")
            webView.load(URLRequest(url: extURL))
        } else {
            if let localHTML = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Lampa") {
                webView.loadFileURL(localHTML, allowingReadAccessTo: localHTML.deletingLastPathComponent())
            } else {
                LogManager.shared.log(serviceId: "system", text: "LibraryWebView error: Failed to find local Lampa index.html in resources bundle", isError: true)
            }
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
                
                let settings = SettingsManager.shared.settings
                var finalUrlString = urlString
                
                let configPort = ServiceManager.shared.resolvedConfigServerPort
                let torrPort = ServiceManager.shared.resolvedTorrServerPort
                
                // Rewrite proxied or local TorrServer URLs to point directly to the configured TorrServer host
                let directTorrHost = (settings.useExternalServers && !settings.externalTorrServerHost.isEmpty)
                    ? settings.externalTorrServerHost
                    : "http://127.0.0.1:\(torrPort)"
                
                if finalUrlString.contains("/torrserver/stream/") {
                    finalUrlString = finalUrlString.replacingOccurrences(of: "http://127.0.0.1:\(configPort)/torrserver", with: directTorrHost)
                } else if finalUrlString.contains("127.0.0.1:\(torrPort)/stream/") || finalUrlString.contains("localhost:\(torrPort)/stream/") {
                    finalUrlString = finalUrlString.replacingOccurrences(of: "http://127.0.0.1:\(torrPort)", with: directTorrHost)
                    finalUrlString = finalUrlString.replacingOccurrences(of: "http://localhost:\(torrPort)", with: directTorrHost)
                } else if finalUrlString.contains("127.0.0.1:8090/stream/") || finalUrlString.contains("localhost:8090/stream/") {
                    finalUrlString = finalUrlString.replacingOccurrences(of: "http://127.0.0.1:8090", with: directTorrHost)
                    finalUrlString = finalUrlString.replacingOccurrences(of: "http://localhost:8090", with: directTorrHost)
                }
                
                LogManager.shared.log(serviceId: "system", text: "LibraryWebView playerHandler playing direct stream URL: \(finalUrlString)")
                
                var title = "Orivo Media Player"
                if let url = URL(string: finalUrlString) {
                    let filename = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                    if !filename.isEmpty && filename != "play" && filename != "stream" {
                        title = filename
                    }
                }
                
                DispatchQueue.main.async {
                    AppStateManager.shared.play(url: finalUrlString, title: title)
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

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?
    
    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
