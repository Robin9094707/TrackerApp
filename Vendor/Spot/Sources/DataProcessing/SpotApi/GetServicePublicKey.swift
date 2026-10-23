//
//  GetServicePublicKey.swift
//  Spot
//
//  Created by Leon Böttger on 14.12.24.
//

import BigInt
import CryptoKit
import Foundation
import LUI
import SwiftECC
import SwiftUI

class GetServicePublicKey {
    static var cachedKey: GooglePublicKeys.EciesAeadHkdfPublicKeys.EciesAeadHkdfPublicKey?

    static func get() async throws -> GooglePublicKeys.EciesAeadHkdfPublicKeys.EciesAeadHkdfPublicKey {
        if let cachedKey {
            return cachedKey
        }

        let payload = try await SpotApiManager.spotRequest(apiScope: "GetServicePublicKey", payload: Data())
        let pubKeysProto = try GooglePublicKeys(serializedBytes: payload)

        // return first key, doesnt matter
        for key in pubKeysProto.eciesAeadHkdfPublicKeys.keys {
            cachedKey = key
            return key
        }

        throw NSError(domain: "No Public Key was found!", code: 0, userInfo: nil)
    }
}
