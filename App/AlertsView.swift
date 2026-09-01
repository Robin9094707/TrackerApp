import SwiftUI

struct AlertsView: View {
    @Environment(AppModel.self) private var model
    private var events: [AlertEvent] { model.bootstrap?.alerts?.events ?? [] }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                pushCard
                eventsCard
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .rjScreenChrome()
        .navigationTitle("Meldungen")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.refresh() }
    }

    @ViewBuilder
    private var pushCard: some View {
        if let push = model.bootstrap?.push {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    RJSectionTitle(title: "Native Benachrichtigungen", subtitle: "Push & lokale Synchronisierung", symbol: "bell.badge.fill")
                    Spacer()
                    RJStatusPill(
                        text: push.serverConfigured == true ? "Bereit" : "Lokal",
                        symbol: push.serverConfigured == true ? "checkmark.circle.fill" : "iphone",
                        tint: push.serverConfigured == true ? .green : .orange
                    )
                }
                Divider()
                LabeledContent("iPhone registriert", value: "\(push.activeDevices ?? 0)")
                LabeledContent("APNs-Server", value: push.serverConfigured == true ? "Bereit" : "Noch nicht konfiguriert")
                if push.serverConfigured != true {
                    Label(
                        "Ohne APNs-Push-Key zeigt die App neue Server-Ereignisse nativ an, sobald sie synchronisiert. Für Push im geschlossenen Zustand APNs im Backend konfigurieren.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .rjCard()
        }
    }

    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            RJSectionTitle(title: "Ereignisse", subtitle: "\(events.count) Meldungen", symbol: "bell.fill")
                .padding(.bottom, 10)

            if events.isEmpty {
                ContentUnavailableView("Keine Meldungen", systemImage: "bell.slash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                Divider()
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    Button { Task { await acknowledge(event) } } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: symbol(event))
                                .font(.title3)
                                .foregroundStyle(event.acknowledged == true ? Color.secondary : Color.accentColor)
                                .frame(width: 34, height: 34)
                                .background(
                                    (event.acknowledged == true ? Color.secondary : Color.accentColor).opacity(0.10),
                                    in: Circle()
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(event.title ?? "Tracker-Ereignis")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if event.acknowledged != true {
                                        Circle().fill(.tint).frame(width: 7, height: 7)
                                    }
                                }
                                Text(event.body ?? "")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let ts = Date.fromUnix(event.ts) {
                                    Text(ts.rjTimelineText)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer(minLength: 4)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < events.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
        .rjCard()
    }

    private func symbol(_ event: AlertEvent) -> String {
        switch event.severity?.lowercased() {
        case "critical": "exclamationmark.triangle.fill"
        case "high", "warning": "bell.badge.fill"
        default: "bell.fill"
        }
    }

    private func acknowledge(_ event: AlertEvent) async {
        guard event.acknowledged != true else { return }
        do {
            _ = try await APIClient.shared.action("acknowledge_event", payload: ["event_id": event.id, "acknowledged": true])
            await model.refresh()
            Haptics.success()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
