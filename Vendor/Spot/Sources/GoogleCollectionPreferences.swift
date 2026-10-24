import Foundation

// Default true preserves v5.1's collection behavior and existing history.
enum GoogleCollectionPreferences {
    static func key(account: String, deviceID: String) -> String {
        let account = account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let material = "\(account.utf8.count):\(account)|\(deviceID.utf8.count):\(deviceID)"
        return "native.collectHistory." + SHA256.hash(data: Data(material.utf8)).hex
    }
    static func enabled(account: String, deviceID: String, defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key(account: account, deviceID: deviceID)) as? Bool ?? true
    }
    static func set(_ enabled: Bool, account: String, deviceID: String, defaults: UserDefaults) {
        defaults.set(enabled, forKey: key(account: account, deviceID: deviceID))
    }
}
