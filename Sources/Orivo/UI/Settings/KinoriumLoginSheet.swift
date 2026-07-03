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
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        // Clean session cookies to guarantee a fresh login prompt
        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records, completionHandler: {})
        }
        
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: KinoriumWebView
        
        init(_ parent: KinoriumWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, url.scheme == "kinorium" {
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
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
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
    }
}
