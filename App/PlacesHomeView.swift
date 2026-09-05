import SwiftUI
import MapKit

struct PlacesHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var newPlace = false
    @State private var newFence = false
    var body: some View {
        List {
            Section("Gespeicherte Orte") {
                if (model.bootstrap?.savedPlaces ?? []).isEmpty {
                    Label("Deine wichtigen Orte erscheinen hier.", systemImage: "star").foregroundStyle(.secondary)
                }
                ForEach(model.bootstrap?.savedPlaces ?? []) { place in
                    NavigationLink { SavedPlaceDetailView(place: place) } label: {
                        Label { Text(place.label) } icon: { Text(place.emoji ?? "📍") }
                    }
                }
            }
            Section("Geofences") {
                if (model.bootstrap?.geofences ?? []).isEmpty {
                    Label("Lass dir Betreten oder Verlassen melden.", systemImage: "mappin.and.ellipse").foregroundStyle(.secondary)
                }
                ForEach(model.bootstrap?.geofences ?? []) { fence in
                    NavigationLink { GeofenceDetailView(fence: fence) } label: {
                        HStack {
                            Text(fence.emoji ?? "📍")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(fence.label)
                                Text("\((fence.radiusM ?? 100).metersText) · \(fence.enabled == true ? "Aktiv" : "Pausiert")").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Orte").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Ort speichern", systemImage: "star") { newPlace = true }
                Button("Geofence erstellen", systemImage: "mappin.and.ellipse") { newFence = true }
            } label: { Image(systemName: "plus") }.accessibilityLabel("Ort hinzufügen")
        }
        .sheet(isPresented: $newPlace) { NavigationStack { PlaceEditorView() } }
        .sheet(isPresented: $newFence) { NavigationStack { PlaceEditorView(geofence: true) } }
        .refreshable { await model.refresh() }
    }
}

struct SavedPlaceDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let place: SavedPlace
    @State private var edit = false
    @State private var confirmDelete = false
    @State private var busy = false
    private var current: SavedPlace { model.bootstrap?.savedPlaces?.first { $0.id == place.id } ?? place }
    private var location: TrackerLocation? {
        guard let lat = current.latitude, let lon = current.longitude else { return nil }
        return TrackerLocation(latitude: lat, longitude: lon)
    }
    var body: some View {
        List {
            if let location {
                Map {
                    Marker(current.label, coordinate: location.coordinate)
                    MapCircle(center: location.coordinate, radius: current.radiusM ?? 100).foregroundStyle(.blue.opacity(0.1))
                }.frame(height: 230).listRowInsets(EdgeInsets())
                Section {
                    Button("In Apple Karten öffnen", systemImage: "map") {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
                        item.name = current.label; item.openInMaps()
                    }
                    LabeledContent("Radius", value: (current.radiusM ?? 100).metersText)
                    if let note = current.note, !note.isEmpty { Text(note) }
                }
            }
            Section { Button("Ort löschen", role: .destructive) { confirmDelete = true }.disabled(busy) }
        }
        .navigationTitle(current.label).navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Bearbeiten") { edit = true } }
        .sheet(isPresented: $edit) { NavigationStack { PlaceEditorView(seed: location, suggestedName: current.label, existing: current) } }
        .confirmationDialog("Diesen gespeicherten Ort löschen?", isPresented: $confirmDelete) {
            Button("Ort löschen", role: .destructive) {
                busy = true
                Task {
                    defer { busy = false }
                    do { try await model.runAction("delete_saved_place", payload: ["place": current.id]); dismiss() }
                    catch { model.errorMessage = error.localizedDescription }
                }
            }
        }
    }
}

struct PlaceEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var geofence = false
    var trackerRef: String?
    var existing: SavedPlace?
    @State private var name: String
    @State private var note: String
    @State private var emoji: String
    @State private var radius: Double
    @State private var point: TrackerLocation?
    @State private var position: MapCameraPosition
    @State private var notifyEnter = true
    @State private var notifyExit = true
    @State private var busy = false
    @State private var error: String?

    init(seed: TrackerLocation? = nil, suggestedName: String = "", geofence: Bool = false, trackerRef: String? = nil, existing: SavedPlace? = nil) {
        self.geofence = geofence; self.trackerRef = trackerRef; self.existing = existing
        _name = State(initialValue: suggestedName)
        _note = State(initialValue: existing?.note ?? "")
        _emoji = State(initialValue: existing?.emoji ?? "📍")
        _radius = State(initialValue: min(max(existing?.radiusM ?? 150, 25), 5000))
        _point = State(initialValue: seed)
        _position = State(initialValue: seed.map { .region(RJMapCamera.focusedRegion(for: $0, zoomMeters: 1500)) } ?? .automatic)
    }

    var body: some View {
        Form {
            Section {
                MapReader { proxy in
                    Map(position: $position) {
                        if let point {
                            Marker(name.isEmpty ? "Neuer Ort" : name, coordinate: point.coordinate)
                            MapCircle(center: point.coordinate, radius: radius).foregroundStyle(.blue.opacity(0.12)).stroke(.blue.opacity(0.5), lineWidth: 1)
                        }
                    }
                    .onTapGesture { screenPoint in
                        guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                        point = TrackerLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    }
                    .frame(height: 240)
                    .accessibilityLabel("Tippe auf die Karte, um den Mittelpunkt zu setzen")
                }.listRowInsets(EdgeInsets())
                Menu("Standort eines Trackers verwenden", systemImage: "airtag") {
                    ForEach(model.trackers.filter { $0.validLocation != nil }) { tracker in
                        Button(tracker.name) {
                            point = tracker.validLocation
                            if let point { position = .region(RJMapCamera.focusedRegion(for: point, zoomMeters: 1500)) }
                        }
                    }
                }
                if let point {
                    Text(String(format: "%.5f, %.5f", point.latitude, point.longitude)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else { Text("Tippe den gewünschten Ort auf der Karte an.").font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Details") {
                TextField("Name", text: $name)
                TextField("Symbol", text: $emoji)
                LabeledContent("Radius", value: radius.metersText)
                Slider(value: $radius, in: 25...5000, step: 25)
                if !geofence { TextField("Notiz", text: $note, axis: .vertical).lineLimit(2...4) }
            }
            if geofence {
                Section {
                    Toggle("Betreten melden", isOn: $notifyEnter)
                    Toggle("Verlassen melden", isOn: $notifyExit)
                    Text(trackerRef == nil ? "Gilt für alle Tracker." : "Gilt für dieses Objekt und seine verknüpften Quellen.").font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Benachrichtigungen") }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(geofence ? "Neuer Geofence" : "Ort speichern").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.disabled(busy) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { Task { await save() } }
                    .disabled(busy || point == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80 || note.count > 240)
            }
        }
        .interactiveDismissDisabled(busy)
    }
    private func save() async {
        guard let point, CLLocationCoordinate2DIsValid(point.coordinate), !busy else { return }
        busy = true; defer { busy = false }
        var payload: [String: Any] = ["label": name.trimmingCharacters(in: .whitespacesAndNewlines), "emoji": emoji, "latitude": point.latitude, "longitude": point.longitude, "radius_m": radius, "note": note]
        if let existing { payload["place_id"] = existing.id }
        if geofence {
            payload["notify_enter"] = notifyEnter; payload["notify_exit"] = notifyExit
            payload["trackers"] = trackerRef.map { [$0] } ?? []
            payload["enabled"] = true
        }
        do { try await model.runAction(geofence ? "create_geofence" : "upsert_saved_place", payload: payload); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
