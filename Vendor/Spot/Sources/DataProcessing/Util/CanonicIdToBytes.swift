//
//  CanonicIdToBytes.swift
//  Spot
//
//  Created by Leon Böttger on 16.12.24.
//

import Foundation
import SwiftUI

class CanonicIdToBytes {
    static func convert(_ id: String) -> Data {
        id.filter { $0 != "-" }.lowercased().dataFromHex
    }
}
