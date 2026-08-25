import Foundation
import CoreLocation

struct AddressInfo: Codable, Hashable {
    var label: String?
    var displayName: String?
    var subtitle: String?
    var road: String?
    var houseNumber: String?
    var postcode: String?
    var locality: String?
    var state: String?
    var country: String?

    enum CodingKeys: String, CodingKey {
        case label, subtitle, road, state, country, locality, postcode
        case displayName = "display_name"
        case houseNumber = "house_number"
    }

    var bestText: String {
        displayName ?? label ?? [road, houseNumber, postcode, locality].compactMap { $0 }.joined(separator: " ")
    }
}

struct TrackerLocation: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var accuracyM: Double?
    var timestamp: Int?
    var network: String?
    var provider: String?
    var address: AddressInfo?
    var confidence: Double?
    var quality: String?

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, network, provider, address, confidence, quality
        case accuracyM = "accuracy_m"
        case timestamp
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct TrackerDetails: Codable, Hashable {
    var name: String?
    var emoji: String?
    var kind: String?
    var note: String?
    var aliases: [String]?
    var providerName: String?

    enum CodingKeys: String, CodingKey {
        case name, emoji, kind, note, aliases
        case providerName = "provider_name"
    }
}

struct ToggleSummary: Codable, Hashable { var enabled: Bool? }

struct Tracker: Codable, Identifiable, Hashable {
    var ref: String
    var name: String
    var provider: String
    var location: TrackerLocation?
    var lastSeenTs: Int?
    var battery: String?
    var status: String?
    var favorite: Bool?
    var archived: Bool?
    var hidden: Bool?
    var historyActive: Bool?
    var emoji: String?
    var kind: String?
    var details: TrackerDetails?
    var foundNotification: ToggleSummary?
    var departureNotification: ToggleSummary?
    var linkedNetworks: [String]?
    var recovery: JSONValue?
    var polling: JSONValue?
    var sourceHealth: JSONValue?
    var networkDisagreement: JSONValue?
    var capabilities: JSONValue?

    var id: String { ref }

    enum CodingKeys: String, CodingKey {
        case ref, name, provider, location, battery, status, favorite, archived, hidden, emoji, kind, details, recovery, polling, capabilities
        case lastSeenTs = "last_seen_ts"
        case historyActive = "history_active"
        case foundNotification = "found_notification"
        case departureNotification = "departure_notification"
        case linkedNetworks = "linked_networks"
        case sourceHealth = "source_health"
        case networkDisagreement = "network_disagreement"
    }
}

struct SessionInfo: Codable, Hashable {
    var authenticated: Bool?
    var user: UserInfo?
    var csrfToken: String?
    var tenantId: String?
    var serverTime: Int?
    var timezone: String?
    var appName: String?
    var appVersion: String?
    var mobileApiVersion: String?

    enum CodingKeys: String, CodingKey {
        case authenticated, user, timezone
        case csrfToken = "csrf_token"
        case tenantId = "tenant_id"
        case serverTime = "server_time"
        case appName = "app_name"
        case appVersion = "app_version"
        case mobileApiVersion = "mobile_api_version"
    }
}

struct UserInfo: Codable, Hashable {
    var id: String?
    var username: String?
    var displayName: String?
    var role: String?
    var isMainAdmin: Bool?

    enum CodingKeys: String, CodingKey {
        case id, username, role
        case displayName = "display_name"
        case isMainAdmin = "is_main_admin"
    }
}

struct ServerAPIInfo: Codable, Hashable {
    var version: String?
    var serverName: String?
    var serverVersion: String?
    var timezone: String?
    var generatedAt: Int?

    enum CodingKeys: String, CodingKey {
        case version, timezone
        case serverName = "server_name"
        case serverVersion = "server_version"
        case generatedAt = "generated_at"
    }
}

struct AlertEvent: Codable, Identifiable, Hashable {
    var id: String
    var ts: Int?
    var type: String?
    var severity: String?
    var title: String?
    var body: String?
    var acknowledged: Bool?
    var trackerRef: String?
    var location: JSONValue?

    enum CodingKeys: String, CodingKey {
        case id, ts, type, severity, title, body, acknowledged, location
        case trackerRef = "tracker_ref"
    }
}

struct AlertSummary: Codable, Hashable {
    var enabled: Bool?
    var unreadCount: Int?
    var eventCount: Int?
    var events: [AlertEvent]?
    var quietHours: JSONValue?
    var health: JSONValue?

    enum CodingKeys: String, CodingKey {
        case enabled, events, health
        case unreadCount = "unread_count"
        case eventCount = "event_count"
        case quietHours = "quiet_hours"
    }
}

struct PushStatus: Codable, Hashable {
    var enabled: Bool?
    var mirrorEvents: Bool?
    var registeredDevices: Int?
    var activeDevices: Int?
    var serverConfigured: Bool?
    var environment: String?
    var bundleId: String?
    var requiresApplePushKey: Bool?

    enum CodingKeys: String, CodingKey {
        case enabled, environment
        case mirrorEvents = "mirror_events"
        case registeredDevices = "registered_devices"
        case activeDevices = "active_devices"
        case serverConfigured = "server_configured"
        case bundleId = "bundle_id"
        case requiresApplePushKey = "requires_apple_push_key"
    }
}

