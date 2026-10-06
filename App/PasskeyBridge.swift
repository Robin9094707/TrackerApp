import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

@MainActor
final class PasskeyBridge: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PasskeyBridge()
    private var authenticating = false
    private var browserSession: ASWebAuthenticationSession?
    func authenticate(enrollment: Bool = false) async throws {
        guard let base = APIClient.shared.baseURL, base.scheme == "https" else { throw APIError.message("Passkeys benötigen eine HTTPS-Serveradresse.") }
        guard !authenticating else { throw APIError.message("Eine Passkey-Anmeldung läuft bereits.") }
        authenticating = true
        defer { authenticating = false }
        let verifier = UUID().uuidString + UUID().uuidString + UUID().uuidString
        let state = UUID().uuidString
        let challenge = SHA256.hash(data: Data(verifier.utf8)).map { String(format: "%02x", $0) }.joined()
        var query = [URLQueryItem(name: "state", value: state), URLQueryItem(name: "challenge", value: challenge)]
        if enrollment {
            let start = try await APIClient.shared.requestJSON(path: "/api/v3/auth/browser/start", method: "POST", json: [:])
            guard let ticket = start["ticket"].stringValue else { throw APIError.message("Passkey-Einrichtung konnte nicht gestartet werden.") }
            query += [.init(name: "mode", value: "register"), .init(name: "ticket", value: ticket)]
        }
        var components = URLComponents(url: base.appendingPathComponent("auth/passkey"), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        guard let url = components.url else { throw APIError.message("Ungültige Anmeldeadresse.") }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "rjtracker") { url, error in
                Task { @MainActor in
                    self.browserSession = nil
                    if let url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: error ?? APIError.message("Passkey-Anmeldung abgebrochen.")) }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.browserSession = session
            if !session.start() { self.browserSession = nil; continuation.resume(throwing: APIError.message("Sicherheitsdialog konnte nicht geöffnet werden.")) }
        }
        let params = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard callback.scheme == "rjtracker", callback.host == "auth", params.first(where: { $0.name == "state" })?.value == state,
              let code = params.first(where: { $0.name == "code" })?.value else { throw APIError.message("Anmelderückgabe konnte nicht bestätigt werden.") }
        _ = try await APIClient.shared.requestJSON(path: "/api/v3/auth/exchange", method: "POST", json: ["code": code, "verifier": verifier])
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
