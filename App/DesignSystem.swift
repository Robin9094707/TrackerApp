import SwiftUI
import UIKit
import CoreLocation
import MapKit

// MARK: - Visual language

enum RJDesign {
    static let corner: CGFloat = 26
    static let compactCorner: CGFloat = 20
    static let sheetCorner: CGFloat = 28
    static let controlSize: CGFloat = 46
    static let contentPadding: CGFloat = 16
}

private struct RJExpandInspectorKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}
extension EnvironmentValues {
    var rjExpandInspector: () -> Void {
        get { self[RJExpandInspectorKey.self] }
        set { self[RJExpandInspectorKey.self] = newValue }
    }
}

struct RJGlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
    }
}

extension View {
    @ViewBuilder
    func rjGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.8))
        }
    }

    func rjCard() -> some View {
        padding(RJDesign.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: RJDesign.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RJDesign.corner, style: .continuous).stroke(Color.primary.opacity(0.045), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
    }

    func rjCompactCard() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: RJDesign.compactCorner, style: .continuous))
    }

    func rjScreenChrome() -> some View {
        background(RJGlassBackdrop())
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    func rjListChrome() -> some View {
        scrollContentBackground(.hidden)
            .background(RJGlassBackdrop())
            .listStyle(.insetGrouped)
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    func rjFormChrome() -> some View {
        scrollContentBackground(.hidden)
            .background(RJGlassBackdrop())
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    func rjGlassControl() -> some View {
        frame(width: RJDesign.controlSize, height: RJDesign.controlSize)
            .modifier(RJInteractiveGlass())
    }
}

private struct RJInteractiveGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(.regularMaterial, in: Circle())
        }
    }
}

struct RJGlassControls<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { content() }
        } else { content() }
    }
}

struct RJPrimaryButtonStyle: ButtonStyle {
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            configuration.label.padding(.horizontal, 16).padding(.vertical, 8)
                .foregroundStyle(.white)
                .glassEffect(.regular.tint(.blue).interactive(), in: Capsule())
                .opacity(configuration.isPressed ? 0.75 : 1)
        } else {
            configuration.label.padding(.horizontal, 16).padding(.vertical, 8)
                .foregroundStyle(.white).background(.blue, in: Capsule())
                .opacity(configuration.isPressed ? 0.75 : 1)
        }
    }
}

struct RJSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 16).padding(.vertical, 8)
            .rjGlass(in: Capsule()).opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct RJLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        ZStack {
            RJGlassBackdrop()
            VStack(spacing: 22) {
                Image(systemName: "airtag.radiowaves.forward.fill")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(.blue.gradient)
                    .frame(width: 120, height: 120)
                    .rjGlass(in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.88)
                VStack(spacing: 8) {
                    Text("RJ Tracker").font(.largeTitle.bold())
                    Text("Deine Dinge. Immer im Blick.").font(.subheadline).foregroundStyle(.secondary)
                }
                ProgressView("Verbinden …").font(.caption).padding(.top, 8)
            }.opacity(appeared || reduceMotion ? 1 : 0)
        }.onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.15)) { appeared = true }
        }
    }
}

struct RJSectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

