import Foundation

@MainActor
final class APIClient {
    static let shared = APIClient()
    private(set) var baseURL: URL?
    private(set) var csrfToken: String = KeychainStore.get("csrf") ?? ""
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        if let saved = UserDefaults.standard.string(forKey: "serverURL") { baseURL = URL(string: saved) }
    }

    func configure(server: String) throws {
        var text = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), url.host != nil else {
            throw APIError.message("Die Serveradresse ist ungültig.")
        }
        baseURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: "serverURL")
    }

    func pair(server: String, username: String, password: String) async throws -> PairResponse {
        try configure(server: server)
        let body: [String: Any] = ["username": username, "pw": password]
        let response: PairResponse = try await request(path: "/api/mobile/v1/pair", method: "POST", json: body, needsCSRF: false)
        if let token = response.csrfToken { saveCSRF(token) }
        if !username.isEmpty { UserDefaults.standard.set(username, forKey: "username") }
        return response
    }

    func pair2FA(code: String) async throws -> PairResponse {
        let response: PairResponse = try await request(path: "/api/mobile/v1/pair/2fa", method: "POST", json: ["code": code], needsCSRF: false)
        if let token = response.csrfToken { saveCSRF(token) }
        return response
    }

    func session() async throws -> SessionResponse {
        let response: SessionResponse = try await request(path: "/api/mobile/v1/session")
        if let token = response.csrfToken { saveCSRF(token) }
        return response
    }

    func bootstrap() async throws -> BootstrapResponse {
        try await request(path: "/api/mobile/v1/bootstrap")
    }

    func history(tracker: String, days: Int) async throws -> HistoryResponse {
        try await request(path: "/api/mobile/v1/history", query: [
            URLQueryItem(name: "ref", value: tracker), URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "limit", value: "1800"), URLQueryItem(name: "resolve_addresses", value: "0")
        ])
    }

    func capabilities() async throws -> CapabilityResponse {
        try await request(path: "/api/mobile/v1/capabilities")
    }

    func action(_ name: String, payload: [String: Any] = [:]) async throws -> JSONValue {
        var body = payload
        body["action"] = name
        return try await requestJSON(path: "/api/mobile/v1/action", method: "POST", json: body)
    }

    func registerPush(token: String, label: String, model: String, systemVersion: String, appVersion: String) async throws -> JSONValue {
        try await requestJSON(path: "/api/mobile/v1/push", method: "POST", json: [
            "token": token, "label": label, "device_model": model,
            "system_version": systemVersion, "app_version": appVersion, "mirror_events": true
        ])
    }

    func logout() async {
        _ = try? await requestJSON(path: "/api/logout", method: "POST", json: [:])
        if let baseURL {
            HTTPCookieStorage.shared.cookies(for: baseURL)?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
        csrfToken = ""
        KeychainStore.delete("csrf")
    }

    func requestJSON(path: String, method: String = "GET", json: [String: Any]? = nil) async throws -> JSONValue {
        let data = try await raw(path: path, method: method, json: json, query: [])
        return try decoder.decode(JSONValue.self, from: data)
    }

    func requestRaw(path: String, method: String, bodyText: String) async throws -> String {
        var object: [String: Any]?
        if !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = bodyText.data(using: .utf8),
                  let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw APIError.message("Der Request-Body muss ein JSON-Objekt sein.")
            }
            object = parsed
        }
        let data = try await raw(path: path, method: method, json: object, query: [])
        if let object = try? JSONSerialization.jsonObject(with: data), JSONSerialization.isValidJSONObject(object),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            return String(decoding: pretty, as: UTF8.self)
        }
        return String(decoding: data, as: UTF8.self)
    }

    func request<T: Decodable>(path: String, method: String = "GET", json: [String: Any]? = nil, query: [URLQueryItem] = [], needsCSRF: Bool? = nil) async throws -> T {
        let data = try await raw(path: path, method: method, json: json, query: query, needsCSRF: needsCSRF)
        do { return try decoder.decode(T.self, from: data) }
        catch {
            DebugLogger.shared.log("Decode error for \(path): \(error)")
            throw APIError.message("Die Serverantwort konnte nicht gelesen werden: \(error.localizedDescription)")
        }
    }

    private func raw(path: String, method: String, json: [String: Any]?, query: [URLQueryItem], needsCSRF: Bool? = nil) async throws -> Data {
        guard let baseURL else { throw APIError.message("Noch kein Server gekoppelt.") }
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.message("Ungültige Server-URL.")
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, cleanPath].filter { !$0.isEmpty }.joined(separator: "/"))
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.message("Ungültige API-URL.") }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = method.uppercased()
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("RJTracker-iOS/2.0", forHTTPHeaderField: "User-Agent")
        if let json {
            guard JSONSerialization.isValidJSONObject(json) else { throw APIError.message("Ungültiger JSON-Body.") }
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let writing = !["GET", "HEAD"].contains(request.httpMethod ?? "GET")
        if (needsCSRF ?? writing), !csrfToken.isEmpty { request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token") }

        DebugLogger.shared.log("API \(request.httpMethod ?? "GET") \(url.path)")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.message("Keine HTTP-Antwort erhalten.") }
        if let newCSRF = http.value(forHTTPHeaderField: "X-CSRF-Token"), !newCSRF.isEmpty { saveCSRF(newCSRF) }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? decoder.decode(APIMessage.self, from: data)
            let message = envelope?.message ?? "Serverfehler HTTP \(http.statusCode)."
            if http.statusCode == 401 { NotificationCenter.default.post(name: .apiSessionExpired, object: nil) }
            throw APIError.http(http.statusCode, message)
        }
        if let envelope = try? decoder.decode(APIMessage.self, from: data), envelope.status == "error" {
            throw APIError.message(envelope.message ?? "Die Aktion konnte nicht ausgeführt werden.")
        }
        return data
    }

    private func saveCSRF(_ token: String) {
        csrfToken = token
        KeychainStore.set(token, for: "csrf")
    }
}

enum APIError: LocalizedError {
    case message(String)
    case http(Int, String)
    var errorDescription: String? {
        switch self { case .message(let text), .http(_, let text): text }
    }
}

extension Notification.Name {
    static let apiSessionExpired = Notification.Name("apiSessionExpired")
    static let apnsTokenAvailable = Notification.Name("apnsTokenAvailable")
}

