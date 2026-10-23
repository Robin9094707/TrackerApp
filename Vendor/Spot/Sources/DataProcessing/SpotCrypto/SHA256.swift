//
//  SHA256.swift
//  Spot
//
//  Created by Leon Böttger on 11.12.24.
//

import CryptoKit
import Foundation

class SHA256 {
    static func hash(data: Data) -> Data {
        Data(CryptoKit.SHA256.hash(data: data))
    }
}
