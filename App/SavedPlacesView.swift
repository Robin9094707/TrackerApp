import SwiftUI

struct SavedPlacesView: View {
    @Environment(AppModel.self) private var model
    @State private var showNew = false
    var body: some View {
        List {
            ForEach(model.bootstrap?.savedPlaces ?? []) { place in
                HStack { Text(place.emoji ?? "📍").font(.title2); VStack(alignment: .leading) { Text(place.label).font(.headline); if let note = place.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) } } }
                .swipeActions { Button("Löschen", role: .destructive) { Task { await delete(place) } } }
            }
        }.navigationTitle("Gespeicherte Orte").toolbar { Button { showNew = true } label: { Image(systemName: "plus") } }.sheet(isPresented: $showNew) { NavigationStack { NewSavedPlaceView() } }
    }
    private func delete(_ place: SavedPlace) async { do { _ = try await APIClient.shared.action("delete_saved_place", payload: ["place": place.id]); await model.refresh() } catch { model.errorMessage = error.localizedDescription } }
}

struct NewSavedPlaceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""; @State private var lat = ""; @State private var lon = ""; @State private var note = ""
    var body: some View { Form { Section("Ort") { TextField("Name", text: $label); TextField("Breitengrad", text: $lat).keyboardType(.numbersAndPunctuation); TextField("Längengrad", text: $lon).keyboardType(.numbersAndPunctuation); TextField("Notiz", text: $note) } }.navigationTitle("Ort speichern").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Speichern") { Task { await save() } } } } }
    private func save() async { guard let a = Double(lat), let b = Double(lon), !label.isEmpty else { return }; do { _ = try await APIClient.shared.action("upsert_saved_place", payload: ["label": label, "latitude": a, "longitude": b, "note": note, "radius_m": 100]); await model.refresh(); dismiss() } catch { model.errorMessage = error.localizedDescription } }
}
