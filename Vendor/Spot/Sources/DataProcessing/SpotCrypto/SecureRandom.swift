//
//  SecureRandom.swift
//  Spot
//
//  Created by Leon Böttger on 17.12.24.
//

import Foundation

class SecureRandom {
    static func getBytes(_ count: Int) throws -> Data {
        var randomBytes = [UInt8](repeating: 0, count: count)
        let result = SecRandomCopyBytes(kSecRandomDefault, count, &randomBytes)
        guard result == errSecSuccess else {
            throw NSError(domain: "SecureRandomError", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "Failed to generate random bytes!"])
        }
        return Data(randomBytes)
    }
}
