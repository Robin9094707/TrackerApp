import SwiftUI
import UIKit

enum RJDesign {
    static let corner: CGFloat = 28
    static let compactCorner: CGFloat = 18
}

extension View {
    @ViewBuilder
    func rjGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    func rjCard() -> some View {
        padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .rjGlass(in: RoundedRectangle(cornerRadius: RJDesign.corner, style: .continuous))
    }
}

struct ProviderBadge: View {
    let provider: String
    var body: some View {
        Label(provider.capitalized, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.secondary.opacity(0.12), in: Capsule())
            .accessibilityLabel("Netzwerk \(provider)")
    }

    private var symbol: String {
        switch provider.lowercased() {
        case "apple": "apple.logo"
        case "google": "g.circle.fill"
        case "samsung": "s.circle.fill"
        case "fusion": "point.3.connected.trianglepath.dotted"
        default: "dot.radiowaves.left.and.right"
        }
    }
}

struct FreshnessLabel: View {
    let timestamp: Int?
    var body: some View {
        if let date = Date.fromUnix(timestamp) {
            Text(date.rjTrackerAgeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(date.rjTrackerFreshnessColor)
        } else {
            Text("Kein Standort")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct AccuracyPill: View {
    let accuracy: Double?
    var body: some View {
        if let accuracy, accuracy > 0 {
            Label("±\(accuracy.metersText)", systemImage: "scope")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.secondary.opacity(0.12), in: Capsule())
        }
    }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func impact() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}

extension Date {
    static func fromUnix(_ value: Int?) -> Date? {
        value.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    var rjTrackerAgeText: String {
        let age = max(0, Date().timeIntervalSince(self))
        if age < 45 { return "Jetzt" }
        if age < 3600 {
            let minutes = max(1, Int(age / 60))
            return "vor \(minutes) Min."
        }
        if Calendar.current.isDateInToday(self) {
            return formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(self) {
            return "Gestern, " + formatted(date: .omitted, time: .shortened)
        }
        return formatted(date: .numeric, time: .shortened)
    }

    var rjTrackerFreshnessColor: Color {
        let age = max(0, Date().timeIntervalSince(self))
        if age <= 5 * 60 { return .green }
        if age <= 20 * 60 { return .blue }
        if age < 60 * 60 { return .orange }
        return .red
    }

    var rjTimelineText: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}

extension Double {
    var metersText: String {
        if self >= 1000 { return String(format: "%.1f km", self / 1000) }
        return "\(Int(self.rounded())) m"
    }
}
