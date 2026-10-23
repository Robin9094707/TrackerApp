//
//  TruncatedEID.swift
//  Spot
//
//  Created by Leon Böttger on 22.12.24.
//

import Foundation

extension TruncatedEID {
    static func fromEID(_ eid: Data) -> Data {
        eid.subdata(in: 0 ..< 10)
    }
}
