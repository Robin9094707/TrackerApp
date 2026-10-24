import Foundation
import CoreData

@main struct GoogleMigrationCheck {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }
    static func main() throws {
        let models = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let old = NSManagedObjectModel(contentsOf: models.appendingPathComponent("DataModel.mom")),
              let current = NSManagedObjectModel(contentsOf: models.appendingPathComponent("DataModel51.mom")) else { fatalError("Both the v5.0 and v5.1 database models must be bundled") }
        // This host executable has no app classes; the same entities are exercised using KVC.
        for model in [old, current] { for entity in model.entities { entity.managedObjectClassName = "NSManagedObject" } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("v50.sqlite")
        let target = directory.appendingPathComponent("v51.sqlite")
        let oldCoordinator = NSPersistentStoreCoordinator(managedObjectModel: old)
        let oldStore = try oldCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: source, options: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = oldCoordinator
        let device = NSEntityDescription.insertNewObject(forEntityName: "StoredDevice", into: context)
        device.setValue("existing-google-tracker", forKey: "canonicDeviceId")
        let report = NSEntityDescription.insertNewObject(forEntityName: "StoredLocationReport", into: context)
        report.setValue(51.43, forKey: "latitude"); report.setValue(6.76, forKey: "longitude")
        report.setValue(Float(14), forKey: "accuracy"); report.setValue(Date(timeIntervalSince1970: 1_790_000_000), forKey: "time")
        try context.save(); context.reset(); try oldCoordinator.remove(oldStore)
        let mapping = try NSMappingModel.inferredMappingModel(forSourceModel: old, destinationModel: current)
        let migration = NSMigrationManager(sourceModel: old, destinationModel: current)
        try migration.migrateStore(from: source, sourceType: NSSQLiteStoreType, options: nil,
                                   with: mapping, toDestinationURL: target, destinationType: NSSQLiteStoreType, destinationOptions: nil)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: current)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: target, options: nil)
        let migrated = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        migrated.persistentStoreCoordinator = coordinator
        let devices = try migrated.fetch(NSFetchRequest<NSManagedObject>(entityName: "StoredDevice"))
        let reports = try migrated.fetch(NSFetchRequest<NSManagedObject>(entityName: "StoredLocationReport"))
        require(devices.count == 1 && devices[0].value(forKey: "canonicDeviceId") as? String == "existing-google-tracker", "Existing tracker was lost during migration")
        require(reports.count == 1 && reports[0].value(forKey: "latitude") as? Double == 51.43, "Existing location report was changed")
        require(current.entitiesByName["StoredLocationReport"]?.attributesByName["name"] != nil, "New semantic report attribute missing")
        reports[0].setValue("Semantic report supported", forKey: "name"); try migrated.save()
        try coordinator.remove(store)
        print("Google v5.0 → v5.1 Core Data migration passed: existing tracker, coordinates and reports preserved.")
    }
}
