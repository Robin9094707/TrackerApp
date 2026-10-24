import Foundation

// Google MCS is a byte stream: one report can span several reads and several reports
// can share one read. Retain incomplete frames and deliver every complete frame in order.
struct GoogleMCSDecoder {
    struct Frame { let tag: UInt8; let payload: Data }
    private var data = Data()
    private var first = true
    mutating func append(_ bytes: Data) throws -> [Frame] {
        data.append(bytes)
        var frames: [Frame] = []
        while !data.isEmpty {
            var cursor = first ? 1 : 0
            if first {
                guard data.count >= 2 else { break }
                guard [UInt8(38), UInt8(41)].contains(data[0]) else { throw googleError("Unbekannte Google-Push-Version.") }
            }
            let tag = data[cursor]; cursor += 1
            var length = 0, shift = 0, complete = false
            while cursor < data.count {
                let byte = data[cursor]; cursor += 1
                length |= Int(byte & 0x7f) << shift
                if byte & 0x80 == 0 { complete = true; break }
                shift += 7
                if shift > 28 { throw googleError("Ungültige Google-Push-Nachricht.") }
            }
            guard complete else { break }
            guard length <= 4_194_304 else { throw googleError("Google-Push-Nachricht ist zu groß.") }
            guard data.count - cursor >= length else { break }
            frames.append(Frame(tag: tag, payload: Data(data[cursor..<(cursor + length)])))
            data = Data(data.dropFirst(cursor + length)); first = false
        }
        return frames
    }
}
