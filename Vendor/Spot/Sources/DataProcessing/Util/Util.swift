//
//  Util.swift
//  Spot
//
//  Created by Leon Böttger on 05.12.24.
//

import Foundation

extension String {
    var dataFromHex: Data {
        var data = Data()
        var hex = self
        while hex.count > 0 {
            let c = String(hex.prefix(2))
            hex = String(hex.dropFirst(2))
            var ch: UInt64 = 0
            Scanner(string: c).scanHexInt64(&ch)
            var char = UInt8(ch)
            data.append(&char, count: 1)
        }
        return data
    }
}

func int32ToData(_ value: Int32) -> Data {
    // Convert Int32 to a 4-byte array in big-endian order
    var bigEndianValue = value.bigEndian
    return Data(bytes: &bigEndianValue, count: MemoryLayout<Int32>.size)
}

/// Extension to simplify Data-to-Bytes conversion
extension Data {
    var bytes: [UInt8] {
        [UInt8](self)
    }

    func bitFlipped(enabled: Bool) -> Data {
        if enabled {
            return Data(map { ~$0 })
        }
        return self
    }
}

func getRandomUUID() -> String {
    UUID().uuidString.uppercased()
}

func intToHex(_ number: Int) -> String {
    String(number, radix: 16) // Convert to base 16 (hexadecimal)
}

extension Data {
    var hex: String {
        map { String(format: "%02hhx", $0) }.joined()
    }
}

func base64UrlToData(base64UrlString: String) -> Data? {
    // Replace Base64URL characters with Base64 characters
    var base64String = base64UrlString
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")

    // Add padding if necessary
    let paddingLength = base64String.count % 4
    if paddingLength > 0 {
        base64String.append(String(repeating: "=", count: 4 - paddingLength))
    }

    // Decode the Base64 string into Data
    return Data(base64Encoded: base64String)
}

func dataToBase64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "") // Remove padding
}

func wordToInt(data: Data) throws -> Int {
    if data.count != 4 {
        throw NSError(domain: "Invalid data length: \(data.count)", code: 0, userInfo: nil)
    }

    let uintValue: UInt32 = data.withUnsafeBytes { $0.load(as: UInt32.self) }
    return Int(UInt32(bigEndian: uintValue))
}

func pastTime(date: Date) -> Date {
    let current = Date()
    return date > current ? current : date
}

func timeToRelativeTime(date: Date, currentDate: Date) -> String {
    if abs(date.timeIntervalSince1970 - currentDate.timeIntervalSince1970) < 5 {
        return "Now"
    }

    return dateToRelativeString(date, currentDate: currentDate)
}

func dateToString(_ date: Date, withSeconds: Bool = false) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = withSeconds ? .medium : .short
    return formatter.string(from: date)
}

func relativeDateOrStaticString(_ date: Date, currentDate: Date) -> String {
    // If date in last hour, show relative
    if currentDate.timeIntervalSince(date) < 60 * 60 {
        return dateToRelativeString(date, currentDate: currentDate, unitsStyle: .abbreviated)
    }

    return dateToStaticString(date, currentDate: currentDate)
}

func dateToStaticString(_ date: Date, currentDate: Date) -> String {
    // if date is on same day, omit the day
    if Calendar.current.isDate(date, inSameDayAs: currentDate) {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "Today, " + formatter.string(from: date)
    }

    return dateToString(date)
}

func dateToRelativeString(_ date: Date, currentDate: Date, unitsStyle: RelativeDateTimeFormatter.UnitsStyle = .full) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = unitsStyle
    return formatter.localizedString(for: date, relativeTo: currentDate)
}

func unixTimeToDate(unixTime: Int32) -> Date {
    Date(timeIntervalSince1970: TimeInterval(unixTime))
}

func ensureDataLength(_ data: Data, length: Int) -> Data {
    if data.count == length {
        // Data is already the correct length
        return data
    } else if data.count < length {
        // Prepend zeros to the required length
        let padding = Data([UInt8](repeating: 0, count: length - data.count))
        return padding + data
    } else {
        // Truncate data to the required length
        return data.suffix(length)
    }
}
