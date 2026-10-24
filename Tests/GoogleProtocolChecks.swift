import Foundation
import Combine

@main struct GoogleProtocolChecks {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
    static func main() async throws {
        let suite = "google-migration-test-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        // v5.0 wrote custom/optional values as JSON Data and primitives directly.
        preferences.set(try JSONEncoder().encode(Optional("saved-google@example.invalid")), forKey: "username")
        preferences.set(7, forKey: "ownerKeyVersion")
        preferences.set(false, forKey: "backgroundScanning")
        let username = SyncStorage(key: MigrationKey.username, defaultValue: Optional<String>.none, on: MigrationOwner.self, ud: preferences)
        let version = SyncStorage(key: MigrationKey.ownerKeyVersion, defaultValue: 1, on: MigrationOwner.self, ud: preferences)
        let scanning = SyncStorage(key: MigrationKey.backgroundScanning, defaultValue: true, on: MigrationOwner.self, ud: preferences)
        check(username.wrappedValue == "saved-google@example.invalid", "v5.0 Google account was not migrated")
        check(version.wrappedValue == 7 && scanning.wrappedValue == false, "Existing Google preferences were reset")
        username.wrappedValue = "saved-google@example.invalid"
        check(preferences.data(forKey: "username") != nil, "Migration discarded the original persisted account")
        // Two messages delivered as one byte stream, fragmented inside a multi-byte size.
        let payload = Data(repeating: 7, count: 130)
        let bytes = Data([41, 8, 0x82, 0x01]) + payload + Data([8, 1, 9])
        for split in 0...bytes.count {
            var parser = GoogleMCSDecoder()
            let first = try parser.append(Data(bytes.prefix(split)))
            let second = try parser.append(Data(bytes.dropFirst(split)))
            let frames = first + second
            check(frames.count == 2, "Fragmented/multiple reports were lost at offset \(split)")
            check(frames[0].payload == payload && frames[1].payload == Data([9]), "Report order or payload changed")
        }
        var parser = GoogleMCSDecoder()
        var collected: [GoogleMCSDecoder.Frame] = []
        for byte in bytes { collected += try parser.append(Data([byte])) }
        check(collected.count == 2, "Bytewise network delivery lost a report")
        do {
            let _: Int = try await googleCallback(seconds: 0.03) { _ in }
            fatalError("Silent network callback never timed out")
        } catch is URLError { }
        let value: Int = try await googleCallback(seconds: 0.1) { done in
            done(.success(42)); done(.success(9)); done(.failure(URLError(.badServerResponse)))
        }
        check(value == 42, "A second completion changed the operation's result")
        let task = Task { () throws -> Int in try await googleCallback(seconds: 5) { _ in } }
        task.cancel()
        do { _ = try await task.value; fatalError("Cancelled setup stayed pending") } catch is CancellationError { }
        print("Google protocol checks passed: every stream split, multi-report delivery, deadlines, repeated callbacks and cancellation.")
    }
}

private enum MigrationKey: String { case username, ownerKeyVersion, backgroundScanning }
private final class MigrationOwner: SharedInstance {
    static let sharedInstance = MigrationOwner()
    let objectWillChange = ObservableObjectPublisher()
}
