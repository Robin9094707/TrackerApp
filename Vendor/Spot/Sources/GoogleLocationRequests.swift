import Foundation

/// One visible request per tracker. Older stream packets/timeouts cannot finish a newer request.
struct GoogleLocationRequests {
    private var tokens: [String: UUID] = [:]
    var pending: Set<String> { Set(tokens.keys) }
    mutating func begin(_ id: String) -> UUID? {
        guard tokens[id] == nil else { return nil }
        let token = UUID()
        tokens[id] = token
        return token
    }
    func contains(_ id: String, token: UUID) -> Bool { tokens[id] == token }
    @discardableResult mutating func finish(_ id: String, token: UUID) -> Bool {
        guard contains(id, token: token) else { return false }
        tokens.removeValue(forKey: id)
        return true
    }
    mutating func reset() { tokens.removeAll() }
}
