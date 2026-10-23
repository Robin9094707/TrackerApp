//
//  SyncStorage.swift
//
//
//  Created by Leon Böttger on 11/23/20.
//  Copyright © 2020 Leon Böttger.
//

import Combine
import Foundation
import SwiftUI

public protocol SharedInstance: ObservableObject {
    static var sharedInstance: Self { get }
}

/// background thread for database work in background.
let userDefaultsQueue = DispatchQueue(label: "userDefaultsQueue", qos: .utility)

@propertyWrapper
public class SyncStorage<Value: Equatable & Codable, Key: RawRepresentable>: NSObject,
    ObservableObject
{
    private let key: String
    private let ud: UserDefaults
    private var value: Value {
        willSet {
            if let publisher = object.sharedInstance.objectWillChange as? ObservableObjectPublisher {
                publisher.send()
            } else {}
            objectWillChange.send()
        }
    }

    private let object: any SharedInstance.Type
    private var customType: Bool

    public convenience init(
        key: Key, defaultValue: Value, on: any SharedInstance.Type, ud: UserDefaults
    ) {
        self.init(key: String(describing: key.rawValue), defaultValue: defaultValue, on: on, ud: ud)
    }

    private init(key: String, defaultValue: Value, on: any SharedInstance.Type, ud: UserDefaults) {
        self.ud = ud
        self.key = key
        object = on

        if isValueUdCompatible(defaultValue) {
            // primitive types
            customType = false

            if let existingValue = ud.object(forKey: key) as? Value {
                value = existingValue
            } else {
                value = defaultValue
                ud.set(defaultValue, forKey: key)
            }
        } else {
            // custom types
            customType = true
            value = loadUD(key: key, alternativeData: defaultValue, ud: ud)
        }
        super.init()
        ud.addObserver(self, forKeyPath: key, options: .new, context: nil)
    }

    private func registerObserver() {
        ud.addObserver(self, forKeyPath: key, options: .new, context: nil)
    }

    private func unregisterObserver() {
        ud.removeObserver(self, forKeyPath: key, context: nil)
    }

    override public func observeValue(
        forKeyPath keyPath: String?, of object: Any?, change _: [NSKeyValueChangeKey: Any]?,
        context _: UnsafeMutableRawPointer?
    ) {
        userDefaultsQueue.async { [self] in
            guard let keyPath, object != nil, keyPath == key else {
                return
            }
            if customType {
                // custom objects
                let newValue = loadUD(key: key, alternativeData: value, ud: ud)

                if newValue != value {
                    DispatchQueue.main.async {
                        withAnimation(.spring()) {
                            self.value = newValue
                        }
                    }
                }
            } else {
                // primitive types
                if let newValue = ud.object(forKey: key) as? Value {
                    if value != newValue {
                        DispatchQueue.main.async {
                            withAnimation(.spring()) {
                                self.value = newValue
                            }
                        }
                    }
                }
            }
        }
    }

    deinit {
        unregisterObserver()
    }

    public var wrappedValue: Value {
        get { value }
        set {
            if newValue != value {
                value = newValue

                userDefaultsQueue.async { [self] in
                    unregisterObserver()
                    if customType {
                        newValue.storeUdNow(key: key, ud: ud)
                    } else {
                        ud.set(newValue, forKey: key)
                    }
                    registerObserver()
                }
            }
        }
    }
}

private func isValueUdCompatible(_ value: Any) -> Bool {
    value is Bool || value is Int
}

public extension Encodable {
    func storeUdNow(key: String, ud: UserDefaults) {
        if let encoded = try? JSONEncoder().encode(self) {
            ud.set(encoded, forKey: key)
        }
    }
}

public func loadUD<T: Decodable & Encodable>(key: String, alternativeData: T, ud: UserDefaults) -> T {
    if let decodedData = ud.object(forKey: key) as? Data {
        if let loadedData = try? JSONDecoder().decode(T.self, from: decodedData) {
            return loadedData
        }
    }
    alternativeData.storeUdNow(key: key, ud: ud)
    return alternativeData
}
