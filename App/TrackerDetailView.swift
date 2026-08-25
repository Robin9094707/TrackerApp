import SwiftUI
import MapKit

struct TrackerDetailView: View {
    @Environment(AppModel.self) private var model
    let tracker: Tracker
    @State private var showRecoveryConfirm = false
    @State private var working = false
    @State private var mapPosition: MapCameraPosition = .automatic

    private var current: Tracker { model.trackers.first(where: { $0.ref == tracker.ref }) ?? tracker }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let location = current.location { heroMap(location) }
                detailSheet
                    .offset(y: current.location == nil ? 0 : -30)
                    .padding(.bottom, current.location == nil ? 20 : -10)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshable { await model.refresh() }
        .task { focusCurrent() }
        .onChange(of: current.location) { _, _ in focusCurrent() }
    }

    private func heroMap(_ location: TrackerLocation) -> some View {
        Map(position: $mapPosition) {
            if let accuracy = location.accuracyM, accuracy > 0 {
                MapCircle(center: location.coordinate, radius: max(accuracy, 3))
                    .foregroundStyle(Color.accentColor.opacity(0.13))
                    .stroke(Color.accentColor.opacity(0.55), lineWidth: 1.5)
            }
            Annotation(current.name, coordinate: location.coordinate) {
                ZStack {
                    Circle().fill(.background).frame(width: 54, height: 54).shadow(radius: 7)
                    if model.isLocating(current) { ProgressView() }
                    else { Text(current.emoji ?? "📍").font(.title2) }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls { MapCompass(); MapScaleView() }
        .frame(height: 430)
        .overlay(alignment: .bottomTrailing) {
            AccuracyPill(accuracy: location.accuracyM)
                .padding(.trailing, 16)
                .padding(.bottom, 48)
        }
    }

    private var detailSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 42, height: 5).frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(current.name).font(.largeTitle.bold())
                    Spacer()
                    ProviderBadge(provider: current.provider)
                }
                if let location = current.location {
                    Text(location.address?.bestText.isEmpty == false ? location.address!.bestText : "\(location.latitude), \(location.longitude)")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                    HStack(spacing: 7) {
                        FreshnessLabel(timestamp: location.timestamp ?? current.lastSeenTs)
                        Text("•").foregroundStyle(.secondary)
                        AccuracyPill(accuracy: location.accuracyM)
                    }
                } else {
                    Text("Noch kein Standort verfügbar").foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button { Task { await model.locate(current) } } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle().fill(Color.accentColor.opacity(0.13)).frame(width: 52, height: 52)
                            if model.isLocating(current) { ProgressView() }
                            else { Image(systemName: "location.fill").font(.title2).foregroundStyle(.tint) }
                        }
                        Text(model.isLocating(current) ? "Ortung läuft …" : "Jetzt orten")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(model.isLocating(current))

                NavigationLink { HistoryView(tracker: current) } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle().fill(.secondary.opacity(0.12)).frame(width: 52, height: 52)
                            Image(systemName: "clock.arrow.circlepath").font(.title2)
                        }
                        Text("Verlauf").font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)

            if let location = current.location {
                Button {
                    openMaps(location)
                } label: {
                    Label("Route in Apple Karten", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Tracker").font(.headline)
                LabeledContent("Netzwerk", value: current.provider.capitalized)
                LabeledContent("Batterie", value: current.battery ?? "Unbekannt")
                LabeledContent("Verlauf", value: current.historyActive == true ? "Aktiv" : "Aus")
                if let networks = current.linkedNetworks, !networks.isEmpty {
                    LabeledContent("Fusion", value: networks.joined(separator: " + "))
                }
            }
            .padding(16)
            .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text("Benachrichtigungen").font(.headline)
                Button { Task { await toggleFound() } } label: {
                    Label(
                        current.foundNotification?.enabled == true ? "Fundmeldung deaktivieren" : "Bei Fund melden",
                        systemImage: current.foundNotification?.enabled == true ? "bell.slash" : "bell.and.waves.left.and.right"
                    )
                }
                .buttonStyle(.bordered)

                if ["apple", "fusion"].contains(current.provider) {
                    Button(role: .destructive) { showRecoveryConfirm = true } label: {
                        Label("Recovery Guard aktivieren", systemImage: "lifepreserver.fill")
                    }
                    .buttonStyle(.bordered)
                    .confirmationDialog("Recovery Guard starten?", isPresented: $showRecoveryConfirm, titleVisibility: .visible) {
                        Button("Aktivieren", role: .destructive) { Task { await startRecovery() } }
                        Button("Abbrechen", role: .cancel) { }
                    } message: {
                        Text("Der Server beginnt einen Recovery-Fall für diesen Tracker. Das ist kein offizieller Apple-Lost-Mode.")
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rjGlass(in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .padding(.horizontal, 10)
    }

    private func focusCurrent() {
        guard let location = current.location else { return }
        let accuracy = max(location.accuracyM ?? 80, 80)
        mapPosition = .region(MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: max(900, accuracy * 7),
            longitudinalMeters: max(900, accuracy * 7)
        ))
    }

    private func toggleFound() async {
        working = true; defer { working = false }
        do {
            _ = try await APIClient.shared.action("set_found_notification", payload: [
                "tracker": current.ref,
                "enabled": current.foundNotification?.enabled != true,
                "mode": "once"
            ])
            await model.refresh(); Haptics.success()
        } catch { model.errorMessage = error.localizedDescription }
    }

    private func startRecovery() async {
        do {
            _ = try await APIClient.shared.action("start_recovery", payload: ["tracker": current.ref, "confirmed": true])
            await model.refresh(); Haptics.success()
        } catch { model.errorMessage = error.localizedDescription }
    }

    private func openMaps(_ location: TrackerLocation) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        item.name = current.name
        item.openInMaps()
    }
}
