import SwiftUI

struct ArchiveView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [Tracker] = []
    @State private var loading = false
    @State private var updating: String?
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Text("Archivierte und ausgeblendete Objekte bleiben auf deinem Server erhalten. Du kannst sie hier wieder in die Objektliste aufnehmen.").font(.subheadline).foregroundStyle(.secondary)
            }
            if loading { ProgressView() }
            if !loading && items.isEmpty && error == nil { ContentUnavailableView("Alles sichtbar", systemImage: "archivebox", description: Text("Es gibt keine archivierten oder ausgeblendeten Objekte.")) }
            ForEach(items) { tracker in
                HStack(spacing: 12) {
                    Text(tracker.emoji ?? "📍").font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tracker.name).font(.headline)
                        Text("\(tracker.provider.rjProviderName) · \(tracker.archived == true ? "Archiviert" : "Ausgeblendet")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await restore(tracker) } } label: {
                        if updating == tracker.ref { ProgressView() } else { Image(systemName: "arrow.uturn.backward.circle") }
                    }.disabled(updating != nil).accessibilityLabel("\(tracker.name) wiederherstellen")
                }.padding(.vertical, 6)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Archiv & ausgeblendet").navigationBarTitleDisplayMode(.inline)
            .task { await load() }.refreshable { await load() }
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            let catalog: TrackerCatalogResponse = try await APIClient.shared.request(path: "/api/mobile/v1/trackers", query: [URLQueryItem(name: "include_hidden", value: "1"), URLQueryItem(name: "include_archived", value: "1"), URLQueryItem(name: "limit", value: "1000")])
            items = catalog.trackers.filter { $0.hidden == true || $0.archived == true }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch { self.error = error.localizedDescription }
    }
    private func restore(_ tracker: Tracker) async {
        updating = tracker.ref; defer { updating = nil }
        do {
            _ = try await APIClient.shared.requestJSON(path: "/api/v2/trackers/\(tracker.provider)/\(tracker.apiID)/preferences", method: "POST", json: ["archived": false, "hidden": false])
            await model.refresh(); await load()
        } catch { self.error = error.localizedDescription }
    }
}
