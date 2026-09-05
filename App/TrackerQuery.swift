import Foundation
import CoreLocation

enum TrackerSort: String, CaseIterable, Identifiable {
    case favorites, name, newest, nearest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .favorites: "Favoriten zuerst"
        case .name: "Name"
        case .newest: "Zuletzt gesehen"
        case .nearest: "Entfernung zu mir"
        }
    }
}

enum TrackerScope: String, CaseIterable, Identifiable {
    case all, favorites, recent, missing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Alle Objekte"
        case .favorites: "Favoriten"
        case .recent: "In den letzten 15 Min."
        case .missing: "Länger nicht gesehen"
        }
    }
}

struct TrackerQuery {
    var text = ""
    var provider = "all"
    var scope: TrackerScope = .all
    var sort: TrackerSort = .favorites
    var group: String?

    func apply(to trackers: [Tracker], now: Date = Date(), origin: CLLocation? = nil) -> [Tracker] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trackers.filter { tracker in
            guard tracker.archived != true, tracker.hidden != true else { return false }
            guard provider == "all" || tracker.provider == provider else { return false }
            if let group, !(tracker.groups ?? []).contains(group) { return false }
            let age = tracker.reportDate.map { now.timeIntervalSince($0) } ?? .infinity
            switch scope {
            case .all: break
            case .favorites: if tracker.favorite != true { return false }
            case .recent: if age < -300 || age > 900 { return false }
            case .missing: if age <= 3600 { return false }
            }
            let terms = [tracker.name, tracker.ref, tracker.details?.note ?? "", tracker.location?.address?.bestText ?? ""] + (tracker.details?.aliases ?? [])
            return query.isEmpty || terms.contains { $0.localizedStandardContains(query) }
        }.sorted { a, b in
            switch sort {
            case .favorites:
                if (a.favorite == true) != (b.favorite == true) { return a.favorite == true }
            case .newest:
                if a.reportTimestamp != b.reportTimestamp { return a.reportTimestamp > b.reportTimestamp }
            case .nearest:
                if let origin {
                    let da = a.distance(from: origin) ?? .infinity
                    let db = b.distance(from: origin) ?? .infinity
                    if da != db { return da < db }
                }
            case .name: break
            }
            let comparison = a.name.localizedStandardCompare(b.name)
            return comparison == .orderedSame ? a.ref < b.ref : comparison == .orderedAscending
        }
    }
}

extension Tracker {
    var apiID: String { serverID ?? String(ref.split(separator: ":", maxSplits: 1).last ?? Substring(ref)) }
    var reportTimestamp: Int { location?.timestamp ?? lastSeenTs ?? 0 }
    var reportDate: Date? { reportTimestamp > 0 ? Date(timeIntervalSince1970: TimeInterval(reportTimestamp)) : nil }
    var validLocation: TrackerLocation? {
        guard let location, CLLocationCoordinate2DIsValid(location.coordinate) else { return nil }
        return location
    }
    func distance(from origin: CLLocation) -> Double? {
        guard let location = validLocation else { return nil }
        return origin.distance(from: CLLocation(latitude: location.latitude, longitude: location.longitude))
    }
    var shareText: String {
        guard let location = validLocation else { return name }
        let date = reportDate?.formatted(date: .abbreviated, time: .shortened) ?? "Zeit unbekannt"
        return "\(name)\n\(location.address?.bestText ?? "Standort")\nStand: \(date)\nhttps://maps.apple.com/?ll=\(location.latitude),\(location.longitude)"
    }
}
