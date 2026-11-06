import SwiftUI
import MapKit

/// The same saved-location map is used by server and native Google details.
struct TrackerDetailMap: View {
    let tracker: Tracker
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            if tracker.validLocation != nil {
                TrackerLocationMapCanvas(tracker: tracker, interactive: false)
                    .frame(height: 240)
                    .overlay(alignment: .topTrailing) {
                        RJMapControlStack {
                            RJMapControlButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Trackerkarte vergrößern") { expanded = true }
                                .accessibilityIdentifier("tracker-detail-map-expand")
                        }.padding(12)
                    }
                locationCaption.padding(12)
            } else {
                ContentUnavailableView("Noch kein Standort", systemImage: "mappin.slash.circle",
                    description: Text("Sobald eine gültige Ortung vorliegt, erscheint dein Tracker hier auf der Karte."))
                    .frame(minHeight: 160)
                    .accessibilityIdentifier("tracker-detail-map-empty")
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tracker-detail-map-card")
        .fullScreenCover(isPresented: $expanded) {
            NavigationStack {
                TrackerLocationMapCanvas(tracker: tracker, interactive: true)
                    .safeAreaInset(edge: .bottom) { locationCaption.padding(16).background(.regularMaterial) }
                    .navigationTitle(tracker.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fertig") { expanded = false }
                                .accessibilityIdentifier("tracker-detail-map-close")
                        }
                    }
            }
        }
    }

    private var locationCaption: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { savedLocationLabel; Spacer(minLength: 0); accuracy }
            VStack(alignment: .leading, spacing: 8) { savedLocationLabel; accuracy }
        }
        .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var savedLocationLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Zuletzt gemeldeter Standort", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            FreshnessLabel(timestamp: tracker.reportTimestamp > 0 ? tracker.reportTimestamp : nil)
        }
    }

    @ViewBuilder private var accuracy: some View {
        if let value = tracker.validLocation?.accuracyM, value.isFinite, value > 0 {
            AccuracyPill(accuracy: value)
        }
    }
}

private struct TrackerLocationMapCanvas: View {
    let tracker: Tracker
    let interactive: Bool
    @State private var position: MapCameraPosition = .automatic
    @State private var satellite = false

    private var accuracyRadius: Double? {
        guard let value = tracker.validLocation?.accuracyM, value.isFinite, value > 0 else { return nil }
        return min(value, 100_000)
    }
    // New report timestamps alone must not reset the user's zoom or pan.
    private var focusCoordinates: [Double] {
        guard let location = tracker.validLocation else { return [] }
        return [location.latitude, location.longitude, accuracyRadius ?? 0]
    }

    var body: some View {
        Map(position: $position, interactionModes: interactive ? .all : []) {
            if let location = tracker.validLocation {
                if let radius = accuracyRadius {
                    MapCircle(center: location.coordinate, radius: radius)
                        .foregroundStyle(Color.accentColor.opacity(0.12))
                        .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                }
                Annotation("", coordinate: location.coordinate, anchor: .bottom) {
                    TrackerMapBubble(tracker: tracker, selected: true)
                }
            }
        }
        .mapStyle(satellite ? .hybrid(elevation: .flat) : .standard(pointsOfInterest: .excludingAll))
        .accessibilityIdentifier("tracker-location-map")
        .overlay(alignment: .topTrailing) {
            if interactive {
                RJMapControlStack {
                    RJMapControlButton(symbol: "scope", label: "Tracker auf Karte zentrieren", action: focus)
                        .accessibilityIdentifier("tracker-detail-map-center")
                    RJMapControlDivider()
                    RJMapControlButton(symbol: satellite ? "map" : "globe.europe.africa", label: satellite ? "Standardkarte" : "Satellitenkarte") { satellite.toggle() }
                        .accessibilityIdentifier("tracker-detail-map-style")
                }.padding(12)
            }
        }
        .onChange(of: focusCoordinates, initial: true) { _, _ in focus() }
    }

    private func focus() {
        guard let location = tracker.validLocation else { return }
        let zoom = min(40_000, max(650, (accuracyRadius ?? 80) * 6.5))
        position = .region(RJMapCamera.focusedRegion(for: location, zoomMeters: zoom))
    }
}
