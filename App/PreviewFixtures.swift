#if DEBUG
import Foundation

/// Synthetic public-location fixtures, compiled only into Debug builds for simulator UI checks.
enum PreviewFixtures {
    static func response(path: String) -> Data? {
        let json: String
        switch path {
        case "/api/account/profile": json = #"{"user":{"id":"main","username":"demo","display_name":"Demo","email":"","is_main_admin":true}}"#
        case "/api/security/2fa": json = #"{"two_factor":{"enabled":false}}"#
        case "/api/security/passkeys": json = #"{"passkeys":{"credentials":[]}}"#
        case "/api/admin/users": json = #"{"users":[]}"#
        case "/api/v2/backups": json = #"{"backups":[]}"#
        case "/api/comparison-tests": json = #"{"tests":[]}"#
        case "/api/internal-shares": json = #"{"received":[],"outgoing":[],"recipients":[],"catalog":[]}"#
        case "/api/v2/storage": json = #"{"cleanup":[{"id":"logs","label":"Alte Protokolle","description":"Alte Logdateien bereinigen","available":true,"bytes":1000}]}"#
        case "/api/google/guardian/status": json = #"{"runtime":{"ready":true,"tools_installed":true,"secrets_uploaded":true}}"#
        case "/api/mobile/v1/history":
            let now = Int(Date().timeIntervalSince1970)
            let points = [HistoryPoint(latitude: 52.51, longitude: 13.37, accuracyM: 20, timestamp: now - 120, network: "apple"), HistoryPoint(latitude: 52.5101, longitude: 13.3701, accuracyM: 25, timestamp: now - 90, network: "google"), HistoryPoint(latitude: 52.5102, longitude: 13.3702, accuracyM: 20, timestamp: now - 60, network: "apple")]
            return try? JSONEncoder().encode(HistoryResponse(status: "ok", tracker: bootstrap.trackers[0], points: points))
        case "/api/v2/groups": json = #"{"groups":[{"id":"travel","label":"Reisen","emoji":"🧳"}]}"#
        case "/api/polling/settings": json = #"{"polling":{"enabled":true,"providers":{"apple":{"interval_min":30,"interval_max":120},"google":{"interval_min":60,"interval_max":180},"samsung":{"interval_min":40,"interval_max":120}}}}"#
        case "/api/diagnostics": json = #"{"status":"completed","checks":[{"id":"connection","title":"Serververbindung","status":"ok","summary":"Alle Ortungsnetzwerke antworten."}]}"#
        case "/api/mobile/v1/trackers": return try? JSONEncoder().encode(bootstrap)
        default: return nil
        }
        return Data(json.utf8)
    }
    static var bootstrap: BootstrapResponse {
        let now = Int(Date().timeIntervalSince1970)
        let json = """
        {"status":"ok","trackers":[
          {"ref":"fusion:demo-bag","id":"demo-bag","name":"Rucksack","provider":"fusion","emoji":"🎒","favorite":true,"battery":"85 %","history_active":true,
           "location":{"latitude":52.5163,"longitude":13.3777,"timestamp":\(now-90),"accuracy_m":22,"network":"apple","address":{"label":"Platz des 18. März, Berlin"}},
           "linked_networks":["apple","google","samsung"],"source_health":{"apple":{"timestamp":\(now-90),"accuracy_m":22},"google":{"timestamp":\(now-300),"accuracy_m":45},"samsung":{"timestamp":\(now-180),"accuracy_m":30}},
           "details":{"note":"Demo: im Innenfach"},"found_notification":{"enabled":false},"departure_notification":{"enabled":true}},
          {"ref":"apple:demo-keys","name":"Schlüssel","provider":"apple","emoji":"🔑","favorite":true,"battery":"Gut",
           "location":{"latitude":52.5181,"longitude":13.3752,"timestamp":\(now-240),"accuracy_m":30,"address":{"label":"Platz der Republik, Berlin"}}},
          {"ref":"samsung:demo-bike","name":"Fahrrad","provider":"samsung","emoji":"🚲","battery":"70 %",
           "location":{"latitude":52.5142,"longitude":13.3501,"timestamp":\(now-4500),"accuracy_m":65,"address":{"label":"Tiergarten, Berlin"}}},
          {"ref":"google:demo-case","name":"Koffer","provider":"google","emoji":"🧳","battery":"Unbekannt"}],
         "saved_places":[{"id":"demo-place","label":"Brandenburger Tor","emoji":"🏛️","latitude":52.5163,"longitude":13.3777,"radius_m":100}],
         "geofences":[],"alerts":{"unread_count":0,"events":[]},"session":{"user":{"display_name":"Demo"}}}
        """
        return try! JSONDecoder().decode(BootstrapResponse.self, from: Data(json.utf8))
    }
}
#endif
