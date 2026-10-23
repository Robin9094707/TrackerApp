//
//  GoogleLogin.swift
//  Spot
//
//  Created by Leon Böttger on 10.12.24.
//

import LUI
import SwiftUI
import WebKit

struct GoogleLoginWebView: UIViewRepresentable {
    class Coordinator: NSObject {
        var parent: GoogleLoginWebView
        var timer: Timer?

        init(parent: GoogleLoginWebView) {
            self.parent = parent
        }

        func startCookieCheck(webView: WKWebView) {
            // Set up a periodic timer to check cookies
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                let cookieStore = WKWebsiteDataStore.default().httpCookieStore
                cookieStore.getAllCookies { cookies in
                    if let oauthTokenCookie = cookies.first(where: { $0.name == "oauth_token" && ($0.domain == "accounts.google.com" || $0.domain == ".google.com" || $0.domain == "google.com") }) {
                        // Stop the timer and notify the parent
                        self.timer?.invalidate()
                        self.timer = nil

                        let parentReference = self.parent

                        Task {
                            do {
                                try await generateAasToken(oauthToken: oauthTokenCookie.value)
                                await MainActor.run { parentReference.shouldClose = true }
                            } catch {
                                showAlert(title: "Google-Anmeldung", message: error.localizedDescription)
                                // Remove the one-time cookie so a retry uses a fresh login token.
                                WKWebsiteDataStore.default().httpCookieStore.delete(oauthTokenCookie)
                                await MainActor.run { self.startCookieCheck(webView: webView) }
                            }
                        }
                    }
                }
            }
        }

        func stopCookieCheck() {
            timer?.invalidate()
            timer = nil
        }
    }

    let url: URL
    @Binding var shouldClose: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        context.coordinator.startCookieCheck(webView: webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_: WKWebView, context _: Context) {}

    static func dismantleUIView(_: WKWebView, coordinator: Coordinator) {
        // Clean up resources and stop the timer
        coordinator.stopCookieCheck()
    }
}

struct GoogleLoginView: View {
    @State private var shouldCloseWebView = false
    @State private var finished = false

    var body: some View {
        NavigationSubView(header: "", supportsScrolling: false, backgroundShown: false) {
            ZStack {
                GoogleLoginWebView(url: URL(string: "https://accounts.google.com/EmbeddedSetup")!,
                                   shouldClose: $shouldCloseWebView)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .modifier(LinkTo(content: { IntroductionDoneView() }, isActive: $shouldCloseWebView))
    }
}

@MainActor
func generateAasToken(oauthToken: String) async throws {
    guard let androidId = PushReceiver.sharedInstance.getAndroidId() else {
        throw NSError(domain: "SpotGoogle", code: 3, userInfo: [NSLocalizedDescriptionKey: "Google-Registrierung fehlt. Bitte die Einrichtung erneut starten."])
    }
    let response: [String: String] = try await withCheckedThrowingContinuation { continuation in
        PlayServicesOAuth.requestAASToken(email: TokenManager.sharedInstance.username ?? "", oauthToken: oauthToken, androidID: String(androidId)) {
            continuation.resume(with: $0)
        }
    }
    guard let token = response["Token"], !token.isEmpty, let email = response["Email"], !email.isEmpty else {
        throw NSError(domain: "SpotGoogle", code: 4, userInfo: [NSLocalizedDescriptionKey: "Google hat die Anmeldung nicht bestätigt. Bitte erneut anmelden."])
    }
    // Verify secure persistence before marking onboarding complete.
    try KeychainStore.shared.save(token, for: .aasToken)
    TokenManager.sharedInstance.username = email
    TokenManager.sharedInstance.aasToken = token
}
