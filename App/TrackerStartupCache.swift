import Foundation
import CryptoKit

/// A display-only snapshot, partitioned by server AND account. Contains no session or keys.
/// Server actions remain unavailable until authentication succeeds.
actor TrackerStartupCache {
    static let shared = TrackerStartupCache()
    struct Snapshot: Codable {
        var trackers: [Tracker]
        var date: Date
    }
    private let directory: URL
    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("TrackerCatalog", isDirectory: true)) {
        self.directory = directory
    }
    private func url(identity: String) -> URL {
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key + ".json")
    }
    func load(identity: String) -> Snapshot? {
        guard let data = try? Data(contentsOf: url(identity: identity)) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
    func save(_ trackers: [Tracker], date: Date, identity: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Snapshot(trackers: trackers, date: date))
            try data.write(to: url(identity: identity), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { /* A cache failure must never prevent live tracking. */ }
    }
    func clear(identity: String) { try? FileManager.default.removeItem(at: url(identity: identity)) }
}
