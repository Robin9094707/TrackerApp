//
//  KeychainStore.swift
//
//
//  Created by Leon Böttger on 23.10.26.
//

import Foundation
import Security

final class KeychainStore {
    static let shared = KeychainStore(
        service: (Bundle.main.bundleIdentifier ?? "Spot") + ".spot.credentials",
        defaults: UserDefaults(suiteName: "eu.rjuhas.rjtracker.spot")!
    )

    private let service: String
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(service: String, defaults: UserDefaults) {
        self.service = service
        self.defaults = defaults
    }

    func load<Value: Codable>(_: Value.Type, for key: DeviceOnlyKeys) throws -> Value? {
        lock.lock()
        defer { lock.unlock() }

        if let data = try readData(for: key) {
            let value = try JSONDecoder().decode(Value?.self, from: data)
            defaults.removeObject(forKey: key.rawValue)
            return value
        }

        guard let legacyValue = defaults.object(forKey: key.rawValue) else { return nil }
        guard let legacyData = legacyValue as? Data else { throw StorageError.invalidData }
        let value = try JSONDecoder().decode(Value?.self, from: legacyData)

        if let value {
            let data = try JSONEncoder().encode(value)
            try writeData(data, for: key)
            guard try readData(for: key) == data else { throw StorageError.verificationFailed }
        }

        defaults.removeObject(forKey: key.rawValue)
        return value
    }

    func save(_ value: (some Encodable)?, for key: DeviceOnlyKeys) throws {
        lock.lock()
        defer { lock.unlock() }

        if let value {
            try writeData(JSONEncoder().encode(value), for: key)
        } else {
            try deleteData(for: key)
        }

        defaults.removeObject(forKey: key.rawValue)
    }

    func remove(for key: DeviceOnlyKeys) throws {
        lock.lock()
        defer { lock.unlock() }

        try deleteData(for: key)
        defaults.removeObject(forKey: key.rawValue)
    }

    private func query(for key: DeviceOnlyKeys) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private func readData(for key: DeviceOnlyKeys) throws -> Data? {
        var query = query(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StorageError.status(status) }
        guard let data = result as? Data else { throw StorageError.invalidData }
        return data
    }

    private func writeData(_ data: Data, for key: DeviceOnlyKeys) throws {
        let query = query(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let item = query.merging(attributes) { _, new in new }
        var status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        }
        guard status == errSecSuccess else { throw StorageError.status(status) }
    }

    private func deleteData(for key: DeviceOnlyKeys) throws {
        let status = SecItemDelete(query(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StorageError.status(status)
        }
    }

    private enum StorageError: LocalizedError {
        case status(OSStatus)
        case invalidData
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case let .status(status):
                "Keychain access failed (\(status)). Please unlock your device and try again."
            case .invalidData:
                "The stored credentials could not be read."
            case .verificationFailed:
                "The credentials could not be verified in Keychain. The previous stored values have been preserved."
            }
        }
    }
}
