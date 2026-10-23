//
//  PersistenceController.swift
//  Spot
//
//  Created by Leon Böttger on 06.01.25.
//

import CoreData
import LUI
import UIKit

struct PersistenceController {
    private static let lock = NSRecursiveLock()
    private static var account: String?
    private static var current: PersistenceController?
    static var shared: PersistenceController {
        lock.lock()
        defer { lock.unlock() }
        let username = TokenManager.sharedInstance.username?.lowercased()
        if current == nil || username != account {
            account = username
            current = PersistenceController()
        }
        return current!
    }

    let container: NSPersistentContainer = {
        let bundle = Bundle(for: SpotResourceMarker.self)
        guard let url = bundle.url(forResource: "DataModel", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("The Google history model is missing from SpotIntegration.")
        }
        let container = NSPersistentContainer(name: "SpotGoogleHistory", managedObjectModel: model)
        // Google histories are isolated by account, separate from every server database.
        let account = TokenManager.sharedInstance.username?.lowercased() ?? "unconfigured"
        let accountID = SHA256.hash(data: Data(account.utf8)).hex
        let storeURL = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("SpotGoogle-\(accountID).sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        container.loadPersistentStores { _, error in
            if error != nil {
                showAlert(title: "Google-Verlauf nicht verfügbar", message: "Der lokale Verlauf konnte nicht geöffnet werden. Vorhandene Dateien bleiben erhalten. Bitte die App neu starten.")
            }
        }

        return container
    }()

    /// background thread for database work in background.
    private let databaseBackgroundQueue = DispatchQueue(label: "databaseQueue", qos: .utility)

    func getDatabaseQueue() -> DispatchQueue {
        databaseBackgroundQueue
    }

    /// Peforms all work on a background queue and merges changes into main context afterwards (serialized).
    func modifyDatabaseBackground(task: @escaping (NSManagedObjectContext) -> Void) {
        /// perform all operations in background - serialized (!!!)
        getDatabaseQueue().async {
            /// create new background context
            let privateMOC = container.newBackgroundContext()

            /// serialize operations
            privateMOC.performAndWait {
                /// Perform task
                task(privateMOC)

                if privateMOC.hasChanges {
                    /// merge in main context
                    do {
                        try privateMOC.save()

                    } catch {}
                }
            }
        }
    }

    /// Writes any changes to CoreData model to disk
    func store() {
        let context = container.viewContext

        // perform action synchronously
        context.performAndWait {
            /// only perform if any changes made to model
            if context.hasChanges {
                do {
                    /// write to disk
                    try context.save()
                } catch {
                    /// some error occured
                }
            }
        }
    }
}
