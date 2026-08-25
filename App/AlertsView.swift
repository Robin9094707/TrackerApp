import SwiftUI

struct AlertsView: View {
    @Environment(AppModel.self) private var model
    private var events: [AlertEvent] { model.bootstrap?.alerts?.events ?? [] }

    var body: some View {
        List {
            if let push = model.bootstrap?.push {
                Section("Native Benachrichtigungen") {
                    LabeledContent("iPhone registriert", value: "\(push.activeDevices ?? 0)")
                    LabeledContent("APNs-Server", value: push.serverConfigured == true ? "Bereit" : "Noch nicht konfiguriert")
                    if push.serverConfigured != true { Label("Ohne .p8 Push-Key zeigt die App neue Server-Ereignisse nativ an, sobald sie synchronisiert. Für Push im geschlossenen Zustand APNs im Backend konfigurieren.", systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            Section("Ereignisse") {
                if events.isEmpty { ContentUnavailableView("Keine Meldungen", systemImage: "bell.slash") }
                ForEach(events) { event in
                    Button { Task { await acknowledge(event) } } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: symbol(event))
                                .font(.title3)
                                .foregroundStyle(event.acknowledged == true ? Color.secondary : Color.accentColor)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) { HStack { Text(event.title ?? "Tracker-Ereignis").font(.headline); if event.acknowledged != true { Circle().fill(.tint).frame(width: 7, height: 7) } }; Text(event.body ?? "").font(.subheadline).foregroundStyle(.secondary); if let ts = Date.fromUnix(event.ts) { Text(ts, style: .relative).font(.caption2).foregroundStyle(.tertiary) } }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }.navigationTitle("Meldungen").refreshable { await model.refresh() }
    }

    private func symbol(_ event: AlertEvent) -> String { switch event.severity?.lowercased() { case "critical": "exclamationmark.triangle.fill"; case "high", "warning": "bell.badge.fill"; default: "bell.fill" } }
    private func acknowledge(_ event: AlertEvent) async { guard event.acknowledged != true else { return }; do { _ = try await APIClient.shared.action("acknowledge_event", payload: ["event_id": event.id, "acknowledged": true]); await model.refresh() } catch { model.errorMessage = error.localizedDescription } }
}
