//
//  SECP160r1.swift
//  Spot
//
//  Created by Leon Böttger on 09.12.24.
//

import BigInt
import SwiftECC
import SwiftUI

class SECP160r1 {
    static let domain = getDomain()

    private static func getDomain() -> Domain {
        try! Domain.instance(pem: """
        -----BEGIN EC PARAMETERS-----
        MIGvAgEBMCAGByqGSM49AQECFQD/////////////////////f////zBDBBT/////
        ////////////////f////AQUHJe+/FS9eotlrPifgdTUrcVl+kUDFQAQU83kLBTW
        luZ2h1YVF1M78/gzRQQpBEqWtWiO9XMoRmRpiWjDi7kTy/yCI6YoVTFolH1Z3MkS
        BCNRN3rF+zICFQEAAAAAAAAAAAAB9Mj5J67TynUiVwIBAQ==
        -----END EC PARAMETERS-----
        """)
    }
}
