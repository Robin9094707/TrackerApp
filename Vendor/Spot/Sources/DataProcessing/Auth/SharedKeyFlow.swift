//
//  SharedKeyFlow.swift
//  Spot
//
//  Created by Leon Böttger on 10.12.24.
//

import LUI
import SwiftUI
@preconcurrency import WebKit

struct KeyRecoverySheetModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.luiFullScreenCover(isPresented: $isPresented) {
            SharedKeyFlowView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    LUIButton(action: {
                        isPresented = false
                    }, label: {
                        LUIText("Cancel")
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                            .background(
                                ZStack {
                                    Color.sheetBackgroundColor
                                    Color.gray.opacity(0.12)
                                }
                                .cornerRadius(30)
                            )
                            .padding()
                            .padding(.bottom, 9)
                    })
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                )
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .onAppear {
                    showAlert(title: "Lock Screen Patterns", message: "Lock screen pattern unlock is currently not supported. If your Android device is secured with a pattern, please temporarily change it to a PIN or a password first.")
                }
        }
    }
}

struct WebView: UIViewRepresentable {
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebView
        var observedRedirectUrl: String

        init(parent: WebView, observedRedirectUrl: String) {
            self.parent = parent
            self.observedRedirectUrl = observedRedirectUrl
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            withAnimation {
                parent.showLoadingIndicator = false
            }
        }

        /// Detect page navigation and check for the redirect
        func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, url.scheme == "https", url.host == observedRedirectUrl {
                // Load the new URL
                if let newUrl = SecurityDomainUrlGenerator.getUrl() {
                    DispatchQueue.main.async {
                        self.parent.currentUrl = newUrl
                    }
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// Handle JavaScript messages
        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            let origin = message.frameInfo.securityOrigin
            guard message.frameInfo.isMainFrame, origin.protocol == "https", origin.host == "accounts.google.com" else { return }
            if message.name == "getKeyHandler", let body = message.body as? [String: Any] {
                if let vaultKeys = body["vaultKeys"] as? String {
                    do {
                        let sharedKey = try getFmdnSharedKey(vaultKeys: vaultKeys)
                        let sharedKeyHex = sharedKey.hex

                        Task {
                            do {
                                let info = try await EidInfoProvider.get()

                                let ownerKeyData = try AESGCM.decrypt(key: sharedKey, encryptedDataAndIV: info.encryptedOwnerKeyAndMetadata.encryptedOwnerKey)

                                if let devicesList = Settings.sharedInstance.devicesList {
                                    for device in devicesList {
                                        do {
                                            if let encryptedKeys = device.encryptedKeys {
                                                let eik = try EIKDecryptor.decrypt(ownerKey: ownerKeyData, encryptedEIK: encryptedKeys.encryptedIdentityKey, isObfuscated: device.isCustomTracker)
                                                device.eik = eik

                                                if !encryptedKeys.encryptedAccountKey.isEmpty, !device.isCustomTracker {
                                                    let accountKey = try AccountKeyDecryptor.decrypt(ownerKey: ownerKeyData, encryptedAccountKey: encryptedKeys.encryptedAccountKey)
                                                    device.accountKey = accountKey
                                                }
                                            }
                                        } catch {}
                                    }
                                }

                                TokenManager.sharedInstance.sharedKey = sharedKeyHex

                                let ownerKeyHex = ownerKeyData.hex
                                TokenManager.sharedInstance.ownerKey = ownerKeyHex
                                TokenManager.sharedInstance.ownerKeyVersion = Int(info.encryptedOwnerKeyAndMetadata.ownerKeyVersion)

                                Settings.sharedInstance.showKeyRecoverySheet = false
                            } catch {
                                showAlert(title: "An Error Occured", message: "Your data could not be decrypted. Please try again later.")
                            }
                        }
                    } catch {
                        showAlert(title: "An Error Occured", message: "Your data could not be decrypted. Please try again later.")
                    }
                }
            }
        }

        private func getFmdnSharedKey(vaultKeys: String) throws -> Data {
            guard let data = vaultKeys.data(using: .utf8),
                  let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            else {
                throw NSError(domain: "Invalid JSON", code: 1, userInfo: nil)
            }

            for (key, value) in jsonObject {
                if key == "finder_hw", let jsonArray = value as? [[String: Any]] {
                    for item in jsonArray {
                        if let epoch = item["epoch"] as? Int,
                           let keyData = item["key"] as? [String: Any]
                        {
                            let processedKey = transformToByteArray(jsonObject: keyData)

                            return Data(processedKey)
                        }
                    }
                }
            }

            throw NSError(domain: "No suitable key found in the vault keys.", code: 2, userInfo: nil)
        }

        private func transformToByteArray(jsonObject: [String: Any]) -> [UInt8] {
            var byteArray = [UInt8]()
            for i in 0 ..< jsonObject.count {
                if let value = jsonObject[String(i)] as? UInt8 {
                    byteArray.append(value)
                }
            }
            return byteArray
        }
    }

    @Binding var currentUrl: URL
    @Binding var showLoadingIndicator: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, observedRedirectUrl: "myaccount.google.com")
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "getKeyHandler")

        // Inject JavaScript interface
        let script = """
        window.mm = {
            setVaultSharedKeys: function(str, vaultKeys) {
                window.webkit.messageHandlers.getKeyHandler.postMessage({str: str, vaultKeys: vaultKeys});
            }
        };
        """
        let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(userScript)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: currentUrl))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context _: Context) {
        if uiView.url != currentUrl {
            let request = URLRequest(url: currentUrl)
            uiView.load(request)
        }
    }
}

struct SharedKeyFlowView: View {
    @State private var currentUrl = URL(string: "https://accounts.google.com/")!
    @State private var cookies = [WebloginAuthResponse.WebloginCookies.Cookie]()
    @State private var showWebView = false
    @State private var showLoadingIndicator = true

    var body: some View {
        ZStack {
            if showWebView {
                WebView(currentUrl: $currentUrl, showLoadingIndicator: $showLoadingIndicator)
            }

            if showLoadingIndicator {
                LoadingIndicator()
                    .frame(width: 23)
                    .onAppear {
                        retrieveCookies()
                    }
            }
        }
        .animation(.easeInOut, value: showWebView)
        .animation(.easeInOut, value: showLoadingIndicator)
    }

    func retrieveCookies() {
        runAfter(seconds: 0.5) {
            Task {
                do {
                    // retrieve login cookies
                    try await cookies = TokenManager.sharedInstance.getLoginCookies()

                    // get unlock challenge page url
                    guard let url = SecurityDomainUrlGenerator.getUrl() else {
                        throw NSError(domain: "Invalid URL", code: 0, userInfo: nil)
                    }

                    // Set the current URL
                    currentUrl = url

                    // clean all old cookies first, and set the new ones
                    CookieCache.clearWKWebViewCacheAndCookies {
                        // Add retrieved cookies and show the WebView
                        CookieCache.addCookies(cookies: cookies) {
                            showWebView = true
                        }
                    }
                } catch {
                    // fallback to login view to set cookies manually
                    showWebView = true
                }
            }
        }
    }
}