struct RJStatusPill: View {
    let text: String
    let symbol: String
    var tint: Color = .blue

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
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
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let date = Date.fromUnix(timestamp) {
                Text(TrackerTimeText.age(of: date, now: context.date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(date.rjTrackerFreshnessColor)
            } else {
                Text("Kein Standort").font(.caption).foregroundStyle(.secondary)
            }
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

// MARK: - Map framing

enum RJMapCamera {
    static func overview(locations: [TrackerLocation], panelCoverage: CGFloat) -> MKCoordinateRegion? {
        guard let first = locations.first else { return nil }
        // Unwrap longitude around the first object so the date line does not create a world-wide span.
        let longitudes = locations.map { first.longitude + ($0.longitude - first.longitude + 540).truncatingRemainder(dividingBy: 360) - 180 }
        let latitudes = locations.map(\.latitude)
        let middleLat = (latitudes.min()! + latitudes.max()!) / 2
        let middleLon = (longitudes.min()! + longitudes.max()!) / 2
        let coverage = min(max(Double(panelCoverage), 0), 0.8)
        let latitudeDelta = min(160, max(0.012, (latitudes.max()! - latitudes.min()!) * 1.5) / (1 - coverage))
        let longitudeDelta = min(350, max(0.018, (longitudes.max()! - longitudes.min()!) * 1.6))
        return MKCoordinateRegion(center: .init(latitude: max(-80, min(80, middleLat - latitudeDelta * coverage / 2)), longitude: (middleLon + 540).truncatingRemainder(dividingBy: 360) - 180), span: .init(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }

    /// Keeps the selected pin above a bottom sheet instead of geometrically centering it behind the sheet.
    static func focusedRegion(
        for location: TrackerLocation,
        zoomMeters: Double? = nil,
        panelCoverage: CGFloat = 0.0
    ) -> MKCoordinateRegion {
        let accuracy = max(location.accuracyM ?? 80, 70)
        let spanMeters = max(zoomMeters ?? (accuracy * 6.5), 650)
        let coverage = min(max(Double(panelCoverage), 0), 0.90)
        let upwardScreenShift = min(0.34, coverage * 0.43)
        let latitudeOffset = (spanMeters * upwardScreenShift) / 111_320.0
        let center = CLLocationCoordinate2D(
            latitude: location.latitude - latitudeOffset,
            longitude: location.longitude
        )
        return MKCoordinateRegion(
            center: center,
            latitudinalMeters: spanMeters,
            longitudinalMeters: spanMeters
        )
    }
}

// MARK: - Apple-like map marker

/// Find My style item pin: a white disc with the item symbol and a short tail.
struct TrackerMapBubble: View {
    let tracker: Tracker
    var selected: Bool = false
    var locating: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var size: CGFloat { selected ? 64 : 48 }
    private var disc: Color { colorScheme == .dark ? Color(uiColor: .systemGray5) : .white }

    var body: some View {
        VStack(spacing: -3) {
            ZStack(alignment: .topTrailing) {
                Text(tracker.emoji ?? "📍")
                    .font(.system(size: selected ? 34 : 25))
                    .frame(width: size - 8, height: size - 8)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                    .padding(4)
                    .background(disc, in: Circle())
                    .overlay(Circle().stroke(selected ? Color.accentColor : Color.black.opacity(0.06), lineWidth: selected ? 3 : 0.5))
                if locating {
                    ProgressView().controlSize(.mini).padding(4)
                        .background(.regularMaterial, in: Circle())
                        .offset(x: 4, y: -4)
                } else if tracker.favorite == true {
                    Image(systemName: "star.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 18, height: 18).background(Color.orange, in: Circle())
                        .overlay(Circle().stroke(disc, lineWidth: 2))
                        .offset(x: 3, y: -3)
                }
            }
            RJPinTail().fill(selected ? Color.accentColor : disc)
                .frame(width: 14, height: 9)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(selected ? 0.28 : 0.2), radius: selected ? 10 : 5, y: selected ? 5 : 3)
        .scaleEffect(selected ? 1 : 0.98, anchor: .bottom)
        .animation(.spring(duration: 0.35, bounce: 0.3), value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tracker.name)
    }
}

struct RJPinTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.midX - rect.width * 0.12, y: rect.minY + rect.height * 0.35))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX + rect.width * 0.12, y: rect.minY + rect.height * 0.35))
        path.closeSubpath()
        return path
    }
}

/// Apple Maps style control column: several buttons share one glass capsule.
struct RJMapControlStack<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        let stack = VStack(spacing: 0) { content() }
            .font(.system(size: 19, weight: .medium))
            .buttonStyle(.plain)
        if reduceTransparency {
            stack.background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        } else if #available(iOS 26.0, *) {
            stack.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            stack.background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }
}

struct RJMapControlButton: View {
    let symbol: String
    var active = false
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(active ? Color.accentColor : .primary)
                .frame(width: RJDesign.controlSize, height: RJDesign.controlSize)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(label)
    }
}

struct RJMapControlDivider: View {
    var body: some View { Divider().frame(width: 26) }
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
        if let result, !result.isEmpty {
            if cache.count >= 500 { cache.removeAll(keepingCapacity: true) }
            cache[key] = result
        }
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
                resolved = nil
                guard supplied == nil, let location else { return }
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                guard !Task.isCancelled else { return }
                let value = await ReverseGeocoder.shared.address(for: location)
                guard !Task.isCancelled else { return }
                resolved = value
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
        TrackerTimeText.age(of: self)
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

/// Large, left-aligned action surface in the Find My item-sheet style.
struct TrackerActionTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    var color: Color = .blue
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color.gradient, in: Circle())
                .symbolEffect(.bounce, value: title)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.primary.opacity(0.05), lineWidth: 0.5))
        .opacity(isEnabled ? 1 : 0.5)
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }
}

/// Settings-style row with a colored rounded-square icon, as in Find My's item sheet.
struct RJSettingsRow: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    var color: Color = .blue
    var chevron = true
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(.primary)
                if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Inset grouped container used by the redesigned detail sheets.
struct RJGroupedSection<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.title3.weight(.semibold)).padding(.horizontal, 4)
            }
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 14)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            if let footer {
                Text(footer).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 6)
            }
        }
    }
}


/// Shared location summary: the tracker name appears once, in the navigation bar.
struct TrackerLocationSummary: View {
    let symbol: String
    let provider: String
    let location: TrackerLocation?
    let timestamp: Int?
    var nearby = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(symbol).font(.system(size: 30))
                .frame(width: 56, height: 56)
                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                .overlay(Circle().stroke(provider.rjProviderColor.opacity(0.35), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 5) {
                if nearby { Text("Bei dir").font(.subheadline.weight(.semibold)).foregroundStyle(.green) }
                ResolvedAddressText(location: location, fallback: "Noch kein Standort gemeldet")
                    .font(.title3.weight(.semibold)).lineLimit(2)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { FreshnessLabel(timestamp: timestamp); SourceBadge(source: provider) }
                    VStack(alignment: .leading, spacing: 4) { FreshnessLabel(timestamp: timestamp); SourceBadge(source: provider) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tracker-detail-header")
    }
}
