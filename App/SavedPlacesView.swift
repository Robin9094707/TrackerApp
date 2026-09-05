import SwiftUI

struct SavedPlacesView: View {
    @Environment(AppModel.self) private var model
    @State private var showNew = false

    var body: some View {
        List {
            if (model.bootstrap?.savedPlaces ?? []).isEmpty {
                ContentUnavailableView("Keine gespeicherten Orte", systemImage: "star.slash")
                    .listRowBackground(Color.clear)
            }

            ForEach(model.bootstrap?.savedPlaces ?? []) { place in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.accentColor.opacity(0.11))
                        Text(place.emoji ?? "📍").font(.title2)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.label).font(.headline)
                        if let note = place.note, !note.isEmpty {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .swipeActions {
                    Button("Löschen", role: .destructive) { Task { await removePlace(place) } }
                }
            }
        }
        .rjListChrome()
        .navigationTitle("Gespeicherte Orte")
        .toolbar {
            Button { showNew = true } label: {
                Image(systemName: "plus")
                    .rjGlassControl()
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showNew) { NavigationStack { NewSavedPlaceView() } }
        .refreshable { await model.refresh() }
    }

    private func removePlace(_ place: SavedPlace) async {
        do {
            _ = try await APIClient.shared.action("delete_saved_place", payload: ["place": place.id])
            await model.refresh()
            Haptics.success()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

struct NewSavedPlaceView: View {
    var body: some View { PlaceEditorView() }
}
