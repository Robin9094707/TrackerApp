import Foundation

/// Explicit German formatting also applies when the iPhone uses another language.
enum TrackerTimeText {
    static let locale = Locale(identifier: "de_DE")
    static func age(of date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "Gerade eben" }
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return minutes == 1 ? "vor einer Minute" : "vor \(minutes) Minuten"
        }
        if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return hours == 1 ? "vor einer Stunde" : "vor \(hours) Stunden"
        }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now)!) {
            return "Gestern um " + date.formatted(.dateTime.locale(locale).hour().minute())
        }
        return date.formatted(.dateTime.locale(locale).day().month().year().hour().minute())
    }
    static func battery(_ value: String) -> String {
        switch value.lowercased() {
        case "normal": return "Normal"
        case "low": return "Niedrig"
        case "critical": return "Kritisch"
        case "unknown": return "Unbekannt"
        default: return value
        }
    }
}
