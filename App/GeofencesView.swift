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
                        MapCircle(center: fence.center.coordinate, radius: fence.radiusM ?? 100)
                            .foregroundStyle(.tint.opacity(0.08))
                            .stroke(.tint.opacity(0.35), lineWidth: 1)
                        Marker(fence.label, coordinate: fence.center.coordinate)
                    }
                }
                .frame(height: 270)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .listRowBackground(Color.clear)

            Section("Orte") {
                if fences.isEmpty { ContentUnavailableView("Keine Geofences", systemImage: "mappin.slash") }
                ForEach(fences) { fence in
                    NavigationLink { GeofenceDetailView(fence: fence) } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.accentColor.opacity(0.11))
                                Text(fence.emoji ?? "📍").font(.title2)
                            }
                            .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(fence.label).font(.headline)
                                Text("Radius \((fence.radiusM ?? 0).metersText) · \(fence.enabled == true ? "aktiv" : "aus")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        .rjListChrome()
        .navigationTitle("Geofences")
        .toolbar {
            Button { showNew = true } label: {
                Image(systemName: "plus")
                    .rjGlassControl()
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showNew) { NavigationStack { NewGeofenceView() } }
        .refreshable { await model.refresh() }
    }
}

struct NewGeofenceView: View {
    var body: some View { PlaceEditorView(geofence: true) }
}

struct GeofenceDetailView: View {
    @Environment(AppModel.self) private var model
    let fence: Geofence
    @Environment(\.dismiss) private var dismiss
    private var current: Geofence { model.bootstrap?.geofences?.first { $0.id == fence.id } ?? fence }
    @State private var deleteConfirm = false

    var body: some View {
        Form {
            Section {
                Map {
                    MapCircle(center: fence.center.coordinate, radius: fence.radiusM ?? 100)
                        .foregroundStyle(.tint.opacity(0.10))
                        .stroke(.tint.opacity(0.35), lineWidth: 1)
                    Marker(fence.label, coordinate: fence.center.coordinate)
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .listRowBackground(Color.clear)

            Section("Details") {
                LabeledContent("Radius", value: (fence.radiusM ?? 0).metersText)
                LabeledContent("Betreten", value: fence.notifyEnter == true ? "Melden" : "Aus")
                LabeledContent("Verlassen", value: fence.notifyExit == true ? "Melden" : "Aus")
                Toggle("Aktiv", isOn: Binding(get: { current.enabled == true }, set: { value in Task { await toggle(value) } }))
            }
            .listRowBackground(Color.clear)

            Section {
                Button("Geofence löschen", role: .destructive) { deleteConfirm = true }
            }
            .listRowBackground(Color.clear)
        }
        .rjFormChrome()
        .navigationTitle(fence.label)
        .confirmationDialog("Geofence wirklich löschen?", isPresented: $deleteConfirm) {
            Button("Löschen", role: .destructive) { Task { await removeFence() } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private func toggle(_ value: Bool) async {
        do {
            _ = try await APIClient.shared.action("update_geofence", payload: ["geofence": fence.id, "enabled": value])
            await model.refresh()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func removeFence() async {
        do {
            _ = try await APIClient.shared.action("delete_geofence", payload: ["geofence": fence.id])
            await model.refresh()
            dismiss()
            Haptics.success()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

