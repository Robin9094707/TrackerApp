import SwiftUI
import UIKit
import CoreLocation

// MARK: - Visual language

enum RJDesign {
    static let corner: CGFloat = 30
    static let compactCorner: CGFloat = 20
    static let sheetCorner: CGFloat = 34
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
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rjGlass(in: RoundedRectangle(cornerRadius: RJDesign.corner, style: .continuous))
    }
}

struct ProviderBadge: View {
    let provider: String

    var body: some View {
        Label(provider.rjProviderName, systemImage: provider.rjProviderSymbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(provider.rjProviderColor.opacity(0.12), in: Capsule())
            .foregroundStyle(provider.rjProviderColor)
            .accessibilityLabel("Netzwerk \(provider.rjProviderName)")
    }
}

struct SourceBadge: View {
    let source: String

    var body: some View {
        Label(source.rjProviderName, systemImage: source.rjProviderSymbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(source.rjProviderColor.opacity(0.13), in: Capsule())
            .foregroundStyle(source.rjProviderColor)
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

// MARK: - Apple-like map marker

struct TrackerMapBubble: View {
    let tracker: Tracker
    var selected: Bool = false
    var locating: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: selected ? 22 : 19, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: selected ? 58 : 50, height: selected ? 58 : 50)
                .overlay {
                    RoundedRectangle(cornerRadius: selected ? 22 : 19, style: .continuous)
                        .stroke(.white.opacity(0.34), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)

            DiamondTip()
                .fill(.ultraThinMaterial)
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(45))
                .offset(y: 5)
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)

            Group {
                if locating {
                    ProgressView().controlSize(.small)
                } else {
                    Text(tracker.emoji ?? "📍")
                        .font(selected ? .system(size: 30) : .system(size: 25))
                }
            }
            .frame(width: selected ? 58 : 50, height: selected ? 54 : 46)
            .offset(y: selected ? -3 : -2)
        }
        .frame(width: selected ? 66 : 58, height: selected ? 72 : 64)
        .scaleEffect(selected ? 1.02 : 1)
        .animation(.snappy(duration: 0.25), value: selected)
    }
}

private struct DiamondTip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))
    }
}

// MARK: - Address fallback

@MainActor
final class ReverseGeocoder {
    static let shared = ReverseGeocoder()
    private var cache: [String: String] = [:]
    private var inFlight: [String: Task<String?, Never>] = [:]

    func address(for location: TrackerLocation) async -> String? {
        if let supplied = location.address?.bestText.trimmingCharacters(in: .whitespacesAndNewlines), !supplied.isEmpty {
            return supplied
        }

        let key = String(format: "%.5f,%.5f", location.latitude, location.longitude)
        if let cached = cache[key] { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<String?, Never> { @MainActor in
            let geocoder = CLGeocoder()
            let coordinate = CLLocation(latitude: location.latitude, longitude: location.longitude)
            guard let placemark = try? await geocoder.reverseGeocodeLocation(coordinate, preferredLocale: Locale.current).first else {
                return nil
            }
            return Self.format(placemark)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result, !result.isEmpty { cache[key] = result }
        return result
    }

    private static func format(_ placemark: CLPlacemark) -> String? {
        var parts: [String] = []
        let street = [placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !street.isEmpty { parts.append(street) }

        let city = [placemark.postalCode, placemark.locality ?? placemark.subAdministrativeArea]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !city.isEmpty { parts.append(city) }

        if parts.isEmpty, let name = placemark.name, !name.isEmpty { parts.append(name) }
        if parts.isEmpty, let area = placemark.administrativeArea, !area.isEmpty { parts.append(area) }
        if parts.isEmpty, let country = placemark.country, !country.isEmpty { parts.append(country) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

struct ResolvedAddressText: View {
    let location: TrackerLocation?
    var fallback: String = "Standort wird geladen …"
    @State private var resolved: String?

    private var supplied: String? {
        guard let text = location?.address?.bestText.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    var body: some View {
        Text(supplied ?? resolved ?? fallback)
            .task(id: taskKey) {
                guard supplied == nil, let location else { return }
                resolved = await ReverseGeocoder.shared.address(for: location)
            }
    }

    private var taskKey: String {
        guard let location else { return "none" }
        return String(format: "%.5f-%.5f", location.latitude, location.longitude)
    }
}

extension HistoryPoint {
    var rjTrackerLocation: TrackerLocation {
        TrackerLocation(
            latitude: latitude,
            longitude: longitude,
            accuracyM: accuracyM,
            timestamp: timestamp,
            network: network,
            provider: nil,
            address: address,
            confidence: nil,
            quality: nil
        )
    }
}

// MARK: - Provider/fusion helpers

extension Tracker {
    var latestSourceName: String? {
        if let network = location?.network, !network.isEmpty, network.lowercased() != "fusion" {
            return network.rjNormalizedProvider
        }
        if let provider = location?.provider, !provider.isEmpty, provider.lowercased() != "fusion" {
            return provider.rjNormalizedProvider
        }
        if self.provider.lowercased() != "fusion" { return self.provider.rjNormalizedProvider }
        return nil
    }

    var fusionNetworkNames: [String] {
        (linkedNetworks ?? []).map(\.rjNormalizedProvider)
    }
}

extension String {
    var rjNormalizedProvider: String {
        let lower = lowercased()
        if lower.contains("apple") || lower.contains("findmy") || lower.contains("find my") { return "apple" }
        if lower.contains("google") { return "google" }
        if lower.contains("samsung") || lower.contains("smartthings") { return "samsung" }
        if lower.contains("fusion") { return "fusion" }
        return self
    }

    var rjProviderName: String {
        switch rjNormalizedProvider.lowercased() {
        case "apple": return "Apple"
        case "google": return "Google"
        case "samsung": return "Samsung"
        case "fusion": return "Fusion"
        default: return self.capitalized
        }
    }

    var rjProviderSymbol: String {
        switch rjNormalizedProvider.lowercased() {
        case "apple": return "apple.logo"
        case "google": return "g.circle.fill"
        case "samsung": return "s.circle.fill"
        case "fusion": return "point.3.connected.trianglepath.dotted"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    var rjProviderColor: Color {
        switch rjNormalizedProvider.lowercased() {
        case "apple": return .blue
        case "google": return .green
        case "samsung": return .cyan
        case "fusion": return .purple
        default: return .secondary
        }
    }
}

extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let object) = self { return object }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

// MARK: - Misc

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
            return "Heute um " + formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(self) {
            return "Gestern um " + formatted(date: .omitted, time: .shortened)
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
