//
//  SecurityDomainUrl.swift
//  Spot
//
//  Created by Leon Böttger on 10.12.24.
//

import Foundation
import LUI
import SwiftProtobuf
import SwiftUI

class SecurityDomainUrlGenerator {
    static func getUrl() -> URL? {
        var encryptionUnlockRequestExtras = EncryptionUnlockRequestExtras()
        encryptionUnlockRequestExtras.operation = 1
        encryptionUnlockRequestExtras.securityDomain.name = "finder_hw"
        encryptionUnlockRequestExtras.securityDomain.unknown = 0
        encryptionUnlockRequestExtras.sessionID = getRandomUUID()

        // Serialize to binary data
        guard let serializedData = try? encryptionUnlockRequestExtras.serializedData() else {
            return nil
        }

        // Encode to base64
        let base64Encoded = serializedData.base64EncodedString()

        let scope = "https://accounts.google.com/encryption/unlock/android?kdi="
        let url = scope + base64Encoded

        return URL(string: url)
    }
}
