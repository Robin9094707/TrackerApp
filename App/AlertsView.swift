import SwiftUI

struct AlertsView: View {
    @Environment(AppModel.self) private var model
    @State private var unreadOnly = false
    @State private var busy = false
    private var events: [AlertEvent] {
        (model.bootstrap?.alerts?.events ?? []).filter { !unreadOnly || $0.acknowledged != true }.sorted { ($0.ts ?? 0) > ($1.ts ?? 0) }
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
            Section {
                NavigationLink { SettingsView() } label: { Label("Mitteilungen einrichten", systemImage: "gearshape") }
            }
        }
        .navigationTitle("Meldungen").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { Task { await acknowledge(events.filter { $0.acknowledged != true }) } } label: { Image(systemName: "checkmark.circle") }
                .disabled(busy || !events.contains { $0.acknowledged != true }).accessibilityLabel("Angezeigte Meldungen als gelesen markieren")
        }
        .refreshable { await model.refresh() }
    }
    private func acknowledge(_ events: [AlertEvent]) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            for event in events where event.acknowledged != true {
                _ = try await APIClient.shared.action("acknowledge_event", payload: ["event_id": event.id, "acknowledged": true])
            }
            await model.refresh()
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
        .navigationTitle("Meldung").navigationBarTitleDisplayMode(.inline)
        .task {
            guard event.acknowledged != true else { return }
            do { try await model.runAction("acknowledge_event", payload: ["event_id": event.id, "acknowledged": true]) }
            catch { model.errorMessage = error.localizedDescription }
        }
    }
}