struct GeofenceCenter: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var address: AddressInfo?
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct Geofence: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var emoji: String?
    var enabled: Bool?
    var center: GeofenceCenter
    var radiusM: Double?
    var notifyEnter: Bool?
    var notifyExit: Bool?
    var color: String?

    enum CodingKeys: String, CodingKey {
        case id, label, emoji, enabled, center, color
        case radiusM = "radius_m"
        case notifyEnter = "notify_enter"
        case notifyExit = "notify_exit"
    }
}

struct SavedPlace: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var emoji: String?
    var latitude: Double?
    var longitude: Double?
    var radiusM: Double?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id, label, emoji, latitude, longitude, note
        case radiusM = "radius_m"
    }
}

struct BootstrapResponse: Codable {
    var status: String
    var api: ServerAPIInfo?
    var session: SessionInfo?
    var trackers: [Tracker]
    var trackerCount: Int?
    var geofences: [Geofence]?
    var savedPlaces: [SavedPlace]?
    var trackerGroups: [JSONValue]?
    var alerts: AlertSummary?
    var push: PushStatus?
    var system: JSONValue?
    var providers: JSONValue?
    var polling: JSONValue?
    var transit: JSONValue?
    var recovery: JSONValue?
    var capabilities: JSONValue?

    enum CodingKeys: String, CodingKey {
        case status, api, session, trackers, alerts, push, system, providers, polling, transit, recovery, capabilities, geofences
        case trackerCount = "tracker_count"
        case savedPlaces = "saved_places"
        case trackerGroups = "tracker_groups"
    }
}

struct PairResponse: Codable {
    var status: String
    var message: String?
    var csrfToken: String?
    var user: UserInfo?
    var recoveryAvailable: Bool?

    enum CodingKeys: String, CodingKey {
        case status, message, user
        case csrfToken = "csrf_token"
        case recoveryAvailable = "recovery_available"
    }
}

struct SessionResponse: Codable {
    var status: String
    var authenticated: Bool?
    var user: UserInfo?
    var csrfToken: String?
    var tenantId: String?
    var appName: String?
    var appVersion: String?

    enum CodingKeys: String, CodingKey {
        case status, authenticated, user
        case csrfToken = "csrf_token"
        case tenantId = "tenant_id"
        case appName = "app_name"
        case appVersion = "app_version"
    }
}

struct HistoryPoint: Codable, Identifiable, Hashable {
    var latitude: Double
    var longitude: Double
    var accuracyM: Double?
    var timestamp: Int
    var observedAtLocal: String?
    var network: String?
    var address: AddressInfo?
    var id: String { "\(timestamp)-\(latitude)-\(longitude)" }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, timestamp, network, address
        case accuracyM = "accuracy_m"
        case observedAtLocal = "observed_at_local"
    }
}

struct HistorySummary: Codable, Hashable {
    var matchingReports: Int?
    var confirmedStays: Int?
    var distanceM: Double?
    var staySeconds: Double?
    var stayText: String?

    enum CodingKeys: String, CodingKey {
        case matchingReports = "matching_reports"
        case confirmedStays = "confirmed_stays"
        case distanceM = "distance_m"
        case staySeconds = "stay_seconds"
        case stayText = "stay_text"
    }
}

struct HistoryResponse: Codable {
    var status: String
    var tracker: Tracker
    var summary: HistorySummary?
    var points: [HistoryPoint]
    var returned: Int?
    var matchingTotal: Int?
    var stays: [JSONValue]?
    var places: [JSONValue]?

    enum CodingKeys: String, CodingKey {
        case status, tracker, summary, points, returned, stays, places
        case matchingTotal = "matching_total"
    }
}

struct APIRoute: Codable, Identifiable, Hashable {
    var path: String
    var endpoint: String
    var methods: [String]
    var arguments: [String]?
    var mobileNative: Bool?
    var id: String { "\(path)|\(methods.joined(separator: ","))" }

    enum CodingKeys: String, CodingKey {
        case path, endpoint, methods, arguments
        case mobileNative = "mobile_native"
    }
}

struct CapabilityResponse: Codable {
    var status: String
    var apiVersion: String?
    var allApiRoutes: [APIRoute]?
    var routeCount: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case apiVersion = "api_version"
        case allApiRoutes = "all_api_routes"
        case routeCount = "route_count"
    }
}

struct APIMessage: Codable { var status: String?; var message: String?; var code: String? }

indirect enum JSONValue: Codable, Hashable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? c.decode([JSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .bool(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .null: try c.encodeNil()
        }
    }

    var foundationObject: Any {
        switch self {
        case .string(let v): v
        case .number(let v): v
        case .bool(let v): v
        case .object(let v): v.mapValues(\.foundationObject)
        case .array(let v): v.map(\.foundationObject)
        case .null: NSNull()
        }
    }

    var prettyPrinted: String {
        guard JSONSerialization.isValidJSONObject(foundationObject),
              let data = try? JSONSerialization.data(withJSONObject: foundationObject, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return String(describing: self) }
        return string
    }
}
