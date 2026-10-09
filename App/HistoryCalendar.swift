import Foundation

struct HistoryCalendarResponse: Decodable {
    let timezone: String
    let today: String
    let days: [StoredHistoryDay]
}

struct StoredHistoryDay: Decodable, Identifiable {
    let date: String
    let count: Int
    let networks: [String]
    var id: String { date }
}

enum HistoryCalendar {
    static func calendar(timezone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        return calendar
    }
    static func key(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }
    static func date(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
    static func range(days: Int, now: Date, calendar: Calendar) -> Set<String> {
        Set((0..<max(1, days)).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: now).map { key($0, calendar: calendar) }
        })
    }
}
