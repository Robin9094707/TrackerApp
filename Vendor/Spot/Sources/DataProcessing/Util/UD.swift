//
//  UD.swift
//  Spot
//
//  Created by Leon Böttger on 10.12.24.
//

import Foundation

public extension Encodable {
    func storeUdNow(key: String, ud: UserDefaults) {
        if let encoded = try? JSONEncoder().encode(self) {
            ud.set(encoded, forKey: key)
        }
    }
}

public func loadUD<T: Decodable & Encodable>(key: String, ud: UserDefaults) -> T? {
    if let decodedData = ud.object(forKey: key) as? Data {
        if let loadedData = try? JSONDecoder().decode(T.self, from: decodedData) {
            return loadedData
        }
    }
    return nil
}
