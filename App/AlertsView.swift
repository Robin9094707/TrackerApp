import SwiftUI

struct AlertsView: View {
    @Environment(AppModel.self) private var model
    @State private var unreadOnly = false
    @State private var busy = false
    @State private var search = ""
    @State private var limit = 150
    private var events: [AlertEvent] {
        (model.bootstrap?.alerts?.events ?? []).filter { (!unreadOnly || $0.acknowledged != true) && (search.isEmpty || (($0.title ?? "") + " " + ($0.body ?? "")).localizedCaseInsensitiveContains(search)) }.sorted { ($0.ts ?? 0) > ($1.ts ?? 0) }
    }
    var body: some View {
        List {
            Section {
                Picker("Meldungen", selection: $unreadOnly) {
                    Text("Alle").tag(false); Text("Ungelesen").tag(true)
                }.pickerStyle(.segmented).listRowBackground(Color.clear)
            }
            if events.isEmpty {
                ContentUnavailableView(unreadOnly ? "Alles gelesen" : "Keine Meldungen", systemImage: "bell.badge", description: Text("Fundmeldungen und Geofence-Ereignisse erscheinen hier."))
            }
            ForEach(events) { event in
                NavigationLink { AlertDetailView(event: event) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: event.severity == "critical" ? "exclamationmark.triangle.fill" : "bell.fill")
                            .foregroundStyle(event.acknowledged == true ? Color.secondary : .blue).frame(width: 28)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(event.title ?? "Tracker-Ereignis").font(.headline)
                            Text(event.body ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                            if let date = Date.fromUnix(event.ts) { Text(date.rjTimelineText).font(.caption).foregroundStyle(.secondary) }
                        }
                        if event.acknowledged != true { Circle().fill(.blue).frame(width: 7, height: 7) }
                    }.padding(.vertical, 6)
                }
                .swipeActions {
                    Button { Task { await acknowledge([event]) } } label: { Label("Gelesen", systemImage: "checkmark") }.tint(.blue)
                }
            }
            if (model.bootstrap?.alerts?.eventCount ?? 0) > (model.bootstrap?.alerts?.events?.count ?? 0), limit < 500 {
                Button("Ältere Meldungen laden") { limit = 500; Task { await model.refreshAlerts(limit: limit) } }.disabled(model.isRefreshingAlerts)
            }
            Section {
                NavigationLink { SettingsView() } label: { Label("Mitteilungen einrichten", systemImage: "gearshape") }
            }
        }
        .scrollContentBackground(.hidden).rjScreenChrome().navigationTitle("Meldungen").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { Task { await acknowledge(events.filter { $0.acknowledged != true }) } } label: { Image(systemName: "checkmark.circle") }
                .disabled(busy || !events.contains { $0.acknowledged != true }).accessibilityLabel("Angezeigte Meldungen als gelesen markieren")
        }
        .searchable(text: $search, prompt: "Meldungen durchsuchen")
        .task { await model.refreshAlerts(limit: limit) }
        .refreshable { await model.refreshAlerts(limit: limit) }
    }
    private func acknowledge(_ events: [AlertEvent]) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            for event in events where event.acknowledged != true {
                _ = try await APIClient.shared.action("acknowledge_event", payload: ["event_id": event.id, "acknowledged": true])
                if let index = model.bootstrap?.alerts?.events?.firstIndex(where: { $0.id == event.id }) { model.bootstrap?.alerts?.events?[index].acknowledged = true }
                model.bootstrap?.alerts?.unreadCount = max(0, (model.bootstrap?.alerts?.unreadCount ?? 0) - 1)
            }
            await model.refreshAlerts(limit: limit)
        } catch { model.errorMessage = error.localizedDescription }
    }
}

struct AlertDetailView: View {
    @Environment(AppModel.self) private var model
    let event: AlertEvent
    var body: some View {
        List {
            Section {
                Text(event.title ?? "Tracker-Ereignis").font(.title2.bold())
                Text(event.body ?? "").textSelection(.enabled)
                if let date = Date.fromUnix(event.ts) { Text(date.rjTimelineText).font(.caption).foregroundStyle(.secondary) }
            }
            if let tracker = model.trackers.first(where: { $0.ref == event.trackerRef }) {
                NavigationLink { TrackerDetailView(tracker: tracker) } label: { Label(tracker.name, systemImage: "airtag") }
            }
        }
        .scrollContentBackground(.hidden).rjScreenChrome().navigationTitle("Meldung").navigationBarTitleDisplayMode(.inline)
        .task {
            guard event.acknowledged != true else { return }
            do { try await model.runAction("acknowledge_event", payload: ["event_id": event.id, "acknowledged": true]) }
            catch { model.errorMessage = error.localizedDescription }
        }
    }
}

