//
//  CurveType.swift
//  Spot
//
//  Created by Leon Böttger on 26.01.25.
//

import Foundation
import SwiftECC

enum CurveType: CaseIterable {
    case secp160r1
    case secp256r1

    var curve: Domain {
        switch self {
        case .secp160r1:
            SECP160r1.domain
        case .secp256r1:
            Domain.instance(curve: .EC256r1)
        }
    }

    var length: Int {
        switch self {
        case .secp160r1:
            20
        case .secp256r1:
            32
        }
    }

    static func fromEID(_ eid: Data) throws -> CurveType {
        for curveType in CurveType.allCases {
            if eid.count == curveType.length {
                return curveType
            }
        }

        throw NSError(domain: "CurveType", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid EID length"])
    }
}
