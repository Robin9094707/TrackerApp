import Foundation

@MainActor
final class APIClient {
    static let shared = APIClient()
    private(set) var baseURL: URL?
    private(set) var csrfToken: String = KeychainStore.get("csrf") ?? ""
    private let transport: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var historyCache: [String: (Date, HistoryResponse)] = [:]
    private var historyGeneration = UUID()
    private var historyTasks: [String: Task<HistoryResponse, Error>] = [:]

    func clearHistoryCache() {
        historyGeneration = UUID()
        historyTasks.values.forEach { $0.cancel() }
        historyTasks.removeAll(); historyCache.removeAll()
    }


    init(transport: URLSession = .shared, baseURL: URL? = nil) {
        self.transport = transport
        if let baseURL { self.baseURL = baseURL; return }
        if let saved = UserDefaults.standard.string(forKey: "serverURL") { self.baseURL = URL(string: saved) }
    }

    func configure(server: String) throws {
        var text = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), url.host != nil else {
            throw APIError.message("Die Serveradresse ist ungültig.")
        }
        if baseURL != url { clearHistoryCache() }
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

    func tracker(reference: String) async throws -> Tracker {
        let response: SingleTrackerResponse = try await request(path: "/api/mobile/v1/tracker", query: [.init(name: "ref", value: reference)])
        return response.tracker
    }

    func trackerCatalog() async throws -> [Tracker] {
        let response: TrackerCatalogResponse = try await request(path: "/api/mobile/v1/trackers", query: [.init(name: "limit", value: "1000")])
        return response.trackers
    }

    func history(tracker: String, days: Int, dates: [String] = [], force: Bool = false) async throws -> HistoryResponse {
        let key = "\(baseURL?.absoluteString ?? "")|\(csrfToken)|\(tracker)|\(days)|\(dates.sorted().joined(separator: ","))"
        if !force, let (date, response) = historyCache[key], Date().timeIntervalSince(date) < 45 { return response }
        if let task = historyTasks[key] { return try await task.value }
        let generation = historyGeneration
        let task = Task<HistoryResponse, Error> {
            try await self.request(path: "/api/mobile/v1/history", query: [
                .init(name: "ref", value: tracker), .init(name: "days", value: String(days)),
                .init(name: "dates", value: dates.isEmpty ? nil : dates.sorted().joined(separator: ",")),
                .init(name: "limit", value: "2000"), .init(name: "resolve_addresses", value: "0"), .init(name: "observation_limit", value: "1")
            ])
        }
        historyTasks[key] = task
        defer { if generation == historyGeneration { historyTasks[key] = nil } }
        let response = try await task.value
        try Task.checkCancellation()
        guard generation == historyGeneration else { throw CancellationError() }
        if historyCache.count >= 8 { historyCache.removeAll() }
        historyCache[key] = (Date(), response)
        return response
    }

    func historyStream(tracker: String, days: Int, dates: [String] = [], cursor: String?, replay: Bool) async throws -> HistoryStreamResponse {
        var query = [URLQueryItem(name: "ref", value: tracker), .init(name: "days", value: String(days)),
                     .init(name: "limit", value: "3000"), .init(name: "replay", value: replay ? "1" : "0")]
        if !dates.isEmpty { query.append(.init(name: "dates", value: dates.sorted().joined(separator: ","))) }
        if let cursor { query.append(.init(name: "cursor", value: cursor)) }
        return try await request(path: "/api/mobile/v1/history/stream", query: query)
    }

    func historyCalendar(tracker: String) async throws -> HistoryCalendarResponse {
        try await request(path: "/api/mobile/v1/history/days", query: [.init(name: "ref", value: tracker)])
    }

