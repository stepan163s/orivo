import SwiftUI
import WebKit

public enum KinoriumLoginResult: Sendable {
    case cookie(cookieString: String, cookies: [HTTPCookie])
    case deepLink(rawURL: String, parameters: [String: String])
}

public struct KinoriumLoginSheet: View {
    let url: URL
    let onComplete: (KinoriumLoginResult) -> Void
    let onCancel: () -> Void
    
    public init(url: URL, onComplete: @escaping (KinoriumLoginResult) -> Void, onCancel: @escaping () -> Void) {
        self.url = url
        self.onComplete = onComplete
        self.onCancel = onCancel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Авторизация через Кинориум")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button("Отмена") {
                    onCancel()
                }
                .buttonStyle(BorderedButtonStyle())
            }
            .padding(12)
            .background(Color.white.opacity(0.02))
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            KinoriumWebView(url: url, onComplete: onComplete)
        }
        .frame(width: 600, height: 750)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }
}

struct KinoriumWebView: NSViewRepresentable {
    let url: URL
    let onComplete: (KinoriumLoginResult) -> Void
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        
        // Inject JS bridge to capture console logs and window errors
        let source = """
        (function() {
            var originalLog = console.log;
            var originalError = console.error;
            var originalWarn = console.warn;
            
            console.log = function() {
                var msg = Array.prototype.slice.call(arguments).join(' ');
                window.webkit.messageHandlers.consoleLog.postMessage('[LOG] ' + msg);
                originalLog.apply(console, arguments);
            };
            console.error = function() {
                var msg = Array.prototype.slice.call(arguments).join(' ');
                window.webkit.messageHandlers.consoleLog.postMessage('[ERROR] ' + msg);
                originalError.apply(console, arguments);
            };
            console.warn = function() {
                var msg = Array.prototype.slice.call(arguments).join(' ');
                window.webkit.messageHandlers.consoleLog.postMessage('[WARN] ' + msg);
                originalWarn.apply(console, arguments);
            };
            window.onerror = function(message, source, lineno, colno, error) {
                var errorMsg = 'WINDOW ERROR: ' + message + ' at ' + source + ':' + lineno + ':' + colno;
                window.webkit.messageHandlers.consoleLog.postMessage(errorMsg);
                return false;
            };
        })();
        """
        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(script)
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        configuration.userContentController.add(context.coordinator, name: "consoleLog")
        
        // Set standard macOS Safari User Agent to prevent Google OAuth block
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: KinoriumWebView
        
        init(_ parent: KinoriumWebView) {
            self.parent = parent
        }
        
        // WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "consoleLog", let body = message.body as? String {
                LogManager.shared.log(serviceId: "system", text: "KinoriumWebView: JS: \(body)")
            }
        }
        
        // Handle target="_blank" and window.open by forcing the link to load in the current web view
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            LogManager.shared.log(serviceId: "system", text: "KinoriumWebView: Intercepted popup request to \(navigationAction.request.url?.absoluteString ?? "about:blank"). Creating background webview.")
            let dummyWebView = WKWebView(frame: .zero, configuration: configuration)
            return dummyWebView
        }
        
        private func checkForCookies(in webView: WKWebView) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                let cookieString = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                
                if cookies.contains(where: { 
                    let name = $0.name.lowercased()
                    return name.contains("session") || name.contains("token") || name.contains("user_id") || name == "auth"
                }) {
                    LogManager.shared.log(serviceId: "system", text: "KinoriumWebView: Login cookies intercepted successfully!")
                    DispatchQueue.main.async {
                        self.parent.onComplete(.cookie(cookieString: cookieString, cookies: cookies))
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                LogManager.shared.log(serviceId: "system", text: "KinoriumWebView: Navigating to \(url.absoluteString)")
                
                // Bypass Google's regional SetSID domain synchronization hangs on .ru domains
                if url.path.contains("/accounts/SetSID"),
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                   let continueItem = components.queryItems?.first(where: { $0.name == "continue" }),
                   let continueVal = continueItem.value,
                   let continueURL = URL(string: continueVal) {
                    
                    LogManager.shared.log(serviceId: "system", text: "KinoriumWebView: Bypassing regional SetSID redirect loop. Loading continue URL directly: \(continueURL.absoluteString)")
                    
                    DispatchQueue.main.async {
                        webView.load(URLRequest(url: continueURL))
                    }
                    decisionHandler(.cancel)
                    return
                }
                
                if url.scheme == "kinorium" {
                    LogManager.shared.log(serviceId: "system", text: "KinoriumWebView: Intercepted deep link URL: \(url.absoluteString)")
                    
                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                       let queryItems = components.queryItems {
                        let itemsMap = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
                        
                        DispatchQueue.main.async {
                            self.parent.onComplete(.deepLink(rawURL: url.absoluteString, parameters: itemsMap))
                        }
                    }
                    
                    decisionHandler(.cancel)
                    return
                }
            }
            checkForCookies(in: webView)
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            checkForCookies(in: webView)
        }
        
        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            checkForCookies(in: webView)
        }
        
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            checkForCookies(in: webView)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            LogManager.shared.log(serviceId: "system", text: "KinoriumWebView: Finished loading page: \(webView.url?.absoluteString ?? "none") | Title: \(webView.title ?? "none")")
            checkForCookies(in: webView)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            LogManager.shared.log(serviceId: "system", text: "KinoriumWebView: Navigation failed to page: \(webView.url?.absoluteString ?? "none") | Error: \(error.localizedDescription)", isError: true)
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            LogManager.shared.log(serviceId: "system", text: "KinoriumWebView: Provisional navigation failed to page: \(webView.url?.absoluteString ?? "none") | Error: \(error.localizedDescription)", isError: true)
        }
        
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            LogManager.shared.log(serviceId: "system", text: "KinoriumWebView: Web content process terminated (crashed)!", isError: true)
            webView.reload()
        }
    }
}
