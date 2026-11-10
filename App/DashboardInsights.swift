import SwiftUI

// MARK: - 8.1 Smart dashboard

/// A short, actionable observation about one tracker, derived on device from
/// the data the server already delivers. Nothing is invented: every insight
/// states exactly which stored value caused it.
struct TrackerInsight: Identifiable, Hashable {
    enum Kind: String { case battery, stale, noLocation }
    let kind: Kind
    let ref: String
    let title: String
    let detail: String
    var id: String { kind.rawValue + "|" + ref }

    var symbol: String {
        switch kind {
        case .battery: "battery.25percent"
        case .stale: "clock.badge.exclamationmark"
        case .noLocation: "location.slash"
        }
    }

    var tint: Color {
        switch kind {
        case .battery: .red
        case .stale: .orange
        case .noLocation: .gray
        }
    }
}

enum DashboardInsights {
    /// Reports younger than this count as "aktuell" in the status ring.
    static let freshSeconds = 2 * 3600
    /// Reports older than this are worth a hint.
    static let staleSeconds = 12 * 3600

    static func greeting(hour: Int) -> String {
        switch hour {
        case 5..<11: "Guten Morgen"
        case 11..<18: "Guten Tag"
        case 18..<23: "Guten Abend"
        default: "Gute Nacht"
        }
    }

    static func batteryPercent(_ text: String?) -> Int? {
        guard let text, let range = text.range(of: #"\d{1,3}(?=\s*%)"#, options: .regularExpression) else { return nil }
        return Int(text[range]).flatMap { (0...100).contains($0) ? $0 : nil }
    }

    static func batteryIsLow(_ text: String?) -> Bool {
        if let percent = batteryPercent(text) { return percent <= 20 }
        let lowered = (text ?? "").lowercased()
        return ["niedrig", "kritisch", "schwach", "low", "critical"].contains { lowered.contains($0) }
    }

    static func freshCount(_ trackers: [Tracker], now: Int) -> Int {
        trackers.filter { $0.reportTimestamp > 0 && now - $0.reportTimestamp <= freshSeconds }.count
    }

    static func ageText(seconds: Int) -> String {
        let hours = max(1, seconds / 3600)
        if hours < 48 { return "seit \(hours) Std." }
        return "seit \(hours / 24) Tagen"
    }

    static func insights(for trackers: [Tracker], now: Int, limit: Int = 4) -> [TrackerInsight] {
        var battery: [TrackerInsight] = []
        var stale: [(age: Int, insight: TrackerInsight)] = []
        var missing: [TrackerInsight] = []
        for tracker in trackers where tracker.archived != true && tracker.hidden != true {
            if batteryIsLow(tracker.battery) {
                battery.append(TrackerInsight(kind: .battery, ref: tracker.ref, title: tracker.name,
                                              detail: "Batterie schwach (\(tracker.battery ?? "niedrig"))"))
            }
            if tracker.reportTimestamp <= 0 {
                missing.append(TrackerInsight(kind: .noLocation, ref: tracker.ref, title: tracker.name,
                                              detail: "Noch kein Standort gemeldet"))
            } else if now - tracker.reportTimestamp > staleSeconds {
                let age = now - tracker.reportTimestamp
                stale.append((age, TrackerInsight(kind: .stale, ref: tracker.ref, title: tracker.name,
                                                  detail: "Keine neue Meldung \(ageText(seconds: age))")))
            }
        }
        let ordered = battery + stale.sorted { $0.age > $1.age }.map(\.insight) + missing
        return Array(ordered.prefix(limit))
    }
}

/// Greeting, one-line summary and a ring showing how many objects reported recently.
struct DashboardHero: View {
    let trackers: [Tracker]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = Int(context.date.timeIntervalSince1970)
            let total = trackers.count
            let fresh = DashboardInsights.freshCount(trackers, now: now)
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(DashboardInsights.greeting(hour: Calendar.current.component(.hour, from: context.date)).uppercased())
                        .font(.caption.weight(.bold)).tracking(1.8).foregroundStyle(RJBrand.gradient)
                    Text("Alles im Blick.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(summary(total: total, fresh: fresh))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if total > 0 { ring(total: total, fresh: fresh) }
            }
        }
    }

    private func summary(total: Int, fresh: Int) -> String {
        if total == 0 { return "Noch keine Objekte verbunden" }
        if fresh == total { return total == 1 ? "Dein Objekt ist aktuell" : "Alle \(total) Objekte sind aktuell" }
        return "\(fresh) von \(total) aktuell · \(total - fresh) älter als 2 Std."
    }

    private func ring(total: Int, fresh: Int) -> some View {
        let fraction = total > 0 ? Double(fresh) / Double(total) : 0
        return ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 8)
            Circle().trim(from: 0, to: max(0.001, fraction))
                .stroke(RJBrand.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.6), value: fraction)
            VStack(spacing: 0) {
                Text("\(fresh)").font(.title2.bold().monospacedDigit()).contentTransition(.numericText())
                Text("von \(total)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 76, height: 76)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(fresh) von \(total) Objekten aktuell")
    }
}

/// Automatic hints: weak batteries, objects without recent reports, objects without any location.
struct DashboardInsightsCard: View {
    let trackers: [Tracker]
    let onSelect: (Tracker) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let rows = DashboardInsights.insights(for: trackers, now: Int(context.date.timeIntervalSince1970))
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(RJBrand.gradient)
                    Text("Hinweise").font(.headline)
                    Spacer()
                    if !rows.isEmpty {
                        Text("\(rows.count)").font(.caption.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange.gradient, in: Capsule())
                    }
                }
                if rows.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Alles in Ordnung").font(.subheadline.weight(.semibold))
                            Text("Keine schwache Batterie, keine überfälligen Meldungen.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    ForEach(rows) { insight in
                        Button {
                            if let tracker = trackers.first(where: { $0.ref == insight.ref }) { onSelect(tracker) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: insight.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(insight.tint.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(insight.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                    Text(insight.detail).font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(RJPressStyle())
                        .accessibilityIdentifier("insight-\(insight.id)")
                    }
                }
            }
        }
    }
}

/// Subtle press feedback for cards and tiles.
struct RJPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