    func downloadBackup(name: String) async throws -> URL {
        guard name == URL(fileURLWithPath: name).lastPathComponent, name.hasSuffix(".zip") else { throw APIError.message("Ungültiger Backup-Dateiname.") }
        let data = try await raw(path: "/api/v2/backups/\(name)", method: "GET", json: nil, query: [])
        guard data.starts(with: [0x50, 0x4b]) else { throw APIError.message("Der Server hat kein ZIP-Backup geliefert.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Backup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        return file
    }

    func capabilities() async throws -> CapabilityResponse {
        try await request(path: "/api/mobile/v1/capabilities")
    }

    func alerts(limit: Int = 150, unreadOnly: Bool = false) async throws -> AlertSummary {
        try await request(path: "/api/mobile/v1/alerts", query: [.init(name: "limit", value: String(min(500, max(1, limit)))), .init(name: "unread_only", value: unreadOnly ? "1" : "0")])
    }

    func pushDevices() async throws -> PushDevicesResponse {
        try await request(path: "/api/mobile/v1/push")
    }

    func removePushDevice(id: String) async throws {
        _ = try await requestJSON(path: "/api/mobile/v1/push", method: "DELETE", json: ["device_id": id])
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
        clearHistoryCache()
        _ = try? await requestJSON(path: "/api/logout", method: "POST", json: [:])
        if let baseURL {
            HTTPCookieStorage.shared.cookies(for: baseURL)?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
        csrfToken = ""
        KeychainStore.delete("csrf")
    }

    func requestJSON(path: String, method: String = "GET", json: [String: Any]? = nil, query: [URLQueryItem] = []) async throws -> JSONValue {
        let data = try await raw(path: path, method: method, json: json, query: query)
        return try decoder.decode(JSONValue.self, from: data)
    }

    func requestForm(path: String, values: [String: String]) async throws -> JSONValue {
        let data = try await raw(path: path, method: "POST", json: nil, query: [], form: values)
        return try decoder.decode(JSONValue.self, from: data)
    }

    static func formBody(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.keys.sorted().map { URLQueryItem(name: $0, value: values[$0]) }
        return Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
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
        guard let parts = URLComponents(string: path), parts.scheme == nil, parts.host == nil else {
            throw APIError.message("Bitte einen relativen API-Pfad angeben.")
        }
        let data = try await raw(path: parts.path, method: method, json: object, query: parts.queryItems ?? [])
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

    private func raw(path: String, method: String, json: [String: Any]?, query: [URLQueryItem], needsCSRF: Bool? = nil, form: [String: String]? = nil) async throws -> Data {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            guard method == "GET", let data = PreviewFixtures.response(path: path) else { throw APIError.message("Im UI-Test sind Serveränderungen deaktiviert.") }
            return data
        }
        #endif
        guard let baseURL else { throw APIError.message("Noch kein Server gekoppelt.") }
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.message("Ungültige Server-URL.")
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, cleanPath.removingPercentEncoding ?? cleanPath].filter { !$0.isEmpty }.joined(separator: "/"))
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.message("Ungültige API-URL.") }
        let slowOperation = path.contains("/backups") || path.contains("/cleanup") || path.contains("/tools") || path.contains("/import") || path.contains("/auth/complete") || path == "/api/login"
        let timeout: TimeInterval = slowOperation ? 180 : (path.hasSuffix("/history") ? 60 : 25)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method.uppercased()
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("RJTracker-iOS/4.0", forHTTPHeaderField: "User-Agent")
        request.setValue("iPhone / iPad · RJ Tracker", forHTTPHeaderField: "X-RJ-Device-Label")
        if let json {
            guard JSONSerialization.isValidJSONObject(json) else { throw APIError.message("Ungültiger JSON-Body.") }
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let form {
            request.httpBody = Self.formBody(form)
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        let writing = !["GET", "HEAD"].contains(request.httpMethod ?? "GET")
        if (needsCSRF ?? writing), !csrfToken.isEmpty { request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token") }

        DebugLogger.shared.log("API \(request.httpMethod ?? "GET") \(url.path)")
        let (data, response) = try await transport.data(for: request)
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
        if let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let token = envelope["csrf_token"] as? String, !token.isEmpty { saveCSRF(token) }
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


struct SingleTrackerResponse: Decodable { let tracker: Tracker }

