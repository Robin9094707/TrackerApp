import SwiftUI
import MapKit

struct GeofencesView: View {
    @Environment(AppModel.self) private var model
    @State private var showNew = false
    var fences: [Geofence] { model.bootstrap?.geofences ?? [] }

    var body: some View {
        List {
            Section {
                Map {
                    ForEach(fences) { fence in
                        MapCircle(center: fence.center.coordinate, radius: fence.radiusM ?? 100).foregroundStyle(.tint.opacity(0.10))
                        Marker(fence.label, coordinate: fence.center.coordinate)
                    }
                }.frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }.listRowBackground(Color.clear)
            Section("Orte") {
                if fences.isEmpty { ContentUnavailableView("Keine Geofences", systemImage: "mappin.slash") }
                ForEach(fences) { fence in
                    NavigationLink { GeofenceDetailView(fence: fence) } label: { HStack { Text(fence.emoji ?? "📍").font(.title2); VStack(alignment: .leading) { Text(fence.label).font(.headline); Text("Radius \((fence.radiusM ?? 0).metersText) · \(fence.enabled == true ? "aktiv" : "aus")").font(.caption).foregroundStyle(.secondary) } } }
                }
            }
        }.navigationTitle("Geofences").toolbar { Button { showNew = true } label: { Image(systemName: "plus") } }.sheet(isPresented: $showNew) { NavigationStack { NewGeofenceView() } }.refreshable { await model.refresh() }
    }
}

struct NewGeofenceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""; @State private var latitude = ""; @State private var longitude = ""; @State private var radius = 150.0
    var body: some View {
        Form {
            Section("Ort") { TextField("Name", text: $label); TextField("Breitengrad", text: $latitude).keyboardType(.numbersAndPunctuation); TextField("Längengrad", text: $longitude).keyboardType(.numbersAndPunctuation); LabeledContent("Radius", value: radius.metersText); Slider(value: $radius, in: 25...1000, step: 25) }
            Section { Text("Tipp: Koordinaten kannst du aus Apple Karten kopieren. Der Geofence wird serverseitig ausgewertet und gilt für alle Tracker, solange du keine Tracker-Auswahl über die erweiterten Werkzeuge setzt.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Neuer Geofence").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Speichern") { Task { await save() } }.disabled(label.isEmpty || Double(latitude) == nil || Double(longitude) == nil) } }
    }
    private func save() async { guard let lat = Double(latitude), let lon = Double(longitude) else { return }; do { _ = try await APIClient.shared.action("create_geofence", payload: ["label": label, "latitude": lat, "longitude": lon, "radius_m": radius, "notify_enter": true, "notify_exit": true, "enabled": true]); await model.refresh(); dismiss(); Haptics.success() } catch { model.errorMessage = error.localizedDescription } }
}

struct GeofenceDetailView: View {
    @Environment(AppModel.self) private var model
    let fence: Geofence
    @State private var deleteConfirm = false
    var body: some View {
        Form {
            Section { Map { MapCircle(center: fence.center.coordinate, radius: fence.radiusM ?? 100).foregroundStyle(.tint.opacity(0.12)); Marker(fence.label, coordinate: fence.center.coordinate) }.frame(height: 260) }
            Section("Details") { LabeledContent("Radius", value: (fence.radiusM ?? 0).metersText); LabeledContent("Betreten", value: fence.notifyEnter == true ? "Melden" : "Aus"); LabeledContent("Verlassen", value: fence.notifyExit == true ? "Melden" : "Aus"); Toggle("Aktiv", isOn: Binding(get: { fence.enabled == true }, set: { value in Task { await toggle(value) } })) }
            Section { Button("Geofence löschen", role: .destructive) { deleteConfirm = true } }
        }.navigationTitle(fence.label).confirmationDialog("Geofence wirklich löschen?", isPresented: $deleteConfirm) { Button("Löschen", role: .destructive) { Task { await remove() } }; Button("Abbrechen", role: .cancel) {} }
    }
    private func toggle(_ value: Bool) async { do { _ = try await APIClient.shared.action("update_geofence", payload: ["geofence": fence.id, "enabled": value]); await model.refresh() } catch { model.errorMessage = error.localizedDescription } }
    private func remove() async { do { _ = try await APIClient.shared.action("delete_geofence", payload: ["geofence": fence.id]); await model.refresh() } catch { model.errorMessage = error.localizedDescription } }
}
