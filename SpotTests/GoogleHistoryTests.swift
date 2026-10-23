import XCTest
import CoreData
@testable import SpotIntegration

final class GoogleHistoryTests: XCTestCase {
    func testAccountHistoriesAreIsolatedAndSurviveSwitching() throws {
        let manager = TokenManager.sharedInstance
        let previous = manager.username
        defer { manager.username = previous }
        let unique = UUID().uuidString
        let firstAccount = "first-\(unique)@example.invalid"
        let secondAccount = "second-\(unique)@example.invalid"
        manager.username = firstAccount
        let first = PersistenceController.shared.container
        XCTAssertEqual(first.persistentStoreCoordinator.persistentStores.count, 1,
                       "The framework must contain and load its Core Data model.")
        let url = try XCTUnwrap(first.persistentStoreDescriptions.first?.url)
        var failure: Error?
        first.viewContext.performAndWait {
            let device = StoredDevice(context: first.viewContext)
            device.canonicDeviceId = "preserved-device"
            do { try first.viewContext.save() } catch { failure = error }
        }
        if let failure { throw failure }
        manager.username = secondAccount
        let second = PersistenceController.shared.container
        XCTAssertNotEqual(second.persistentStoreDescriptions.first?.url, url)
        var count = -1
        second.viewContext.performAndWait {
            count = (try? second.viewContext.count(for: StoredDevice.fetchRequest())) ?? -1
        }
        XCTAssertEqual(count, 0, "A second Google account must not inherit the first account's history.")
        manager.username = firstAccount
        let restored = PersistenceController.shared.container
        XCTAssertEqual(restored.persistentStoreDescriptions.first?.url, url)
        restored.viewContext.performAndWait {
            count = (try? restored.viewContext.count(for: StoredDevice.fetchRequest())) ?? -1
        }
        XCTAssertEqual(count, 1, "Switching accounts must retain the first account's local data.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
