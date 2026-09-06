import Foundation

struct TrackerGroup: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var emoji: String?
}
struct GroupResponse: Decodable { var groups: [TrackerGroup] }
struct TrackerCatalogResponse: Decodable { var trackers: [Tracker] }

struct PollingInterval: Equatable {
    var minimum: Int
    var maximum: Int
    static func bounds(for provider: String) -> ClosedRange<Int> {
        switch provider { case "apple": 15...300; case "samsung": 20...600; default: 30...900 }
    }
    func isValid(for provider: String) -> Bool {
        Self.bounds(for: provider).contains(minimum) && Self.bounds(for: provider).contains(maximum) && minimum <= maximum
    }
}

extension JSONValue {
    subscript(_ key: String) -> JSONValue { objectValue?[key] ?? .null }
    var arrayValue: [JSONValue] { if case .array(let values) = self { return values }; return [] }
    var integer: Int { Int(min(max(numberValue ?? 0, Double(Int.min) + 2048), Double(Int.max) - 2048)) }
}

struct NativeShareOptions {
    var password = ""
    var expiryHours = 24
    var canLocate = true
    var showHistory = false
    var precision = "exact"
    var form: [String: String] {
        ["pw": password, "expires_hours": String(expiryHours), "can_locate": canLocate ? "1" : "0",
         "show_history": showHistory ? "1" : "0", "location_precision": precision,
         "show_accuracy": "1", "show_address": "1", "show_battery": "1", "show_provider": "1",
         "show_geofences": "0", "show_transit": "0", "can_navigate": "1"]
    }
}
