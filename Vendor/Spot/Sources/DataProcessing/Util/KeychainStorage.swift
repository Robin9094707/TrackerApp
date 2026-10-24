//
//  KeychainStorage.swift
//
//
//  Created by Leon Böttger on 23.10.26.
//

import Combine
import Foundation
import Combine

@propertyWrapper
final class KeychainStorage<Value: Codable & Equatable> {
    private let key: DeviceOnlyKeys
    private let object: any SharedInstance.Type
    private let lock = NSRecursiveLock()
    private var value: Value?
    private var loaded = false
    private var reportedError = false

    init(key: DeviceOnlyKeys, on object: any SharedInstance.Type) {
        self.key = key
        self.object = object
        loadIfNecessary()
    }

    var wrappedValue: Value? {
        get {
            lock.lock()
            defer { lock.unlock() }
            loadIfNecessary()
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }

            do {
                try KeychainStore.shared.save(newValue, for: key)
                if !loaded || value != newValue {
                    (object.sharedInstance.objectWillChange as? ObservableObjectPublisher)?.send()
                    value = newValue
                }
                loaded = true
                reportedError = false
            } catch {
                report(error)
            }
        }
    }

    private func loadIfNecessary() {
        guard !loaded else { return }
        do {
            value = try KeychainStore.shared.load(Value.self, for: key)
            loaded = true
            reportedError = false
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        guard !reportedError else { return }
        reportedError = true
        showAlert(title: "Secure Storage Error", message: error.localizedDescription)
    }
}
