//
//  TrackerStateResponse.swift
//
//
//  Created by Leon Böttger on 08.12.24.
//

import Foundation
import Combine

func parseTrackerState(data: Data) throws -> TrackerStateResponse {
    guard data.count >= 8 else {
        throw NSError(domain: "Invalid Tracker State Data Length: \(data.count)", code: 0, userInfo: nil)
    }

    let calibratedPowerBytes = data.subdata(in: 0 ..< 1)
    let clockOffsetBytes = data.subdata(in: 1 ..< 5)
    let curveSelectionBytes = data.subdata(in: 5 ..< 6)
    let componentsBytes = data.subdata(in: 6 ..< 7)
    let ringingCapabilitiesBytes = data.subdata(in: 7 ..< 8)

    // interpret calibrated power as signed int
    let calibratedPowerInt = Int(calibratedPowerBytes.withUnsafeBytes { $0.load(as: Int8.self) })

    // interpret clock offset as big endian int
    let clockOffsetInt = try wordToInt(data: clockOffsetBytes)

    let curveSelection = try EllipticCurveSelection.fromBytes(curveSelectionBytes)
    let capableRingingComponents = try CapableRingingComponents.fromBytes(componentsBytes)

    var volumeSelectionAvailable: Bool

    switch ringingCapabilitiesBytes {
    case Data([0x00]):
        volumeSelectionAvailable = false
    case Data([0x01]):
        volumeSelectionAvailable = true
    default:
        throw NSError(domain: "Invalid Volume Selection Availability: \(ringingCapabilitiesBytes.hex)", code: 0, userInfo: nil)
    }

    return TrackerStateResponse(calibratedPower: calibratedPowerInt, clockOffset: clockOffsetInt, ellipticCurveSelection: curveSelection, capableRingingComponents: capableRingingComponents, volumeSelectionAvailable: volumeSelectionAvailable)
}

struct TrackerStateResponse {
    let calibratedPower: Int
    let clockOffset: Int
    let ellipticCurveSelection: EllipticCurveSelection
    let capableRingingComponents: CapableRingingComponents
    let volumeSelectionAvailable: Bool
}

enum CapableRingingComponents: String {
    case None
    case Single
    case LeftAndRight
    case LeftRightAndCase

    static func fromBytes(_ bytes: Data) throws -> CapableRingingComponents {
        if bytes == Data([0x00]) {
            return .None
        }
        if bytes == Data([0x01]) {
            return .Single
        }
        if bytes == Data([0x02]) {
            return .LeftAndRight
        }
        if bytes == Data([0x03]) {
            return .LeftRightAndCase
        }

        throw NSError(domain: "Invalid Capable Ringing Components: \(bytes.hex)", code: 0, userInfo: nil)
    }
}

enum EllipticCurveSelection: String {
    case SECP160R1
    case SECP256R1

    static func fromBytes(_ bytes: Data) throws -> EllipticCurveSelection {
        if bytes == Data([0x00]) {
            return .SECP160R1
        }
        if bytes == Data([0x01]) {
            return .SECP256R1
        }

        throw NSError(domain: "Invalid Elliptic Curve Selection: \(bytes.hex)", code: 0, userInfo: nil)
    }
}
