import SwiftUI

struct TrackerHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var provider = "all"

    var body: some View {
        List {
            Section {
                Picker("Netz", selection: $provider) {
                    Text("Alle").tag("all"); Text("Fusion").tag("fusion"); Text("Apple").tag("apple"); Text("Google").tag("google"); Text("Samsung").tag("samsung")
                }.pickerStyle(.segmented).onChange(of: provider) { _, new in model.providerFilter = new }
            }.listRowBackground(Color.clear)

            Section("\(model.filteredTrackers.count) Tracker") {
                if model.filteredTrackers.isEmpty { ContentUnavailableView("Keine Tracker", systemImage: "location.slash", description: Text("Passe Suche oder Filter an.")) }
                ForEach(model.filteredTrackers) { tracker in
                    NavigationLink(value: tracker) { TrackerRow(tracker: tracker) }
                }
            }
        }
        .navigationTitle("Tracker")
        .searchable(text: Binding(get: { model.searchText }, set: { model.searchText = $0 }), prompt: "Tracker suchen")
        .navigationDestination(for: Tracker.self) { TrackerDetailView(tracker: $0) }
        .refreshable { await model.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { Task { await model.locateAll() } } label: { Image(systemName: "arrow.clockwise") }.disabled(model.isRefreshing) }
        }
    }
}

struct TrackerRow: View {
    let tracker: Tracker
    var body: some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(.secondary.opacity(0.12)); Text(tracker.emoji ?? "📍").font(.title2) }.frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(tracker.name).font(.headline); if tracker.provider == "fusion" { Image(systemName: "sparkles").foregroundStyle(.tint) } }
                Text(tracker.location?.address?.bestText.isEmpty == false ? tracker.location!.address!.bestText : locationSubtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 8) { ProviderBadge(provider: tracker.provider); if let ts = Date.fromUnix(tracker.lastSeenTs) { Text(ts, style: .relative).font(.caption).foregroundStyle(.secondary) } }
            }
        }.padding(.vertical, 4)
    }
    private var locationSubtitle: String { tracker.location == nil ? "Noch kein Standort" : "±\(Int((tracker.location?.accuracyM ?? 0).rounded())) m" }
}
