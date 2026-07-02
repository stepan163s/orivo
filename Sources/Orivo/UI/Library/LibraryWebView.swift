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
        
        // 1b. Player interception and HTML5 mock bridge script
        let playerBridgeSource = """
        (function() {
            var activeVideoElement = null;
            var updatingFromNative = false;
            
            window.activeVideoElement = null;
            
            function mockVideoElement(video) {
                if (video._isMocked) return;
                video._isMocked = true;
                activeVideoElement = video;
                window.activeVideoElement = video;
                
                console.log('[Orivo Bridge] Mocking video element');
                
                // Force transparency on HTML5 video component
                video.style.opacity = '0';
                video.style.backgroundColor = 'transparent';
                
                var mockCurrentTime = 0;
                var mockDuration = 0;
                var mockPaused = true;
                var mockVolume = 1.0;
                var mockPlaybackRate = 1.0;
                
                video.play = function() {
                    console.log('[Orivo Bridge] play() called');
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerActionHandler) {
                        window.webkit.messageHandlers.playerActionHandler.postMessage({ action: 'play' });
                    }
                    mockPaused = false;
                    video.dispatchEvent(new Event('play'));
                    video.dispatchEvent(new Event('playing'));
                    return Promise.resolve();
                };
                
                video.pause = function() {
                    console.log('[Orivo Bridge] pause() called');
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerActionHandler) {
                        window.webkit.messageHandlers.playerActionHandler.postMessage({ action: 'pause' });
                    }
                    mockPaused = true;
                    video.dispatchEvent(new Event('pause'));
                };
                
                Object.defineProperty(video, 'currentTime', {
                    get: function() { return mockCurrentTime; },
                    set: function(val) {
                        mockCurrentTime = val;
                        if (!updatingFromNative) {
                            console.log('[Orivo Bridge] seek: ' + val);
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerActionHandler) {
                                window.webkit.messageHandlers.playerActionHandler.postMessage({ action: 'seek', value: val });
                            }
                            video.dispatchEvent(new Event('seeking'));
                            setTimeout(function() {
                                video.dispatchEvent(new Event('seeked'));
                            }, 50);
                        }
                    },
                    configurable: true
                });
                
                Object.defineProperty(video, 'duration', {
                    get: function() { return mockDuration; },
                    set: function(val) {
                        mockDuration = val;
                        video.dispatchEvent(new Event('durationchange'));
                    },
                    configurable: true
                });
                
                Object.defineProperty(video, 'paused', {
                    get: function() { return mockPaused; },
                    configurable: true
                });
                
                Object.defineProperty(video, 'volume', {
                    get: function() { return mockVolume; },
                    set: function(val) {
                        mockVolume = val;
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerActionHandler) {
                            window.webkit.messageHandlers.playerActionHandler.postMessage({ action: 'volume', value: val * 100 });
                        }
                    },
                    configurable: true
                });
                
                Object.defineProperty(video, 'playbackRate', {
                    get: function() { return mockPlaybackRate; },
                    set: function(val) {
                        mockPlaybackRate = val;
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerActionHandler) {
                            window.webkit.messageHandlers.playerActionHandler.postMessage({ action: 'speed', value: val });
                        }
                    },
                    configurable: true
                });
                
                Object.defineProperty(video, 'buffered', {
                    get: function() {
                        return {
                            length: 1,
                            start: function(index) { return 0; },
                            end: function(index) { return mockDuration; }
                        };
                    },
                    configurable: true
                });
                
                Object.defineProperty(video, 'readyState', {
                    get: function() { return 4; },
                    configurable: true
                });
                Object.defineProperty(video, 'networkState', {
                    get: function() { return 1; },
                    configurable: true
                });
                
                video.updateProgressFromNative = function(current, total) {
                    updatingFromNative = true;
                    mockCurrentTime = current;
                    mockDuration = total;
                    video.dispatchEvent(new Event('timeupdate'));
                    updatingFromNative = false;
                };
                
                video.updateStateFromNative = function(paused) {
                    mockPaused = paused;
                    if (paused) {
                        video.dispatchEvent(new Event('pause'));
                    } else {
                        video.dispatchEvent(new Event('play'));
                        video.dispatchEvent(new Event('playing'));
                    }
                };
            }
            
            function intercept(video, src) {
                if (!src) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerActionHandler) {
                        window.webkit.messageHandlers.playerActionHandler.postMessage({ action: 'close' });
                    }
                    return false;
                }
                if (src.indexOf(':8090/stream/') !== -1) {
                    console.log('[Orivo Bridge] Intercepted stream source: ' + src);
                    mockVideoElement(video);
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerActionHandler) {
                        window.webkit.messageHandlers.playerActionHandler.postMessage({ action: 'load', value: src });
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
                if (intercept(this, src)) {
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
                if (intercept(this, src)) {
                    return;
                }
                return originalLoad.apply(this, arguments);
            };
            
            var originalSrcDescriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
            if (originalSrcDescriptor && originalSrcDescriptor.set) {
                var originalSet = originalSrcDescriptor.set;
                originalSrcDescriptor.set = function(val) {
                    if (intercept(this, val)) {
                        return;
                    }
                    originalSet.call(this, val);
                };
                Object.defineProperty(HTMLMediaElement.prototype, 'src', originalSrcDescriptor);
            }
            
            // Periodically check for video elements added by other means
            setInterval(function() {
                var videos = document.querySelectorAll('video');
                videos.forEach(mockVideoElement);
            }, 500);
            
            // Inject styles to hide raw video and force transparency on player overlay containers
            document.addEventListener('DOMContentLoaded', function() {
                var style = document.createElement('style');
                style.innerHTML = 'video { opacity: 0 !important; background: transparent !important; } .player, .player-video, .player-video video, .video-player { background: transparent !important; background-color: transparent !important; }';
                document.head.appendChild(style);
            });
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
        })();
        """
        let configScript = WKUserScript(source: configSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(configScript)
        
        // Register message handlers
        configuration.userContentController.add(context.coordinator, name: "logHandler")
        configuration.userContentController.add(context.coordinator, name: "playerActionHandler")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.underlyingNSView.setValue(false, forKey: "drawsBackground") // Enable transparent background
        
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
        weak var webView: WKWebView?
        
        public override init() {
            super.init()
            
            AppStateManager.shared.onPlayerProgress = { [weak self] current, total in
                guard let self = self, let webView = self.webView else { return }
                DispatchQueue.main.async {
                    let js = "if (window.activeVideoElement) { window.activeVideoElement.updateProgressFromNative(\(current), \(total)); }"
                    webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }
            
            AppStateManager.shared.onPlayerStateChanged = { [weak self] playing in
                guard let self = self, let webView = self.webView else { return }
                DispatchQueue.main.async {
                    let paused = !playing
                    let js = "if (window.activeVideoElement) { window.activeVideoElement.updateStateFromNative(\(paused)); }"
                    webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }
        
        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "logHandler", let log = message.body as? String {
                LogManager.shared.log(serviceId: "system", text: "[WebView] \(log)")
            } else if message.name == "playerActionHandler", let dict = message.body as? [String: Any], let action = dict["action"] as? String {
                LogManager.shared.log(serviceId: "system", text: "LibraryWebView playerActionHandler received action: \(action)")
                
                switch action {
                case "load":
                    if let url = dict["value"] as? String {
                        var title = "Orivo Media Player"
                        if let urlObj = URL(string: url) {
                            let filename = urlObj.lastPathComponent.removingPercentEncoding ?? urlObj.lastPathComponent
                            if !filename.isEmpty && filename != "play" && filename != "stream" {
                                title = filename
                            }
                        }
                        DispatchQueue.main.async {
                            AppStateManager.shared.play(url: url, title: title)
                        }
                    }
                case "play":
                    DispatchQueue.main.async {
                        AppStateManager.shared.activePlayer?.play()
                    }
                case "pause":
                    DispatchQueue.main.async {
                        AppStateManager.shared.activePlayer?.pause()
                    }
                case "seek":
                    if let val = dict["value"] as? Double {
                        DispatchQueue.main.async {
                            AppStateManager.shared.activePlayer?.seek(to: val)
                        }
                    }
                case "volume":
                    if let val = dict["value"] as? Double {
                        DispatchQueue.main.async {
                            AppStateManager.shared.activePlayer?.setVolume(Int(val))
                        }
                    }
                case "speed":
                    if let val = dict["value"] as? Double {
                        DispatchQueue.main.async {
                            AppStateManager.shared.activePlayer?.setSpeed(val)
                        }
                    }
                case "close":
                    DispatchQueue.main.async {
                        AppStateManager.shared.closePlayer()
                    }
                default:
                    break
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

extension WKWebView {
    var underlyingNSView: NSView {
        return self as NSView
    }
}
