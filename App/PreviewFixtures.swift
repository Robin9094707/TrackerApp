#if DEBUG
import Foundation

/// Synthetic public-location fixtures, compiled only into Debug builds for simulator UI checks.
enum PreviewFixtures {
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
