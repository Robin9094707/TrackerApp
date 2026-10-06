import Foundation
import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

struct HistorySegment: Identifiable {
    let id: Int
    let points: [HistoryPoint]
    let coordinates: [CLLocationCoordinate2D]
    init(id: Int, points: [HistoryPoint]) {
        self.id = id; self.points = points; self.coordinates = points.map(\.coordinate)
    }
}

struct HistoryDay: Identifiable {
    let date: Date
    let points: [HistoryPoint]
    var id: Date { date }
}

struct PreparedHistory {
    var points: [HistoryPoint] = []
    var mapSegments: [HistorySegment] = []
    var mapPoints: [HistoryPoint] = []
    var days: [HistoryDay] = []
    var indexByID: [String: Int] = [:]
    var availableDays: [HistoryDay] = []
    var medianAccuracy: Double?
    var longestGap: TimeInterval = 0
    var sourceCounts: [String: Int] = [:]
}

enum HistoryAnalysis {
    /// Expensive sorting and map preparation happen once per response/filter change.
    static func prepare(_ input: [HistoryPoint], networks: Set<String>, calendar: Calendar = .current, day: Date? = nil) -> PreparedHistory {
        let allPoints = filtered(input, networks: networks)
        let allGroups = Dictionary(grouping: allPoints) { calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.timestamp))) }
        let available = allGroups.keys.sorted(by: >).map { HistoryDay(date: $0, points: Array((allGroups[$0] ?? []).reversed())) }
        let points = day.flatMap { allGroups[$0] } ?? allPoints
        let groups = Dictionary(grouping: points) { calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.timestamp))) }
        let days = groups.keys.sorted(by: >).map { HistoryDay(date: $0, points: Array((groups[$0] ?? []).reversed())) }
        let mapSegments = sourceSegments(points).map { segment in
            HistorySegment(id: segment.id, points: simplified(segment.points))
        }
        let accuracies = points.compactMap(\.accuracyM).filter { $0.isFinite && $0 > 0 }.sorted()
        let middle = accuracies.count / 2
        let median: Double? = accuracies.isEmpty ? nil : (accuracies.count.isMultiple(of: 2) ? (accuracies[middle - 1] + accuracies[middle]) / 2 : accuracies[middle])
        let gap = zip(points, points.dropFirst()).map { TimeInterval($1.timestamp - $0.timestamp) }.max() ?? 0
        let counts = Dictionary(grouping: points) { ($0.network ?? "unknown").rjNormalizedProvider }.mapValues(\.count)
        return PreparedHistory(points: points, mapSegments: mapSegments, mapPoints: sampled(points, limit: 80), days: days,
                               indexByID: Dictionary(uniqueKeysWithValues: points.enumerated().map { ($0.element.id, $0.offset) }),
                               availableDays: available, medianAccuracy: median, longestGap: gap, sourceCounts: counts)
    }

    /// Preserve real turns and endpoints; rendering never modifies stored reports or exports.
    static func simplified(_ points: [HistoryPoint], toleranceM: Double = 12) -> [HistoryPoint] {
        guard points.count > 2 else { return points }
        let origin = points[0]
        let cosine = cos(origin.latitude * .pi / 180)
        let xy = points.map { point -> (Double, Double) in
            let lon = (point.longitude - origin.longitude + 540).truncatingRemainder(dividingBy: 360) - 180
            return (lon * 111_320 * cosine, (point.latitude - origin.latitude) * 111_320)
        }
        var keep: Set<Int> = [0, points.count - 1]
        var stack = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            let (ax, ay) = xy[start]; let (bx, by) = xy[end]
            let dx = bx - ax; let dy = by - ay; let squared = dx * dx + dy * dy
            var maximum = toleranceM * toleranceM; var index: Int?
            for i in (start + 1)..<end {
                let (x, y) = xy[i]
                let t = squared > 0 ? min(1, max(0, ((x - ax) * dx + (y - ay) * dy) / squared)) : 0
                let ex = x - ax - t * dx; let ey = y - ay - t * dy
                let distance = ex * ex + ey * ey
                if distance > maximum { maximum = distance; index = i }
            }
            if let index { keep.insert(index); stack.append((start, index)); stack.append((index, end)) }
        }
        return keep.sorted().map { points[$0] }
    }

    static func sampled(_ points: [HistoryPoint], limit: Int) -> [HistoryPoint] {
        guard limit > 1 else { return Array(points.prefix(max(0, limit))) }
        guard points.count > limit else { return points }
        return (0..<limit).map { points[Int((Double($0) * Double(points.count - 1) / Double(limit - 1)).rounded())] }
    }

    /// Time-based scrubbing uses binary search rather than scanning every report on each frame.
    static func nearestIndex(to timestamp: Double, in points: [HistoryPoint]) -> Int {
        guard !points.isEmpty else { return 0 }
        var low = 0; var high = points.count
        while low < high {
            let middle = (low + high) / 2
            if Double(points[middle].timestamp) < timestamp { low = middle + 1 } else { high = middle }
        }
        if low == 0 { return 0 }
        if low == points.count { return points.count - 1 }
        return timestamp - Double(points[low - 1].timestamp) <= Double(points[low].timestamp) - timestamp ? low - 1 : low
    }
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

    /// Each network is its own observation stream; never invent travel between providers.
    static func sourceSegments(_ points: [HistoryPoint]) -> [HistorySegment] {
        let grouped = Dictionary(grouping: points) { ($0.network ?? "unknown").rjNormalizedProvider }
        return grouped.keys.sorted().flatMap { segments(grouped[$0] ?? []) }.enumerated().map { HistorySegment(id: $0.offset, points: $0.element.points) }
    }

    static func csv(_ points: [HistoryPoint]) -> String {
        func cell(_ value: String, protectFormula: Bool) -> String {
            // A shared address must never become a spreadsheet formula when opened in Excel.
            let safe = protectFormula && ["=", "+", "-", "@", "\t", "\r"].contains(where: { value.hasPrefix($0) }) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let formatter = ISO8601DateFormatter()
        let rows = points.map { point in
            [formatter.string(from: Date(timeIntervalSince1970: TimeInterval(point.timestamp))), String(point.latitude), String(point.longitude), point.accuracyM.map(String.init(describing:)) ?? "", point.network ?? "", point.address?.bestText ?? ""].enumerated().map { cell($0.element, protectFormula: $0.offset >= 4) }.joined(separator: ",")
        }
        return (["time_utc,latitude,longitude,accuracy_m,network,address"] + rows).joined(separator: "\r\n")
    }

    static func gpx(_ points: [HistoryPoint]) -> String {
        let formatter = ISO8601DateFormatter()
        let segments = sourceSegments(points).map { segment in
            "<trkseg>" + segment.points.map { point in
                "<trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"><time>\(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(point.timestamp))))</time></trkpt>"
            }.joined() + "</trkseg>"
        }.joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\" creator=\"RJ Tracker\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk>\(segments)</trk></gpx>"
    }
}

extension UTType {
    static let rjGPX = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)
}

struct HistoryExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .rjGPX] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

