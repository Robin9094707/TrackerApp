import SwiftUI
import WebKit

struct WebStudioView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let url = APIClient.shared.baseURL {
                WebStudioWebView(url: url)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView(
                    "Kein Server gekoppelt",
                    systemImage: "network.slash",
                    description: Text("Verbinde die App zuerst mit deinem Universal Tag Studio Server.")
                )
            }
        }
        .navigationTitle("Web Studio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let url = APIClient.shared.baseURL {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
    }
}

private struct WebStudioWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "RJTracker-iOS-WebStudio/1.0"
        context.coordinator.webView = webView
        synchronizeSessionAndLoad(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        synchronizeSessionAndLoad(in: webView)
    }

    private func synchronizeSessionAndLoad(in webView: WKWebView) {
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        guard !cookies.isEmpty else {
            webView.load(URLRequest(url: url))
            return
        }
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            cookieStore.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var loadedURL: URL?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loadedURL = webView.url
            DebugLogger.shared.log("Web Studio loaded: \(webView.url?.absoluteString ?? "unknown")")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DebugLogger.shared.log("Web Studio navigation failed: \(error.localizedDescription)")
        }
    }
}
