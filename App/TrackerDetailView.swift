import SwiftUI
import MapKit

struct TrackerDetailView: View {
    @Environment(AppModel.self) private var model
    let tracker: Tracker
    @State private var showRecoveryConfirm = false
    @State private var working = false

    private var current: Tracker { model.trackers.first(where: { $0.ref == tracker.ref }) ?? tracker }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if let location = current.location { locationCard(location) }
                actions
                statusCard
            }.padding()
        }
        .navigationTitle(current.name).navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text(current.emoji ?? "📍").font(.system(size: 44)).frame(width: 70, height: 70).background(.secondary.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 6) { Text(current.name).font(.title2.bold()); ProviderBadge(provider: current.provider); if let networks = current.linkedNetworks { Text("Fusion: " + networks.joined(separator: " + ")).font(.caption).foregroundStyle(.secondary) } }
            Spacer()
        }.rjCard()
    }

    private func locationCard(_ location: TrackerLocation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Map(initialPosition: .region(MKCoordinateRegion(center: location.coordinate, span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01)))) {
                Marker(current.name, coordinate: location.coordinate)
            }.frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).allowsHitTesting(false)
            Text(location.address?.bestText.isEmpty == false ? location.address!.bestText : "\(location.latitude), \(location.longitude)").font(.headline)
            HStack { Label("±\(Int((location.accuracyM ?? 0).rounded())) m", systemImage: "scope"); Spacer(); if let date = Date.fromUnix(location.timestamp) { Text(date, style: .relative) } }.font(.subheadline).foregroundStyle(.secondary)
            Button("In Apple Karten öffnen", systemImage: "arrow.triangle.turn.up.right.diamond.fill") { openMaps(location) }.buttonStyle(.bordered)
        }.rjCard()
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aktionen").font(.headline)
            HStack {
                Button { Task { await model.locate(current) } } label: { Label("Jetzt orten", systemImage: "location.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                NavigationLink { HistoryView(tracker: current) } label: { Label("Verlauf", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
            }
            Button { Task { await toggleFound() } } label: { Label(current.foundNotification?.enabled == true ? "Fundmeldung deaktivieren" : "Bei Fund melden", systemImage: current.foundNotification?.enabled == true ? "bell.slash" : "bell.and.waves.left.and.right") }.buttonStyle(.bordered)
            if ["apple", "fusion"].contains(current.provider) {
                Button(role: .destructive) { showRecoveryConfirm = true } label: { Label("Recovery Guard aktivieren", systemImage: "lifepreserver.fill") }.buttonStyle(.bordered).confirmationDialog("Recovery Guard starten?", isPresented: $showRecoveryConfirm, titleVisibility: .visible) {
                    Button("Aktivieren", role: .destructive) { Task { await startRecovery() } }; Button("Abbrechen", role: .cancel) { }
                } message: { Text("Der Server beginnt einen Recovery-Fall für diesen Tracker. Das ist kein offizieller Apple-Lost-Mode.") }
            }
        }.rjCard()
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Technische Details").font(.headline)
            LabeledContent("Referenz", value: current.ref)
            LabeledContent("Batterie", value: current.battery ?? "Unbekannt")
            LabeledContent("Verlauf", value: current.historyActive == true ? "Aktiv" : "Aus")
            if let status = current.status, !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.secondary) }
        }.rjCard()
    }

    private func toggleFound() async {
        working = true; defer { working = false }
        do { _ = try await APIClient.shared.action("set_found_notification", payload: ["tracker": current.ref, "enabled": current.foundNotification?.enabled != true, "mode": "once"]); await model.refresh(); Haptics.success() }
        catch { model.errorMessage = error.localizedDescription }
    }

    private func startRecovery() async {
        do { _ = try await APIClient.shared.action("start_recovery", payload: ["tracker": current.ref, "confirmed": true]); await model.refresh(); Haptics.success() }
        catch { model.errorMessage = error.localizedDescription }
    }

    private func openMaps(_ location: TrackerLocation) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate)); item.name = current.name; item.openInMaps()
    }
}
