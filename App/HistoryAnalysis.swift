import Foundation
import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

struct HistorySegment: Identifiable {
    let id: Int
    let points: [HistoryPoint]
}

enum HistoryAnalysis {
    static func filtered(_ points: [HistoryPoint], networks: Set<String>) -> [HistoryPoint] {
        var seen: Set<String> = []
        return points.filter {
            CLLocationCoordinate2DIsValid($0.coordinate) && $0.timestamp > 0 &&
            networks.contains(($0.network ?? "unknown").rjNormalizedProvider) && seen.insert($0.id).inserted
        }.sorted { $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp }
    }

    /// Report gaps and implausible jumps remain gaps, rather than becoming a supposed travelled route.
    static func segments(_ points: [HistoryPoint]) -> [HistorySegment] {
        var groups: [[HistoryPoint]] = []
        for point in points {
            if let last = groups.last?.last {
                let seconds = point.timestamp - last.timestamp
                let distance = CLLocation(latitude: last.latitude, longitude: last.longitude)
                    .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
                if seconds > 1800 || seconds <= 0 || distance / Double(max(seconds, 1)) > 90 {
                    groups.append([point])
                } else { groups[groups.count - 1].append(point) }
            } else { groups.append([point]) }
        }
        return groups.enumerated().map { HistorySegment(id: $0.offset, points: $0.element) }
    }

    static func csv(_ points: [HistoryPoint]) -> String {
        func cell(_ value: String) -> String {
            // A shared address must never become a spreadsheet formula when opened in Excel.
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: { value.hasPrefix($0) }) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let formatter = ISO8601DateFormatter()
        let rows = points.map { point in
            [formatter.string(from: Date(timeIntervalSince1970: TimeInterval(point.timestamp))), String(point.latitude), String(point.longitude), point.accuracyM.map(String.init(describing:)) ?? "", point.network ?? "", point.address?.bestText ?? ""].map(cell).joined(separator: ",")
        }
        return (["time_utc,latitude,longitude,accuracy_m,network,address"] + rows).joined(separator: "\r\n")
    }

    static func gpx(_ points: [HistoryPoint]) -> String {
        let formatter = ISO8601DateFormatter()
        let segments = segments(points).map { segment in
            "<trkseg>" + segment.points.map { point in
                "<trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"><time>\(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(point.timestamp))))</time></trkpt>"
            }.joined() + "</trkseg>"
        }.joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\" creator=\"RJ Tracker\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk>\(segments)</trk></gpx>"
    }
}

struct HistoryExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .xml] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
